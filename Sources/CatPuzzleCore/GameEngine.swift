public enum GameEngineError: Error, Equatable, Sendable {
    case invalidCell
    case illegalCatPlacement
    case puzzleDoesNotMatchLevel
    case invalidRestoredPuzzle
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

    public init(level: LevelDefinition, puzzle: Puzzle) throws {
        let freshPuzzle = try level.makePuzzle()
        guard puzzle.size == freshPuzzle.size,
              puzzle.cells == freshPuzzle.cells else {
            throw GameEngineError.puzzleDoesNotMatchLevel
        }
        guard !PuzzleValidator.hasRowConflict(in: puzzle),
              !PuzzleValidator.hasColumnConflict(in: puzzle),
              !PuzzleValidator.hasRegionConflict(in: puzzle),
              !PuzzleValidator.hasAdjacentCats(in: puzzle) else {
            throw GameEngineError.invalidRestoredPuzzle
        }

        state = GameState(level: level, puzzle: puzzle)
        initialPuzzle = freshPuzzle
    }

    public mutating func setState(
        _ newState: CellState,
        atRow row: Int,
        column: Int
    ) throws {
        guard let currentState = state.puzzle.state(
            atRow: row,
            column: column
        ) else {
            throw GameEngineError.invalidCell
        }
        guard currentState != newState else { return }

        if newState == .cat,
           !PuzzleValidator.canPlaceCat(
               atRow: row,
               column: column,
               in: state.puzzle
           ) {
            throw GameEngineError.illegalCatPlacement
        }

        var updatedPuzzle = state.puzzle
        try updatedPuzzle.setState(newState, atRow: row, column: column)
        history.append(state.puzzle)
        state.puzzle = updatedPuzzle
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

        try setState(nextState, atRow: row, column: column)
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
