public enum PuzzleSolutionResult: Equatable, Sendable {
    case none
    case unique([CellPosition])
    case multiple
}

public enum PuzzleSolver {
    public static func solve(level: LevelDefinition) -> PuzzleSolutionResult {
        let foundSolutions = solutions(for: level, limit: 2)
        switch foundSolutions.count {
        case 0:
            return .none
        case 1:
            return .unique(foundSolutions[0])
        default:
            return .multiple
        }
    }

    public static func solutions(
        for level: LevelDefinition,
        limit: Int = 2
    ) -> [[CellPosition]] {
        guard limit > 0,
              (try? LevelValidator.validate(level)) != nil,
              var puzzle = try? level.makePuzzle() else {
            return []
        }

        var foundSolutions: [[CellPosition]] = []
        var placements: [CellPosition] = []
        var usedColumns: Set<Int> = []
        var usedRegions: Set<Int> = []

        func search(row: Int) {
            guard foundSolutions.count < limit else { return }

            if row == level.size {
                if PuzzleValidator.isSolved(puzzle) {
                    foundSolutions.append(placements)
                }
                return
            }

            for column in 0..<level.size {
                guard foundSolutions.count < limit else { return }

                let regionID = level.regionIDs[row][column]
                guard !usedColumns.contains(column),
                      !usedRegions.contains(regionID),
                      isNotAdjacentToPreviousRow(column, placements: placements),
                      PuzzleValidator.canPlaceCat(
                          atRow: row,
                          column: column,
                          in: puzzle
                      ) else {
                    continue
                }

                let position = CellPosition(row: row, column: column)
                try? puzzle.setState(.cat, atRow: row, column: column)
                placements.append(position)
                usedColumns.insert(column)
                usedRegions.insert(regionID)

                search(row: row + 1)

                usedRegions.remove(regionID)
                usedColumns.remove(column)
                placements.removeLast()
                try? puzzle.setState(.empty, atRow: row, column: column)
            }
        }

        search(row: 0)
        return foundSolutions
    }

    private static func isNotAdjacentToPreviousRow(
        _ column: Int,
        placements: [CellPosition]
    ) -> Bool {
        guard let previous = placements.last else { return true }
        return abs(previous.column - column) > 1
    }
}
