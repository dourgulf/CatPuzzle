public enum GameplayMode: String, Codable, CaseIterable, Sendable {
    case exploration
    case challenge

    public var allowsUndo: Bool {
        self == .exploration
    }
}

public struct GameState: Equatable, Sendable {
    public let level: LevelDefinition
    public internal(set) var mode: GameplayMode
    public internal(set) var puzzle: Puzzle
    public internal(set) var mistakeCount: Int

    public var isSolved: Bool {
        PuzzleValidator.isSolved(puzzle, catCount: level.catCount)
    }

    public var isFailed: Bool {
        mistakeCount >= level.maxMistakes
    }

    public var remainingMistakes: Int {
        max(0, level.maxMistakes - mistakeCount)
    }

    public init(
        level: LevelDefinition,
        mode: GameplayMode = .exploration,
        puzzle: Puzzle,
        mistakeCount: Int = 0
    ) {
        self.level = level
        self.mode = mode
        self.puzzle = puzzle
        self.mistakeCount = mistakeCount
    }
}
