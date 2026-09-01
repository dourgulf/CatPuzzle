public enum GameEngineError: Error, Equatable, Sendable {
    case invalidCell
    case illegalCatPlacement
    case incorrectCatPlacement
    case gameAlreadyFailed
    case puzzleDoesNotMatchLevel
    case invalidRestoredPuzzle
    case invalidMistakeCount
    case invalidSolution
    case cellIsLocked
    case invalidGivenCells
}

public struct GameEngine: Sendable {
    public private(set) var state: GameState
    private let initialPuzzle: Puzzle
    private let solution: Set<CellPosition>?
    private var history: [Puzzle] = []

    public var canUndo: Bool {
        state.mode.allowsUndo && !state.isFailed && !history.isEmpty
    }

    public init(level: LevelDefinition) throws {
        try LevelValidator.validate(level)
        let puzzle = try level.makePuzzle()
        state = GameState(level: level, puzzle: puzzle)
        initialPuzzle = puzzle
        solution = nil
    }

    public init(
        fixture: LevelFixture,
        mode: GameplayMode
    ) throws {
        try self.init(
            fixture: fixture,
            puzzle: fixture.level.makePuzzle(),
            mistakeCount: 0,
            mode: mode
        )
    }

    public init(
        level: LevelDefinition,
        puzzle: Puzzle,
        mistakeCount: Int = 0
    ) throws {
        try LevelValidator.validate(level)
        let freshPuzzle = try level.makePuzzle()
        guard puzzle.size == freshPuzzle.size,
              puzzle.cells == freshPuzzle.cells else {
            throw GameEngineError.puzzleDoesNotMatchLevel
        }
        guard !PuzzleValidator.hasRowConflict(in: puzzle),
              !PuzzleValidator.hasColumnConflict(in: puzzle),
              !PuzzleValidator.hasRegionConflict(in: puzzle),
              !PuzzleValidator.hasAdjacentCats(in: puzzle),
              Self.puzzleMatchesGivens(puzzle, level: level) else {
            throw GameEngineError.invalidRestoredPuzzle
        }
        guard mistakeCount >= 0 else {
            throw GameEngineError.invalidMistakeCount
        }

        state = GameState(
            level: level,
            puzzle: puzzle,
            mistakeCount: mistakeCount
        )
        initialPuzzle = freshPuzzle
        solution = nil
    }

    public init(
        fixture: LevelFixture,
        puzzle: Puzzle,
        mistakeCount: Int = 0,
        mode: GameplayMode
    ) throws {
        let level = fixture.level
        try LevelValidator.validate(level)
        let freshPuzzle = try level.makePuzzle()
        guard puzzle.size == freshPuzzle.size,
              puzzle.cells == freshPuzzle.cells else {
            throw GameEngineError.puzzleDoesNotMatchLevel
        }
        guard mistakeCount >= 0 else {
            throw GameEngineError.invalidMistakeCount
        }

        let solution = Set(fixture.solution)
        guard solution.count == level.catCount,
              solution.allSatisfy({ position in
                  freshPuzzle.state(
                      atRow: position.row,
                      column: position.column
                  ) != nil
              }) else {
            throw GameEngineError.invalidSolution
        }

        var solutionPuzzle = freshPuzzle
        for position in solution {
            try solutionPuzzle.setState(
                .cat,
                atRow: position.row,
                column: position.column
            )
        }
        guard PuzzleValidator.isSolved(
            solutionPuzzle,
            catCount: level.catCount
        ) else {
            throw GameEngineError.invalidSolution
        }
        // A given `.cat` that isn't part of `solution` already fails the
        // isSolved check above (either as a cat-count mismatch or a row/
        // column/region conflict once the real solution is overlaid), so
        // only a given `.excluded` marking the solution's own cell needs an
        // explicit check here.
        if let givenStates = level.givenStates {
            for position in level.givenPositions
            where givenStates[position.row][position.column] == .excluded {
                guard !solution.contains(position) else {
                    throw GameEngineError.invalidGivenCells
                }
            }
        }
        guard !PuzzleValidator.hasRowConflict(in: puzzle),
              !PuzzleValidator.hasColumnConflict(in: puzzle),
              !PuzzleValidator.hasRegionConflict(in: puzzle),
              !PuzzleValidator.hasAdjacentCats(in: puzzle),
              Self.puzzleMatchesGivens(puzzle, level: level) else {
            throw GameEngineError.invalidRestoredPuzzle
        }
        if mode == .challenge {
            let restoredCats = puzzle.cells.compactMap { cell in
                puzzle.state(atRow: cell.row, column: cell.column) == .cat
                    ? CellPosition(row: cell.row, column: cell.column)
                    : nil
            }
            guard restoredCats.allSatisfy(solution.contains) else {
                throw GameEngineError.invalidRestoredPuzzle
            }
        }

        state = GameState(
            level: level,
            mode: mode,
            puzzle: puzzle,
            mistakeCount: mistakeCount
        )
        initialPuzzle = freshPuzzle
        self.solution = solution
    }

