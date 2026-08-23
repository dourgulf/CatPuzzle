public enum BuiltInLevels {
    public static let meadowFixture = LevelFixture(
        level: LevelDefinition(
            id: "meadow",
            size: 6,
            catCount: 6,
            maxMistakes: 5,
            colorIDs: [
                [0, 0, 0, 0, 1, 1],
                [0, 0, 4, 1, 1, 1],
                [0, 0, 4, 1, 2, 2],
                [3, 3, 4, 4, 4, 2],
                [4, 4, 4, 5, 5, 5],
                [4, 4, 5, 5, 5, 5],
            ]
        ),
        solution: [
            CellPosition(row: 0, column: 1),
            CellPosition(row: 1, column: 3),
            CellPosition(row: 2, column: 5),
            CellPosition(row: 3, column: 0),
            CellPosition(row: 4, column: 2),
            CellPosition(row: 5, column: 4),
        ]
    )

    public static let riverFixture = LevelFixture(
        level: LevelDefinition(
            id: "river",
            size: 6,
            catCount: 6,
            maxMistakes: 5,
            colorIDs: [
                [0, 0, 1, 1, 1, 2],
                [1, 1, 1, 1, 2, 2],
                [1, 1, 2, 2, 2, 2],
                [1, 3, 3, 4, 2, 2],
                [3, 3, 4, 4, 4, 2],
                [3, 3, 3, 4, 4, 5],
            ]
        ),
        solution: [
            CellPosition(row: 0, column: 0),
            CellPosition(row: 1, column: 2),
            CellPosition(row: 2, column: 4),
            CellPosition(row: 3, column: 1),
            CellPosition(row: 4, column: 3),
            CellPosition(row: 5, column: 5),
        ]
    )

    public static let terracesFixture = LevelFixture(
        level: LevelDefinition(
            id: "terraces",
            size: 6,
            catCount: 6,
            maxMistakes: 5,
            colorIDs: [
                [0, 1, 3, 3, 3, 2],
                [1, 1, 1, 3, 2, 2],
                [4, 4, 3, 3, 2, 2],
                [4, 4, 3, 3, 3, 2],
                [4, 4, 5, 5, 5, 2],
                [4, 4, 5, 5, 5, 2],
            ]
        ),
        solution: [
            CellPosition(row: 0, column: 0),
            CellPosition(row: 1, column: 2),
            CellPosition(row: 2, column: 5),
            CellPosition(row: 3, column: 3),
            CellPosition(row: 4, column: 1),
            CellPosition(row: 5, column: 4),
        ]
    )

    public static let fixtures = [meadowFixture, riverFixture, terracesFixture]

    public static let meadow = meadowFixture.level
    public static let river = riverFixture.level
    public static let terraces = terracesFixture.level
    public static let all = fixtures.map(\.level)
}
