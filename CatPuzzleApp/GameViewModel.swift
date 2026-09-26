import Combine
import CatPuzzleCore

@MainActor
final class GameViewModel: ObservableObject {
    let level: LevelDefinition

    @Published private(set) var mode: GameplayMode
    var allowsUndo: Bool { mode.allowsUndo }

    @Published private(set) var puzzle: Puzzle
    @Published private(set) var canUndo: Bool
    @Published private(set) var isSolved: Bool
    @Published private(set) var isFailed: Bool
    @Published private(set) var mistakeCount: Int
    @Published private(set) var remainingMistakes: Int
    @Published private(set) var feedbackMessage: String?
    @Published private(set) var previewStates: [CellPosition: CellState] = [:]
    @Published private(set) var markerFeedbackSequence = 0
    @Published private(set) var hint: LogicalHint?
    /// Why the board can no longer be finished, when the player asked for a
    /// hint on a board they had already broken. Kept structured rather than
    /// pre-rendered: naming a Region needs the board's icon setting, which
    /// lives with the view.
    @Published private(set) var hintDiagnosis: LogicalHintDiagnosis?

    var mistakeSummary: String {
        "Mistakes: \(mistakeCount) / \(level.maxMistakes)"
    }

    var regionIDs: [Int] {
        Array(Set(puzzle.cells.map(\.regionID))).sorted()
    }

    var occupiedRegionIDs: Set<Int> {
        Set(zip(puzzle.cells, puzzle.states).compactMap { cell, state in
            state == .cat ? cell.regionID : nil
        })
    }

    private var engine: GameEngine
    private let input: CellInputCoordinator
    private let soundPlayer: any PuzzleSoundPlaying
    private let onGameStateChanged: (GameState) -> Void

    convenience init(
        level: LevelDefinition,
        doubleTapInterval: Duration = .milliseconds(300),
        soundPlayer: any PuzzleSoundPlaying = PuzzleSoundPlayer.shared,
        onGameStateChanged: @escaping (GameState) -> Void = { _ in }
    ) throws {
        try self.init(
            engine: GameEngine(level: level),
            doubleTapInterval: doubleTapInterval,
            soundPlayer: soundPlayer,
            onGameStateChanged: onGameStateChanged
        )
    }

    init(
        engine: GameEngine,
        doubleTapInterval: Duration = .milliseconds(300),
        soundPlayer: any PuzzleSoundPlaying = PuzzleSoundPlayer.shared,
        onGameStateChanged: @escaping (GameState) -> Void = { _ in }
    ) {
        self.engine = engine
        self.level = engine.state.level
        self.soundPlayer = soundPlayer
        self.onGameStateChanged = onGameStateChanged
        self.input = CellInputCoordinator(
            doubleTapInterval: doubleTapInterval,
            soundPlayer: soundPlayer
        )
        mode = engine.state.mode
        puzzle = engine.state.puzzle
        canUndo = engine.canUndo
        isSolved = engine.state.isSolved
        isFailed = engine.state.isFailed
        mistakeCount = engine.state.mistakeCount
        remainingMistakes = engine.state.remainingMistakes
        feedbackMessage = nil
        input.configure(
            onPreviewStatesChanged: { [weak self] in
                self?.previewStates = self?.input.previewStates ?? [:]
            },
            onMarkerFeedback: { [weak self] in
                self?.markerFeedbackSequence &+= 1
            }
        )
    }

    private func makeInputEnvironment() -> CellInputCoordinator.Environment {
        CellInputCoordinator.Environment(
            currentState: { [weak self] position in
                self?.puzzle.state(atRow: position.row, column: position.column)
            },
            isLocked: { [weak self] position in
                self?.isLocked(atRow: position.row, column: position.column) ?? true
            },
            isInteractable: { _ in true },
            commit: { [weak self] state, position, playSound in
                self?.apply(state, atRow: position.row, column: position.column, playSound: playSound)
            }
        )
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

    func undo() {
        input.cancelAll()
        hint = nil
        hintDiagnosis = nil
        guard engine.undo() else { return }
        feedbackMessage = nil
        synchronizeFromEngine(notifyChange: true)
    }

    func restart() {
        input.cancelAll()
        hint = nil
        hintDiagnosis = nil
        engine.restart()
        feedbackMessage = nil
        synchronizeFromEngine(notifyChange: true)
    }

    func setMode(_ mode: GameplayMode) {
        input.cancelAll()
        hint = nil
        hintDiagnosis = nil
        engine.setMode(mode)
        feedbackMessage = nil
        synchronizeFromEngine(notifyChange: true)
    }

    func requestHint() {
        input.cancelAll()
        guard !isSolved, !isFailed else { return }
        switch LogicalHintEngine.nextHint(level: level, puzzle: puzzle) {
        case let .hint(next):
            hint = next
            hintDiagnosis = nil
            feedbackMessage = nil
        case let .contradiction(diagnosis):
            // The board can no longer be finished, so there is nothing to
            // preview — tell the player what they broke instead.
            hint = nil
            hintDiagnosis = diagnosis
            feedbackMessage = nil
        case .unavailable:
            hint = nil
            hintDiagnosis = nil
            feedbackMessage = "No next step can be deduced from this board."
        }
    }

    func dismissHint() {
        hint = nil
        hintDiagnosis = nil
    }

    func applyHint() {
        guard let hint else { return }
        input.cancelAll()
        let previousPuzzle = engine.state.puzzle
        do {
            try engine.applyHint(hint)
            self.hint = nil
            self.hintDiagnosis = nil
            feedbackMessage = nil
            synchronizeFromEngine(
                notifyChange: engine.state.puzzle != previousPuzzle
            )
            if isSolved || isFailed {
                input.cancelAll()
            }
        } catch {
            self.hint = nil
            self.hintDiagnosis = nil
            feedbackMessage = "This hint can no longer be applied."
            synchronizeFromEngine(notifyChange: false)
        }
    }

    private func apply(
        _ state: CellState,
        atRow row: Int,
        column: Int,
        playSound: Bool = true
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
        playMarkerFeedback(sound)
    }

    private func playMarkerFeedback(_ sound: PuzzleSound) {
        soundPlayer.play(sound)
        markerFeedbackSequence &+= 1
    }

    private func synchronizeFromEngine(notifyChange: Bool) {
        mode = engine.state.mode
        puzzle = engine.state.puzzle
        canUndo = engine.canUndo
        isSolved = engine.state.isSolved
        isFailed = engine.state.isFailed
        mistakeCount = engine.state.mistakeCount
        remainingMistakes = engine.state.remainingMistakes
        if notifyChange {
            onGameStateChanged(engine.state)
        }
    }
}
