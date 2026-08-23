public struct GameState: Equatable, Sendable {
    public let level: LevelDefinition
    public internal(set) var puzzle: Puzzle

    public var isSolved: Bool {
        PuzzleValidator.isSolved(puzzle)
    }

    public init(level: LevelDefinition, puzzle: Puzzle) {
        self.level = level
        self.puzzle = puzzle
    }
}