    public mutating func setState(
        _ newState: CellState,
        atRow row: Int,
        column: Int
    ) throws {
        guard !state.isFailed else {
            throw GameEngineError.gameAlreadyFailed
        }
        guard let currentState = state.puzzle.state(
            atRow: row,
            column: column
        ) else {
            throw GameEngineError.invalidCell
        }
        guard !state.level.givenPositions.contains(
            CellPosition(row: row, column: column)
        ) else {
            throw GameEngineError.cellIsLocked
        }
        guard currentState != newState else { return }

        if newState == .cat,
           state.mode == .challenge,
           solution?.contains(CellPosition(row: row, column: column)) != true {
            state.mistakeCount += 1
            throw GameEngineError.incorrectCatPlacement
        }

        if newState == .cat,
           !PuzzleValidator.canPlaceCat(
               atRow: row,
               column: column,
               in: state.puzzle
           ) {
            state.mistakeCount += 1
            throw GameEngineError.illegalCatPlacement
        }

        var updatedPuzzle = state.puzzle
        try updatedPuzzle.setState(newState, atRow: row, column: column)
        if state.mode.allowsUndo {
            history.append(state.puzzle)
        }
        state.puzzle = updatedPuzzle
    }

    /// Applies one logical hint atomically. In exploration mode the entire
    /// hint is one undo step, even when it excludes several cells.
    public mutating func applyHint(_ hint: LogicalHint) throws {
        guard !hint.actions.isEmpty else { return }

        var updatedEngine = self
        for action in hint.actions {
            switch action {
            case let .placeCat(position):
                try updatedEngine.setState(
                    .cat,
                    atRow: position.row,
                    column: position.column
                )
            case let .exclude(position):
                try updatedEngine.setState(
                    .excluded,
                    atRow: position.row,
                    column: position.column
                )
            }
        }

        if state.mode.allowsUndo,
           updatedEngine.state.puzzle != state.puzzle {
            updatedEngine.history = history + [state.puzzle]
        }
        self = updatedEngine
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
        guard state.mode.allowsUndo, !state.isFailed else { return false }
        guard let previousPuzzle = history.popLast() else { return false }
        state.puzzle = previousPuzzle
        return true
    }

    public mutating func setMode(_ mode: GameplayMode) {
        guard state.mode != mode else { return }
        state.mode = mode
        history.removeAll(keepingCapacity: true)
    }

    public mutating func restart() {
        state.puzzle = initialPuzzle
        state.mistakeCount = 0
        history.removeAll(keepingCapacity: true)
    }

    private static func puzzleMatchesGivens(
        _ puzzle: Puzzle,
        level: LevelDefinition
    ) -> Bool {
        guard let givenStates = level.givenStates else { return true }
        return level.givenPositions.allSatisfy { position in
            puzzle.state(atRow: position.row, column: position.column)
                == givenStates[position.row][position.column]
        }
    }
}
