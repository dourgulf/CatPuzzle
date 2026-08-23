public struct LevelDefinition: Equatable, Sendable {
    public let id: String
    public let size: Int
    public let catCount: Int
    public let maxMistakes: Int
    public let colorIDs: [[Int]]

    public init(
        id: String,
        size: Int,
        catCount: Int,
        maxMistakes: Int,
        colorIDs: [[Int]]
    ) {
        self.id = id
        self.size = size
        self.catCount = catCount
        self.maxMistakes = maxMistakes
        self.colorIDs = colorIDs
    }

    public func makePuzzle() throws -> Puzzle {
        try Puzzle(size: size, colorIDs: colorIDs)
    }
}
