import Combine
import CatPuzzleCore

/// Drives the one scripted tutorial board. Owns its own `GameEngine` rather
/// than wrapping `GameViewModel`, so the tutorial's coaching state never
/// leaks back into ordinary gameplay's view model — see `Docs/Tutorial.md`
/// for the script/coaching design this consumes. Tap/drag disambiguation is
/// shared with `GameViewModel` through `CellInputCoordinator` rather than
/// reimplemented here.
@MainActor
final class TutorialViewModel: ObservableObject {
    let level: LevelDefinition

    @Published private(set) var puzzle: Puzzle
    @Published private(set) var isSolved: Bool
    @Published private(set) var isFailed: Bool
    @Published private(set) var previewStates: [CellPosition: CellState] = [:]
    @Published private(set) var markerFeedbackSequence = 0
    @Published private(set) var feedbackMessage: String?

    /// The scripted step the tutorial is waiting on, or nil once the script
    /// is finished.
    @Published private(set) var step: TutorialStep?
    /// 1-based position of `step` in the script.
    @Published private(set) var stepNumber = 0
    var stepCount: Int { coach.stepCount }
    var guidedStepCount: Int {
        coach.script.steps.prefix { $0.coaching == .guided }.count
    }
    var placedCatCount: Int { puzzle.states.filter { $0 == .cat }.count }
    /// The single cell revealed when the player requests a discovery hint.
    @Published private(set) var nudgedPositions: Set<CellPosition> = []
    @Published private(set) var isAutoMarking = false
    @Published private(set) var autoMarkedPosition: CellPosition?

    /// Cells the board leaves lit while masking the rest. Empty when nothing
    /// is masked, which is every moment but a guided step.
    var spotlight: Set<CellPosition> {
        guard let step, step.coaching == .guided else { return [] }
        return Set(step.spotlight)
    }

    /// The only cells a guided step lets the player touch — narrower than
    /// the spotlight, which lights up the whole row, column or block being
    /// explained. Nil when every cell is live.
    var interactivePositions: Set<CellPosition>? {
        guard let step, step.coaching == .guided else { return nil }
        return Set(step.remainingPositions(in: puzzle))
    }

    var guidedTarget: CellPosition? {
        guard let step, step.coaching == .guided else { return nil }
        return step.remainingPositions(in: puzzle).first
    }

    /// Replays the hand whenever one guided mark makes its next target change.
    var guidancePlaybackID: Int {
        guard let step else { return 0 }
        return stepNumber * 100 + step.remainingPositions(in: puzzle).count
    }

    private var engine: GameEngine
    private let coach: TutorialCoach
    private let tutorialCatPositions: Set<CellPosition>
    private let input: CellInputCoordinator
    private let soundPlayer: any PuzzleSoundPlaying
    private let onGameStateChanged: (GameState) -> Void
    private let autoMarkInterval: Duration
    private var autoMarkTask: Task<Void, Never>?
    private var autoMarkGeneration = 0

    /// `script` is required and assumed non-empty — callers only build a
    /// `TutorialViewModel` when `TutorialScript.isEmpty == false`, falling
    /// back to a plain `GameViewModel` otherwise (an unscripted board is
    /// simply played, not coached wrongly).
    init(
        engine: GameEngine,
        script: TutorialScript,
        doubleTapInterval: Duration = .milliseconds(300),
        autoMarkInterval: Duration = .milliseconds(220),
        soundPlayer: any PuzzleSoundPlaying = PuzzleSoundPlayer.shared,
        onGameStateChanged: @escaping (GameState) -> Void = { _ in }
    ) {
        self.engine = engine
        self.level = engine.state.level
        self.coach = TutorialCoach(script: script)
        self.tutorialCatPositions = Set(script.steps.compactMap { step in
            if case let .placeCat(position) = step.task { return position }
            return nil
        })
        self.soundPlayer = soundPlayer
        self.onGameStateChanged = onGameStateChanged
        self.autoMarkInterval = autoMarkInterval
        self.input = CellInputCoordinator(
            doubleTapInterval: doubleTapInterval,
            soundPlayer: soundPlayer
        )

        puzzle = engine.state.puzzle
        isSolved = engine.state.isSolved
        isFailed = engine.state.isFailed
        feedbackMessage = nil

        input.configure(
            onPreviewStatesChanged: { [weak self] in
                self?.previewStates = self?.input.previewStates ?? [:]
            },
            onMarkerFeedback: { [weak self] in
                self?.markerFeedbackSequence &+= 1
            }
        )
        refreshCoaching()
    }

