public struct LevelDefinition: Equatable, Sendable {
    public let id: String
    public let size: Int
    public let regionIDs: [[Int]]

    public init(id: String, size: Int, regionIDs: [[Int]]) {
        self.id = id
        self.size = size
        self.regionIDs = regionIDs
    }

    public func makePuzzle() throws -> Puzzle {
        try Puzzle(size: size, regionIDs: regionIDs)
    }
}
