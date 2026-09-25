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
    /// 1-based position of `step` in the script, for "Step 3 of 12".
    @Published private(set) var stepNumber = 0
    var stepCount: Int { coach.stepCount }
    /// Cells pulsing because the player has been sitting on a `.discovery`
    /// step without acting. Empty at every other moment.
    @Published private(set) var nudgedPositions: Set<CellPosition> = []

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
        return Set(step.task.positions)
    }

    private var engine: GameEngine
    private let coach: TutorialCoach
    private let input: CellInputCoordinator
    private let soundPlayer: any PuzzleSoundPlaying
    private let onGameStateChanged: (GameState) -> Void
    private let nudgeDelay: Duration
    private var nudgeTask: Task<Void, Never>?
    /// The step a nudge has already fired for. Once the player has been
    /// shown where to look, every later mark in the same step re-shows it
    /// right away instead of making them wait out the delay again.
    private var nudgedStepNumber: Int?

    /// `script` is required and assumed non-empty — callers only build a
    /// `TutorialViewModel` when `TutorialScript.isEmpty == false`, falling
    /// back to a plain `GameViewModel` otherwise (an unscripted board is
    /// simply played, not coached wrongly).
    init(
        engine: GameEngine,
        script: TutorialScript,
        nudgeDelay: Duration = .seconds(3),
        doubleTapInterval: Duration = .milliseconds(300),
        soundPlayer: any PuzzleSoundPlaying = PuzzleSoundPlayer.shared,
        onGameStateChanged: @escaping (GameState) -> Void = { _ in }
    ) {
        self.engine = engine
        self.level = engine.state.level
        self.coach = TutorialCoach(script: script)
        self.nudgeDelay = nudgeDelay
        self.soundPlayer = soundPlayer
        self.onGameStateChanged = onGameStateChanged
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
        input.cancelAll()
        engine.restart()
        feedbackMessage = nil
        synchronizeFromEngine(notifyChange: true)
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
                return !self.isMasked(position)
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
        do {
            let previousPuzzle = engine.state.puzzle
            let previousCellState = previousPuzzle.state(atRow: row, column: column)
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

    // MARK: - Coaching

    /// Re-reads the board to find the step the tutorial is on. Every board
    /// change also restarts the nudge delay, so a player who is working is
    /// never interrupted — only one who has stopped.
    private func refreshCoaching() {
        let index = coach.currentStepIndex(for: puzzle)
        // A solved board has nothing left to teach, even if the player got
        // there without marking every × the script asked for.
        let current = isSolved ? nil : coach.step(at: index)
        if current != step {
            nudgedStepNumber = nil
        }
        step = current
        stepNumber = min(index + 1, coach.stepCount)
        scheduleNudge()
    }

    private func scheduleNudge() {
        nudgeTask?.cancel()
        nudgeTask = nil
        nudgedPositions = []

        guard let step, step.coaching == .discovery, !isSolved else {
            return
        }
        guard nudgedStepNumber != stepNumber else {
            showNudge(for: step)
            return
        }

        let delay = nudgeDelay
        nudgeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.showNudge(for: step)
        }
    }

    private func showNudge(for step: TutorialStep) {
        guard self.step == step else { return }
        nudgedStepNumber = stepNumber
        nudgedPositions = Set(step.remainingPositions(in: puzzle))
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