    func displayState(atRow row: Int, column: Int) -> CellState? {
        let position = CellPosition(row: row, column: column)
        return previewStates[position]
            ?? puzzle.state(atRow: row, column: column)
    }

    func isLocked(atRow row: Int, column: Int) -> Bool {
        level.givenPositions.contains(CellPosition(row: row, column: column))
    }

    func handleCellTap(atRow row: Int, column: Int) {
        guard puzzle.state(atRow: row, column: column) != nil else {
            feedbackMessage = "That cell is outside the board."
            return
        }
        input.handleTap(
            at: CellPosition(row: row, column: column),
            environment: makeInputEnvironment()
        )
    }

    func toggleExcluded(atRow row: Int, column: Int) {
        input.toggleExcluded(
            at: CellPosition(row: row, column: column),
            environment: makeInputEnvironment()
        )
    }

    func toggleCat(atRow row: Int, column: Int) {
        input.toggleCat(
            at: CellPosition(row: row, column: column),
            environment: makeInputEnvironment()
        )
    }

    func setExcludedDuringDrag(
        _ excluded: Bool,
        atRow row: Int,
        column: Int
    ) {
        input.setExcludedDuringDrag(
            excluded,
            at: CellPosition(row: row, column: column),
            environment: makeInputEnvironment()
        )
    }

    func restart() {
        cancelAutoMarking()
        input.cancelAll()
        engine.restart()
        feedbackMessage = nil
        synchronizeFromEngine(notifyChange: true)
    }

    func revealClue() {
        guard !isAutoMarking,
              let step, step.coaching == .discovery,
              let position = step.remainingPositions(in: puzzle).first else {
            return
        }
        nudgedPositions = [position]
    }

    private func makeInputEnvironment() -> CellInputCoordinator.Environment {
        CellInputCoordinator.Environment(
            currentState: { [weak self] position in
                self?.puzzle.state(atRow: position.row, column: position.column)
            },
            isLocked: { [weak self] position in
                self?.isLocked(atRow: position.row, column: position.column) ?? true
            },
            isInteractable: { [weak self] position in
                guard let self else { return false }
                return !self.isAutoMarking && !self.isMasked(position)
            },
            commit: { [weak self] state, position, playSound in
                self?.apply(state, atRow: position.row, column: position.column, playSound: playSound)
            }
        )
    }

    private func apply(
        _ state: CellState,
        atRow row: Int,
        column: Int,
        playSound: Bool
    ) {
        guard !isAutoMarking else { return }
        do {
            let previousPuzzle = engine.state.puzzle
            let previousCellState = previousPuzzle.state(atRow: row, column: column)
            let position = CellPosition(row: row, column: column)
            if state == .excluded,
               previousCellState != .excluded,
               tutorialCatPositions.contains(position) {
                feedbackMessage = "This cell could still hold a cat. Try another empty cell."
                soundPlayer.play(.catPlacementFailed)
                return
            }
            let currentStep = step
            try engine.setState(state, atRow: row, column: column)
            feedbackMessage = nil
            let puzzleChanged = engine.state.puzzle != previousPuzzle
            synchronizeFromEngine(notifyChange: puzzleChanged)
            if puzzleChanged, playSound {
                playCommittedTransitionSound(
                    from: previousCellState,
                    to: engine.state.puzzle.state(atRow: row, column: column)
                )
            }
            if isSolved || isFailed {
                input.cancelAll()
            } else if state == .excluded,
                      previousCellState != .excluded,
                      let currentStep,
                      currentStep.coaching == .discovery,
                      case let .exclude(positions) = currentStep.task,
                      positions.contains(position) {
                beginAutoMarking(positions)
            }
        } catch GameEngineError.illegalCatPlacement {
            // Challenge mode: a wrong cat is refused rather than landed and
            // knocking every later step off the board it was written for.
            feedbackMessage = "That cat conflicts with another cat."
            synchronizeFromEngine(notifyChange: true)
            soundPlayer.play(isFailed ? .gameOver : .catPlacementFailed)
            if isFailed {
                input.cancelAll()
            }
        } catch GameEngineError.incorrectCatPlacement {
            feedbackMessage = "That cat is not in the solution."
            synchronizeFromEngine(notifyChange: true)
            soundPlayer.play(isFailed ? .gameOver : .catPlacementFailed)
            if isFailed {
                input.cancelAll()
            }
        } catch GameEngineError.gameAlreadyFailed {
            feedbackMessage = "Restart to try again."
        } catch GameEngineError.invalidCell {
            feedbackMessage = "That cell is outside the board."
        } catch {
            feedbackMessage = "Unable to update this cell."
        }
    }

