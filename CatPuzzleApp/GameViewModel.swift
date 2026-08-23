import Combine
import CatPuzzleCore

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

    var mistakeSummary: String {
        "Mistakes: \(mistakeCount) / \(level.maxMistakes)"
    }

    private var engine: GameEngine
    private let onGameStateChanged: (GameState) -> Void

    convenience init(
        level: LevelDefinition = BuiltInLevels.meadow,
        onGameStateChanged: @escaping (GameState) -> Void = { _ in }
    ) throws {
        try self.init(
            engine: GameEngine(level: level),
            onGameStateChanged: onGameStateChanged
        )
    }

    init(
        engine: GameEngine,
        onGameStateChanged: @escaping (GameState) -> Void = { _ in }
    ) {
        self.engine = engine
        self.level = engine.state.level
        self.onGameStateChanged = onGameStateChanged
        puzzle = engine.state.puzzle
        canUndo = engine.canUndo
        isSolved = engine.state.isSolved
        isFailed = engine.state.isFailed
        mistakeCount = engine.state.mistakeCount
        remainingMistakes = engine.state.remainingMistakes
        feedbackMessage = nil
    }

    func toggleExcluded(atRow row: Int, column: Int) {
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

    func toggleCat(atRow row: Int, column: Int) {
        guard let currentState = puzzle.state(atRow: row, column: column) else {
            feedbackMessage = "That cell is outside the board."
            return
        }

        let nextState: CellState = currentState == .cat ? .empty : .cat
        apply(nextState, atRow: row, column: column)
    }

    func undo() {
        guard engine.undo() else { return }
        feedbackMessage = nil
        synchronizeFromEngine(notifyChange: true)
    }

    func restart() {
        engine.restart()
        feedbackMessage = nil
        synchronizeFromEngine(notifyChange: true)
    }

    private func apply(_ state: CellState, atRow row: Int, column: Int) {
        do {
            let previousPuzzle = engine.state.puzzle
            try engine.setState(state, atRow: row, column: column)
            feedbackMessage = nil
            synchronizeFromEngine(
                notifyChange: engine.state.puzzle != previousPuzzle
            )
        } catch GameEngineError.illegalCatPlacement {
            feedbackMessage = "That cat conflicts with another cat."
            synchronizeFromEngine(notifyChange: true)
        } catch GameEngineError.gameAlreadyFailed {
            feedbackMessage = "Restart to try again."
        } catch GameEngineError.invalidCell {
            feedbackMessage = "That cell is outside the board."
        } catch {
            feedbackMessage = "Unable to update this cell."
        }
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
