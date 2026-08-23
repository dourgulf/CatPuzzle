public enum GameEngineError: Error, Equatable, Sendable {
    case invalidCell
    case illegalCatPlacement
}

public struct GameEngine: Sendable {
    public private(set) var state: GameState
    private let initialPuzzle: Puzzle
    private var history: [Puzzle] = []

    public var canUndo: Bool {
        !history.isEmpty
    }

    public init(level: LevelDefinition) throws {
        let puzzle = try level.makePuzzle()
        state = GameState(level: level, puzzle: puzzle)
        initialPuzzle = puzzle
    }

    @discardableResult
    public mutating func toggleCell(
        atRow row: Int,
        column: Int
    ) throws -> CellState {
        guard let currentState = state.puzzle.state(
            atRow: row,
            column: column
        ) else {
            throw GameEngineError.invalidCell
        }

        let nextState: CellState
        switch currentState {
        case .empty:
            nextState = .excluded
        case .excluded:
            nextState = .cat
        case .cat:
            nextState = .empty
        }

        if nextState == .cat,
           !PuzzleValidator.canPlaceCat(
               atRow: row,
               column: column,
               in: state.puzzle
           ) {
            throw GameEngineError.illegalCatPlacement
        }

        var updatedPuzzle = state.puzzle
        try updatedPuzzle.setState(nextState, atRow: row, column: column)
        history.append(state.puzzle)
        state.puzzle = updatedPuzzle
        return nextState
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previousPuzzle = history.popLast() else { return false }
        state.puzzle = previousPuzzle
        return true
    }

    public mutating func restart() {
        state.puzzle = initialPuzzle
        history.removeAll(keepingCapacity: true)
    }
}