    private func playCommittedTransitionSound(
        from previous: CellState?,
        to next: CellState?
    ) {
        guard let previous,
              let next,
              let sound = PuzzleSound.forCommittedTransition(
                from: previous,
                to: next
              ) else {
            return
        }
        soundPlayer.play(sound)
        markerFeedbackSequence &+= 1
    }

    /// Keep the player's first mark visible, then sweep the remaining cells
    /// one by one in the script's row → column → neighbour order. Each engine
    /// update is published separately so the board animates each new ×.
    private func beginAutoMarking(_ positions: [CellPosition]) {
        let remaining = positions.filter {
            puzzle.state(atRow: $0.row, column: $0.column) == .empty
        }
        guard !remaining.isEmpty else { return }
        input.cancelAll()
        isAutoMarking = true
        autoMarkGeneration &+= 1
        let generation = autoMarkGeneration
        autoMarkTask = Task { [weak self] in
            guard let self else { return }
            for position in remaining {
                do {
                    try await Task.sleep(for: self.autoMarkInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled, self.autoMarkGeneration == generation else {
                    return
                }
                do {
                    try self.engine.setState(
                        .excluded,
                        atRow: position.row,
                        column: position.column
                    )
                    self.autoMarkedPosition = position
                    self.synchronizeFromEngine(notifyChange: true)
                } catch {
                    self.cancelAutoMarking()
                    self.feedbackMessage = "Unable to finish marking these cells."
                    return
                }
            }
            guard self.autoMarkGeneration == generation else { return }
            self.isAutoMarking = false
            self.autoMarkedPosition = nil
            self.autoMarkTask = nil
        }
    }

    private func cancelAutoMarking() {
        autoMarkGeneration &+= 1
        autoMarkTask?.cancel()
        autoMarkTask = nil
        isAutoMarking = false
        autoMarkedPosition = nil
    }

    // MARK: - Coaching

    /// Re-reads the board to find the step the tutorial is on. A requested
    /// clue stays visible only while it points at an unfinished move.
    private func refreshCoaching() {
        let index = coach.currentStepIndex(for: puzzle)
        // A solved board has nothing left to teach, even if the player got
        // there without marking every × the script asked for.
        let current = isSolved ? nil : coach.step(at: index)
        if current != step {
            nudgedPositions = []
        } else if let current {
            nudgedPositions.formIntersection(current.remainingPositions(in: puzzle))
        }
        step = current
        stepNumber = min(index + 1, coach.stepCount)
    }

    /// True when a guided step has masked this cell off. The check lives
    /// here rather than only in the board so that VoiceOver actions, which
    /// do not go through the board's gestures, are held to the same rule.
    private func isMasked(_ position: CellPosition) -> Bool {
        guard let interactive = interactivePositions else { return false }
        return !interactive.contains(position)
    }

    private func synchronizeFromEngine(notifyChange: Bool) {
        puzzle = engine.state.puzzle
        isSolved = engine.state.isSolved
        isFailed = engine.state.isFailed
        refreshCoaching()
        if notifyChange {
            onGameStateChanged(engine.state)
        }
    }
}
