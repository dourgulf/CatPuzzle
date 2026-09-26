/// The first ten ordinary levels, drawn by hand to rehearse the three rules.
///
/// Each board begins with a one-cell color block. Later blocks become single
/// candidates after marking cells in a placed cat's row, column, color block,
/// or eight neighboring cells. None requires a trial or a multi-block pattern.
/// The final background block is settled by the remaining row and column.
public enum OpeningLevels {
    public static let fixtures: [LevelFixture] = [
        // 1: A one-cell start, then touching, rows, and columns narrow
        // progressively wider color blocks.
        fixture("opening-01", 6, [
            [0, 1, 1, 5, 5, 5],
            [5, 1, 1, 2, 2, 5],
            [5, 2, 2, 2, 2, 5],
            [5, 3, 3, 3, 3, 5],
            [5, 4, 4, 4, 4, 5],
            [5, 5, 5, 5, 5, 5],
        ], [0, 2, 4, 1, 3, 5]),
        // 2: The first vertical block is resolved by its upper row.
        fixture("opening-02", 6, [
            [5, 5, 1, 1, 1, 0],
            [5, 2, 2, 1, 5, 5],
            [5, 2, 2, 3, 3, 5],
            [5, 4, 4, 4, 3, 5],
            [5, 5, 4, 5, 5, 5],
            [5, 5, 5, 5, 5, 5],
        ], [5, 3, 1, 4, 2, 0]),
        // 3: Alternate a diagonal exclusion and a row exclusion.
        fixture("opening-03", 6, [
            [5, 0, 1, 1, 5, 5],
            [5, 5, 1, 1, 5, 2],
            [3, 5, 5, 5, 5, 2],
            [3, 4, 4, 5, 5, 5],
            [5, 4, 4, 5, 5, 5],
            [5, 5, 5, 5, 5, 5],
        ], [1, 3, 5, 0, 2, 4]),
        // 4: A color block crosses a row boundary, emphasizing that
        // color and row constraints work together.
        fixture("opening-04", 6, [
            [5, 5, 1, 1, 0, 5],
            [2, 5, 1, 1, 5, 5],
            [2, 5, 5, 5, 5, 3],
            [5, 5, 5, 4, 4, 3],
            [5, 5, 5, 4, 4, 5],
            [5, 5, 5, 5, 5, 5],
        ], [4, 2, 0, 5, 3, 1]),
        // 5: The larger board still has a visible one-block-at-a-time chain.
        fixture("opening-05", 7, [
            [0, 1, 1, 6, 6, 6, 6],
            [6, 1, 1, 2, 2, 6, 6],
            [6, 2, 2, 2, 2, 6, 3],
            [6, 4, 4, 6, 6, 6, 3],
            [6, 4, 5, 5, 6, 6, 6],
            [6, 6, 5, 5, 6, 6, 6],
            [6, 6, 6, 6, 6, 6, 6],
        ], [0, 2, 4, 6, 1, 3, 5]),
        // 6: Work from the opposite corner; column and diagonal marks
        // clear the middle row's wider color block.
        fixture("opening-06", 7, [
            [6, 6, 6, 1, 1, 1, 0],
            [6, 6, 2, 2, 1, 6, 6],
            [3, 6, 2, 2, 2, 2, 6],
            [3, 6, 6, 6, 4, 4, 6],
            [6, 6, 6, 5, 5, 4, 6],
            [6, 6, 6, 5, 5, 6, 6],
            [6, 6, 6, 6, 6, 6, 6],
        ], [6, 4, 2, 0, 5, 3, 1]),
        // 7: A previously occupied column chooses between two cells in
        // the same row; the next block is cleared by touching.
        fixture("opening-07", 7, [
            [6, 0, 1, 1, 6, 6, 6],
            [6, 6, 1, 1, 2, 2, 6],
            [6, 6, 6, 6, 2, 2, 6],
            [3, 3, 4, 6, 6, 6, 6],
            [6, 4, 4, 5, 5, 6, 6],
            [6, 5, 5, 5, 5, 6, 6],
            [6, 6, 6, 6, 6, 6, 6],
        ], [1, 3, 5, 0, 2, 4, 6]),
        // 8: A previously occupied column removes a candidate beyond
        // the nearest cat's touching range on the eight-row board.
        fixture("opening-08", 8, [
            [0, 1, 1, 7, 7, 7, 7, 7],
            [7, 1, 1, 2, 2, 7, 7, 7],
            [7, 2, 2, 2, 2, 3, 3, 7],
            [7, 4, 3, 3, 3, 3, 3, 7],
            [7, 4, 5, 5, 7, 7, 7, 7],
            [7, 7, 5, 5, 6, 6, 7, 7],
            [7, 7, 7, 7, 6, 6, 7, 7],
            [7, 7, 7, 7, 7, 7, 7, 7],
        ], [0, 2, 4, 6, 1, 3, 5, 7]),
        // 9: A reflected path changes which corners and columns matter.
        fixture("opening-09", 8, [
            [7, 7, 7, 7, 7, 1, 1, 0],
            [7, 7, 7, 2, 2, 1, 1, 7],
            [7, 3, 3, 2, 2, 2, 2, 7],
            [7, 3, 3, 3, 3, 4, 4, 7],
            [7, 7, 7, 7, 5, 5, 4, 7],
            [7, 7, 6, 6, 5, 5, 7, 7],
            [7, 7, 6, 6, 7, 7, 7, 7],
            [7, 7, 7, 7, 7, 7, 7, 7],
        ], [7, 5, 3, 1, 6, 4, 2, 0]),
        // 10: Seven small blocks are settled directly; the last cat
        // follows from the only unused row, column, and background block.
        fixture("opening-10", 8, [
            [7, 0, 1, 1, 7, 7, 7, 7],
            [7, 7, 1, 1, 2, 2, 7, 7],
            [7, 7, 7, 7, 2, 2, 7, 3],
            [4, 4, 7, 7, 7, 7, 7, 3],
            [4, 5, 5, 7, 7, 7, 7, 7],
            [7, 5, 5, 6, 6, 7, 7, 7],
            [7, 7, 7, 6, 6, 7, 7, 7],
            [7, 7, 7, 7, 7, 7, 7, 7],
        ], [1, 3, 5, 7, 0, 2, 4, 6]),
    ]

    public static let all = fixtures.map(\.level)

    private static func fixture(
        _ id: String,
        _ size: Int,
        _ regionIDs: [[Int]],
        _ catColumnsByRow: [Int]
    ) -> LevelFixture {
        LevelFixture(
            level: LevelDefinition(
                id: id,
                size: size,
                catCount: size,
                maxMistakes: 3,
                regionIDs: regionIDs
            ),
            solution: catColumnsByRow.enumerated().map { row, column in
                CellPosition(row: row, column: column)
            }
        )
    }
}
