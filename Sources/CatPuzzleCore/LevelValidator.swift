public enum LevelValidationError: Error, Equatable, Sendable {
    case invalidSize
    case invalidDimensions
    case invalidRegionCount
    case disconnectedRegion
}

public enum LevelValidator {
    public static func validate(_ level: LevelDefinition) throws {
        guard level.size > 0 else {
            throw LevelValidationError.invalidSize
        }
        guard level.regionIDs.count == level.size,
              level.regionIDs.allSatisfy({ $0.count == level.size }) else {
            throw LevelValidationError.invalidDimensions
        }

        let regionIDs = Set(level.regionIDs.flatMap { $0 })
        guard regionIDs.count == level.size else {
            throw LevelValidationError.invalidRegionCount
        }

        for regionID in regionIDs where !isConnected(regionID, in: level) {
            throw LevelValidationError.disconnectedRegion
        }
    }

    private static func isConnected(
        _ regionID: Int,
        in level: LevelDefinition
    ) -> Bool {
        var cells = Set<CellPosition>()
        for row in 0..<level.size {
            for column in 0..<level.size
            where level.regionIDs[row][column] == regionID {
                cells.insert(CellPosition(row: row, column: column))
            }
        }

        guard let start = cells.first else { return false }

        var visited: Set<CellPosition> = [start]
        var pending = [start]
        let offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]

        while let current = pending.popLast() {
            for (rowOffset, columnOffset) in offsets {
                let neighbor = CellPosition(
                    row: current.row + rowOffset,
                    column: current.column + columnOffset
                )
                if cells.contains(neighbor), visited.insert(neighbor).inserted {
                    pending.append(neighbor)
                }
            }
        }

        return visited.count == cells.count
    }
}
