public enum BuiltInLevels {
    public static let meadow = LevelDefinition(
        id: "meadow",
        size: 6,
        regionIDs: [
            [0, 0, 0, 1, 1, 1],
            [0, 0, 0, 1, 1, 1],
            [2, 2, 2, 3, 3, 3],
            [2, 2, 2, 3, 3, 3],
            [4, 4, 4, 5, 5, 5],
            [4, 4, 4, 5, 5, 5],
        ]
    )

    public static let river = LevelDefinition(
        id: "river",
        size: 6,
        regionIDs: [
            [0, 0, 0, 0, 1, 1],
            [0, 0, 1, 1, 1, 1],
            [2, 2, 2, 3, 3, 3],
            [2, 2, 2, 3, 3, 3],
            [4, 4, 4, 4, 5, 5],
            [4, 4, 5, 5, 5, 5],
        ]
    )

    public static let terraces = LevelDefinition(
        id: "terraces",
        size: 6,
        regionIDs: [
            [0, 0, 0, 0, 0, 1],
            [0, 1, 1, 1, 1, 1],
            [3, 2, 2, 2, 2, 2],
            [3, 3, 3, 3, 3, 2],
            [4, 4, 4, 4, 4, 5],
            [4, 5, 5, 5, 5, 5],
        ]
    )

    public static let all: [LevelDefinition] = [meadow, river, terraces]
}
