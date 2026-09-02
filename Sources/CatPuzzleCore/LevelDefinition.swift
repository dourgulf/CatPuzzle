public struct LevelDefinition: Equatable, Sendable {
    public let id: String
    public let size: Int
    public let catCount: Int
    public let maxMistakes: Int
    public let regionIDs: [[Int]]
    public let givenStates: [[CellState]]?

    public init(
        id: String,
        size: Int,
        catCount: Int,
        maxMistakes: Int,
        regionIDs: [[Int]],
        givenStates: [[CellState]]? = nil
    ) {
        self.id = id
        self.size = size
        self.catCount = catCount
        self.maxMistakes = maxMistakes
        self.regionIDs = regionIDs
        self.givenStates = givenStates
    }

    /// Positions locked at level start because the level ships with a
    /// pre-filled clue there (see `givenStates`). Empty when the level has
    /// no givens.
    public var givenPositions: Set<CellPosition> {
        guard let givenStates else { return [] }
        var positions: Set<CellPosition> = []
        for (row, statesInRow) in givenStates.enumerated() {
            for (column, cellState) in statesInRow.enumerated() where cellState != .empty {
                positions.insert(CellPosition(row: row, column: column))
            }
        }
        return positions
    }

    public func makePuzzle() throws -> Puzzle {
        try Puzzle(size: size, regionIDs: regionIDs, states: givenStates)
    }
}
