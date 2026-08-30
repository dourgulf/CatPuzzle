enum RegionGeometryAnalyzer {
    static func analyze(_ partition: RegionPartition) -> RegionGeometryMetrics {
        let areas = partition.areasByRegionID
        let connectedCount = areas.keys.filter {
            partition.isConnected(regionID: $0)
        }.count
        let regionsWithHoles = areas.keys.sorted().filter {
            hasHole(regionID: $0, partition: partition)
        }
        let largestArea = areas.values.max() ?? 0
        let cellCount = max(1, partition.size * partition.size)

        return RegionGeometryMetrics(
            areasByRegionID: areas,
            connectedRegionCount: connectedCount,
            regionsWithHoles: regionsWithHoles,
            singletonRegionCount: areas.values.filter { $0 == 1 }.count,
            largestRegionFraction: Double(largestArea) / Double(cellCount),
            narrowCorridorCellCount: narrowCorridorCount(partition)
        )
    }

    static func matches(
        _ metrics: RegionGeometryMetrics,
        size: Int,
        difficulty: GeneratorDifficulty,
        profile: RegionGeometryProfile
    ) -> Bool {
        guard metrics.connectedRegionCount == size else { return false }

        switch profile {
        case .dominantBackground:
            let maximumLargestRegionFraction = difficulty == .easy ? 0.45 : 0.70
            guard (0.25...maximumLargestRegionFraction).contains(
                metrics.largestRegionFraction
            ),
                  metrics.singletonRegionCount == (difficulty == .easy ? 1 : 0) else {
                return false
            }
            let largestRegionID = metrics.areasByRegionID.max {
                $0.value < $1.value
            }?.key
            return metrics.areasByRegionID.allSatisfy { regionID, area in
                regionID == largestRegionID || area <= 12
            } && metrics.regionsWithHoles.allSatisfy { $0 == largestRegionID }

        case .balancedMosaic:
            let minimumArea = max(2, size / 2)
            return difficulty != .easy
                && metrics.singletonRegionCount == 0
                && metrics.largestRegionFraction <= 0.28
                && metrics.regionsWithHoles.isEmpty
                && metrics.areasByRegionID.values.allSatisfy {
                    (minimumArea...(2 * size)).contains($0)
                }
        }
    }

    private static func hasHole(
        regionID: Int,
        partition: RegionPartition
    ) -> Bool {
        let size = partition.size
        var remaining = Set((0..<size).flatMap { row in
            (0..<size).compactMap { column -> CellPosition? in
                partition.regionIDs[row][column] != regionID
                    ? CellPosition(row: row, column: column)
                    : nil
            }
        })

        while let first = remaining.first {
            var reachesBoundary = false
            var queue = [first]
            remaining.remove(first)
            while let current = queue.popLast() {
                if current.row == 0 || current.column == 0
                    || current.row == size - 1 || current.column == size - 1 {
                    reachesBoundary = true
                }
                for neighbor in orthogonalNeighbors(of: current, size: size)
                where remaining.remove(neighbor) != nil {
                    queue.append(neighbor)
                }
            }
            if !reachesBoundary { return true }
        }
        return false
    }

    private static func narrowCorridorCount(_ partition: RegionPartition) -> Int {
        var count = 0
        for row in 0..<partition.size {
            for column in 0..<partition.size {
                let regionID = partition.regionIDs[row][column]
                let sameRegionNeighbors = orthogonalNeighbors(
                    of: CellPosition(row: row, column: column),
                    size: partition.size
                ).filter {
                    partition.regionIDs[$0.row][$0.column] == regionID
                }.count
                if partition.areasByRegionID[regionID, default: 0] > 2,
                   sameRegionNeighbors <= 1 {
                    count += 1
                }
            }
        }
        return count
    }

    private static func orthogonalNeighbors(
        of position: CellPosition,
        size: Int
    ) -> [CellPosition] {
        [
            CellPosition(row: position.row - 1, column: position.column),
            CellPosition(row: position.row + 1, column: position.column),
            CellPosition(row: position.row, column: position.column - 1),
            CellPosition(row: position.row, column: position.column + 1),
        ].filter {
            (0..<size).contains($0.row) && (0..<size).contains($0.column)
        }
    }
}
