import Combine
import CatPuzzleCore

enum CellTapResolution: Equatable {
    case pendingSingle(token: Int)
    case doubleTap
}

struct CellTapInterpreter {
    private var pendingTokens: [CellPosition: Int] = [:]
    private var nextToken = 0

    mutating func registerTap(at position: CellPosition) -> CellTapResolution {
        if pendingTokens.removeValue(forKey: position) != nil {
            return .doubleTap
        }

        nextToken &+= 1
        pendingTokens[position] = nextToken
        return .pendingSingle(token: nextToken)
    }

    mutating func commitSingle(
        at position: CellPosition,
        token: Int
    ) -> Bool {
        guard pendingTokens[position] == token else { return false }
        pendingTokens.removeValue(forKey: position)
        return true
    }

    mutating func cancelAll() {
        pendingTokens.removeAll()
    }
}

@MainActor
final class GameViewModel: ObservableObject {
    let level: LevelDefinition

    @Published private(set) var puzzle: Puzzle
    @Published private(set) var canUndo: Bool
    @Published private(set) var isSolved: Bool
    @Published private(set) var isFailed: Bool
    @Published private(set) var mistakeCount: Int
    @Published private(set) var remainingMistakes: Int
    @Published private(set) var feedbackMessage: String?
    @Published private(set) var previewStates: [CellPosition: CellState] = [:]

    var mistakeSummary: String {
        "Mistakes: \(mistakeCount) / \(level.maxMistakes)"
    }

    private var engine: GameEngine
    private var tapInterpreter = CellTapInterpreter()
    private var pendingTapTasks: [CellPosition: Task<Void, Never>] = [:]
    private let doubleTapInterval: Duration
    private let soundPlayer: any PuzzleSoundPlaying
    private let onGameStateChanged: (GameState) -> Void

    convenience init(
        level: LevelDefinition = BuiltInLevels.meadow,
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
        self.doubleTapInterval = doubleTapInterval
        self.soundPlayer = soundPlayer
        self.onGameStateChanged = onGameStateChanged
        puzzle = engine.state.puzzle
        canUndo = engine.canUndo
        isSolved = engine.state.isSolved
        isFailed = engine.state.isFailed
        mistakeCount = engine.state.mistakeCount
        remainingMistakes = engine.state.remainingMistakes
        feedbackMessage = nil
    }

    func displayState(atRow row: Int, column: Int) -> CellState? {
        let position = CellPosition(row: row, column: column)
        return previewStates[position]
            ?? puzzle.state(atRow: row, column: column)
    }

    func handleCellTap(atRow row: Int, column: Int) {
        guard let currentState = puzzle.state(atRow: row, column: column) else {
            feedbackMessage = "That cell is outside the board."
            return
        }

        let position = CellPosition(row: row, column: column)
        switch tapInterpreter.registerTap(at: position) {
        case let .pendingSingle(token):
            previewStates[position] = excludedToggleResult(for: currentState)
            scheduleSingleTapCommit(at: position, token: token)
        case .doubleTap:
            pendingTapTasks.removeValue(forKey: position)?.cancel()
            previewStates.removeValue(forKey: position)
            applyCatToggle(atRow: row, column: column)
        }
    }

    func toggleExcluded(atRow row: Int, column: Int) {
        cancelPendingTaps()
        applyExcludedToggle(atRow: row, column: column)
    }

    func toggleCat(atRow row: Int, column: Int) {
        cancelPendingTaps()
        applyCatToggle(atRow: row, column: column)
    }

    func undo() {
        cancelPendingTaps()
        guard engine.undo() else { return }
        feedbackMessage = nil
        synchronizeFromEngine(notifyChange: true)
    }

    func restart() {
        cancelPendingTaps()
        engine.restart()
        feedbackMessage = nil
        synchronizeFromEngine(notifyChange: true)
    }

    private func applyExcludedToggle(atRow row: Int, column: Int) {
        guard let currentState = puzzle.state(atRow: row, column: column) else {
            feedbackMessage = "That cell is outside the board."
            return
        }

        switch currentState {
        case .empty:
            apply(.excluded, atRow: row, column: column)
        case .excluded:
            apply(.empty, atRow: row, column: column)
        case .cat:
            feedbackMessage = nil
        }
    }

    private func applyCatToggle(atRow row: Int, column: Int) {
        guard let currentState = puzzle.state(atRow: row, column: column) else {
            feedbackMessage = "That cell is outside the board."
            return
        }

        let nextState: CellState = currentState == .cat ? .empty : .cat
        apply(nextState, atRow: row, column: column)
    }

    private func excludedToggleResult(for state: CellState) -> CellState {
        switch state {
        case .empty:
            .excluded
        case .excluded:
            .empty
        case .cat:
            .cat
        }
    }

    private func scheduleSingleTapCommit(
        at position: CellPosition,
        token: Int
    ) {
        let interval = doubleTapInterval
        pendingTapTasks[position] = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.commitSingleTap(at: position, token: token)
        }
    }

    private func commitSingleTap(at position: CellPosition, token: Int) {
        guard tapInterpreter.commitSingle(at: position, token: token) else {
            return
        }

        pendingTapTasks.removeValue(forKey: position)
        previewStates.removeValue(forKey: position)
        applyExcludedToggle(atRow: position.row, column: position.column)
    }

    private func cancelPendingTaps() {
        for task in pendingTapTasks.values {
            task.cancel()
        }
        pendingTapTasks.removeAll()
        previewStates.removeAll()
        tapInterpreter.cancelAll()
    }

    private func apply(_ state: CellState, atRow row: Int, column: Int) {
        do {
            let previousPuzzle = engine.state.puzzle
            let previousCellState = previousPuzzle.state(atRow: row, column: column)
            try engine.setState(state, atRow: row, column: column)
            feedbackMessage = nil
            let puzzleChanged = engine.state.puzzle != previousPuzzle
            synchronizeFromEngine(notifyChange: puzzleChanged)
            if puzzleChanged {
                playCommittedTransitionSound(
                    from: previousCellState,
                    to: engine.state.puzzle.state(atRow: row, column: column)
                )
            }
            if isSolved || isFailed {
                cancelPendingTaps()
            }
        } catch GameEngineError.illegalCatPlacement {
            feedbackMessage = "That cat conflicts with another cat."
            synchronizeFromEngine(notifyChange: true)
            if isFailed {
                cancelPendingTaps()
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
    }

    private func synchronizeFromEngine(notifyChange: Bool) {
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
