public struct CellPosition: Hashable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

public struct LevelFixture: Equatable, Sendable {
    public let level: LevelDefinition
    public let solution: [CellPosition]

    public init(level: LevelDefinition, solution: [CellPosition]) {
        self.level = level
        self.solution = solution
    }
}
