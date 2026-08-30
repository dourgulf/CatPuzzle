public struct LevelDefinition: Equatable, Sendable {
    public let id: String
    public let size: Int
    public let catCount: Int
    public let maxMistakes: Int
    public let regionIDs: [[Int]]

    public init(
        id: String,
        size: Int,
        catCount: Int,
        maxMistakes: Int,
        regionIDs: [[Int]]
    ) {
        self.id = id
        self.size = size
        self.catCount = catCount
        self.maxMistakes = maxMistakes
        self.regionIDs = regionIDs
    }

    public func makePuzzle() throws -> Puzzle {
        try Puzzle(size: size, regionIDs: regionIDs)
    }
}
