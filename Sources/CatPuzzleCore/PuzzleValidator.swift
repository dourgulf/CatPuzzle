public enum PuzzleValidator {
    public static func canPlaceCat(
        atRow row: Int,
        column: Int,
        in puzzle: Puzzle
    ) -> Bool {
        guard let targetCell = puzzle.cell(atRow: row, column: column) else {
            return false
        }
        return !catCells(in: puzzle).contains {
            $0.row == row
                || $0.column == column
                || $0.regionID == targetCell.regionID
                || areAdjacent($0, targetCell)
        }
    }

    public static func hasRowConflict(in puzzle: Puzzle) -> Bool {
        Dictionary(grouping: catCells(in: puzzle), by: \.row)
            .values
            .contains { $0.count > 1 }
    }

    public static func hasColumnConflict(in puzzle: Puzzle) -> Bool {
        Dictionary(grouping: catCells(in: puzzle), by: \.column)
            .values
            .contains { $0.count > 1 }
    }

    public static func hasRegionConflict(in puzzle: Puzzle) -> Bool {
        Dictionary(grouping: catCells(in: puzzle), by: \.regionID)
            .values
            .contains { $0.count > 1 }
    }

    public static func hasAdjacentCats(in puzzle: Puzzle) -> Bool {
        let cats = catCells(in: puzzle)
        for firstIndex in cats.indices {
            for secondIndex in cats.index(after: firstIndex)..<cats.endIndex
            where areAdjacent(cats[firstIndex], cats[secondIndex]) {
                return true
            }
        }
        return false
    }

    public static func isSolved(_ puzzle: Puzzle) -> Bool {
        let cats = catCells(in: puzzle)
        let puzzleRegionIDs = Set(puzzle.cells.map(\.regionID))
        let occupiedRegionIDs = Set(cats.map(\.regionID))

        return cats.count == puzzle.size
            && puzzleRegionIDs.count == puzzle.size
            && occupiedRegionIDs == puzzleRegionIDs
            && !hasRowConflict(in: puzzle)
            && !hasColumnConflict(in: puzzle)
            && !hasRegionConflict(in: puzzle)
            && !hasAdjacentCats(in: puzzle)
    }

    private static func areAdjacent(_ first: Cell, _ second: Cell) -> Bool {
        abs(first.row - second.row) <= 1
            && abs(first.column - second.column) <= 1
    }

    private static func catCells(in puzzle: Puzzle) -> [Cell] {
        puzzle.cells.filter {
            puzzle.state(atRow: $0.row, column: $0.column) == .cat
        }
    }
}
