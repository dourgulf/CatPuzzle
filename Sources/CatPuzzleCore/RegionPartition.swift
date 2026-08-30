struct RegionPartition: Equatable, Sendable {
    struct BoundaryMove: Equatable, Sendable {
        let position: CellPosition
        let sourceRegionID: Int
        let destinationRegionID: Int
    }

    let size: Int
    let solutionByRegionID: [Int: CellPosition]
    private(set) var regionIDs: [[Int]]
    let restrictedRowsByRegionID: [Int: Set<Int>]

    var areasByRegionID: [Int: Int] {
        Dictionary(grouping: regionIDs.flatMap { $0 }, by: { $0 })
            .mapValues(\.count)
    }

    var canonicalHash: [Int] {
        regionIDs.flatMap { $0 }
    }

    static func build(
        size: Int,
        solution: [CellPosition],
        difficulty: GeneratorDifficulty,
        profile: RegionGeometryProfile,
        rng: inout SeededRandomNumberGenerator
    ) -> RegionPartition? {
        guard solution.count == size else { return nil }

        if difficulty == .easy, profile == .dominantBackground {
            return buildEasyCascade(size: size, solution: solution, rng: &rng)
        }
        if difficulty == .medium, profile == .dominantBackground {
            return buildLockedCascade(
                size: size,
                solution: solution,
                difficulty: difficulty,
                rng: &rng
            )
        }
        if difficulty == .hard, profile == .dominantBackground {
            return buildHardCascade(size: size, solution: solution, rng: &rng)
        }

        let anchorRegionID = difficulty == .easy ? 0 : nil
        let lockedRegionIDs = difficulty == .easy ? [] : [0, 1]
        let lockedRows = Set(lockedRegionIDs)
        var restrictions: [Int: Set<Int>] = [:]
        for regionID in lockedRegionIDs {
            restrictions[regionID] = lockedRows
        }

        let targets = targetAreas(
            size: size,
            difficulty: difficulty,
            profile: profile,
            anchorRegionID: anchorRegionID,
            rng: &rng
        )
        var grid = Array(
            repeating: Array(repeating: -1, count: size),
            count: size
        )
        var seeds: [Int: CellPosition] = [:]
        for (regionID, position) in solution.enumerated() {
            guard (0..<size).contains(position.row),
                  (0..<size).contains(position.column),
                  grid[position.row][position.column] == -1 else {
                return nil
            }
            grid[position.row][position.column] = regionID
            seeds[regionID] = position
        }

        var areas = Dictionary(uniqueKeysWithValues: (0..<size).map { ($0, 1) })
        var remaining = size * size - size

        while remaining > 0 {
            var frontier: [(position: CellPosition, regionID: Int, deficit: Int)] = []
            for row in 0..<size {
                for column in 0..<size where grid[row][column] == -1 {
                    let position = CellPosition(row: row, column: column)
                    for regionID in adjacentRegionIDs(to: position, in: grid) {
                        if regionID == anchorRegionID { continue }
                        if let rows = restrictions[regionID], !rows.contains(row) {
                            continue
                        }
                        frontier.append((
                            position,
                            regionID,
                            targets[regionID, default: size] - areas[regionID, default: 0]
                        ))
                    }
                }
            }

            guard !frontier.isEmpty else { return nil }
            let maximumDeficit = frontier.map(\.deficit).max() ?? 0
            let preferred = frontier.filter { $0.deficit == maximumDeficit }
            let selected = preferred[Int.random(in: 0..<preferred.count, using: &rng)]
            grid[selected.position.row][selected.position.column] = selected.regionID
            areas[selected.regionID, default: 0] += 1
            remaining -= 1
        }

        let partition = RegionPartition(
            size: size,
            solutionByRegionID: seeds,
            regionIDs: grid,
            restrictedRowsByRegionID: restrictions
        )
        let metrics = RegionGeometryAnalyzer.analyze(partition)
        return partition.allRegionsAreConnected
            && RegionGeometryAnalyzer.matches(
                metrics,
                size: size,
                difficulty: difficulty,
                profile: profile
            )
            ? partition
            : nil
    }

    private static func buildEasyCascade(
        size: Int,
        solution: [CellPosition],
        rng: inout SeededRandomNumberGenerator
    ) -> RegionPartition? {
        let backgroundRegionID = size - 1
        var grid = Array(
            repeating: Array(repeating: backgroundRegionID, count: size),
            count: size
        )
        let seeds = Dictionary(
            uniqueKeysWithValues: solution.enumerated().map { ($0.offset, $0.element) }
        )
        for (regionID, position) in seeds {
            grid[position.row][position.column] = regionID
        }

        for regionID in 1..<backgroundRegionID {
            let cat = solution[regionID]
            let previousRow = cat.row - 1
            var available = Set(0..<size)
            available.remove(solution[previousRow].column)
            let segment = connectedSegment(
                centeredAt: cat.column,
                availableColumns: available,
                targetCount: 3,
                rng: &rng
            )
            guard segment.contains(cat.column) else { return nil }
            for column in segment {
                grid[previousRow][column] = regionID
            }
        }

        let basePartition = RegionPartition(
            size: size,
            solutionByRegionID: seeds,
            regionIDs: grid,
            restrictedRowsByRegionID: [:]
        )
        guard basePartition.allRegionsAreConnected else { return nil }

        // Keep the singleton logical anchor, but grow the remaining small
        // regions beyond their opening row segment so the background does not
        // dominate the board. Every transfer preserves the background's
        // eight-neighbor connectivity and never consumes its planted cat.
        let backgroundCat = solution[backgroundRegionID]
        for regionID in 1..<backgroundRegionID {
            while grid.flatMap({ $0 }).filter({ $0 == regionID }).count < 6 {
                let candidates = (0..<size).flatMap { row in
                    (0..<size).compactMap { column -> CellPosition? in
                        let position = CellPosition(row: row, column: column)
                        guard position != backgroundCat,
                              grid[row][column] == backgroundRegionID,
                              Self.orthogonalNeighbors(of: position, size: size)
                                .contains(where: {
                                    grid[$0.row][$0.column] == regionID
                                }) else {
                            return nil
                        }
                        return position
                    }
                }.shuffled(using: &rng)

                var accepted = false
                for position in candidates {
                    var proposed = grid
                    proposed[position.row][position.column] = regionID
                    let partition = RegionPartition(
                        size: size,
                        solutionByRegionID: seeds,
                        regionIDs: proposed,
                        restrictedRowsByRegionID: [:]
                    )
                    guard partition.isConnected(regionID: backgroundRegionID) else {
                        continue
                    }
                    grid = proposed
                    accepted = true
                    break
                }
                guard accepted else { return nil }
            }
        }

        let partition = RegionPartition(
            size: size,
            solutionByRegionID: seeds,
            regionIDs: grid,
            restrictedRowsByRegionID: [:]
        )
        let metrics = RegionGeometryAnalyzer.analyze(partition)
        return partition.allRegionsAreConnected
            && RegionGeometryAnalyzer.matches(
                metrics,
                size: size,
                difficulty: .easy,
                profile: .dominantBackground
            )
            ? partition
            : nil
    }

    private static func buildLockedCascade(
        size: Int,
        solution: [CellPosition],
        difficulty: GeneratorDifficulty,
        rng: inout SeededRandomNumberGenerator
    ) -> RegionPartition? {
        let backgroundRegionID = size - 1
        var grid = Array(
            repeating: Array(repeating: backgroundRegionID, count: size),
            count: size
        )
        let seeds = Dictionary(
            uniqueKeysWithValues: solution.enumerated().map { ($0.offset, $0.element) }
        )
        for (regionID, position) in seeds {
            grid[position.row][position.column] = regionID
        }

        let regionTwoCat = solution[2]
        guard grid[1][regionTwoCat.column] == backgroundRegionID else {
            return nil
        }
        grid[1][regionTwoCat.column] = 2

        for regionID in 0...1 {
            let cat = solution[regionID]
            let neighborColumns = [cat.column - 1, cat.column + 1]
                .filter { (0..<size).contains($0) }
                .filter { grid[cat.row][$0] == backgroundRegionID }
            guard let column = neighborColumns.randomElement(using: &rng) else {
                return nil
            }
            grid[cat.row][column] = regionID
        }

        for regionID in 3..<backgroundRegionID {
            let cat = solution[regionID]
            let previousRow = cat.row - 1
            let available = Set((0..<size).filter {
                grid[previousRow][$0] == backgroundRegionID
            })
            let segment = connectedSegment(
                centeredAt: cat.column,
                availableColumns: available,
                targetCount: 3,
                rng: &rng
            )
            guard segment.contains(cat.column) else { return nil }
            for column in segment {
                grid[previousRow][column] = regionID
            }
        }

        let partition = RegionPartition(
            size: size,
            solutionByRegionID: seeds,
            regionIDs: grid,
            restrictedRowsByRegionID: [0: [0, 1], 1: [0, 1]]
        )
        let metrics = RegionGeometryAnalyzer.analyze(partition)
        return partition.allRegionsAreConnected
            && RegionGeometryAnalyzer.matches(
                metrics,
                size: size,
                difficulty: difficulty,
                profile: .dominantBackground
            )
            ? partition
            : nil
    }

    private static func buildHardCascade(
        size: Int,
        solution: [CellPosition],
        rng: inout SeededRandomNumberGenerator
    ) -> RegionPartition? {
        let backgroundRegionID = size - 1
        let first = solution[2]
        let linkCat = solution[3]
        let followupCat = solution[4]
        let direction = linkCat.column > first.column ? 1 : -1
        guard linkCat.column == first.column + 2 * direction,
              followupCat.column == first.column + 4 * direction else {
            return nil
        }

        var grid = Array(
            repeating: Array(repeating: backgroundRegionID, count: size),
            count: size
        )
        let seeds = Dictionary(
            uniqueKeysWithValues: solution.enumerated().map { ($0.offset, $0.element) }
        )
        for (regionID, position) in seeds {
            grid[position.row][position.column] = regionID
        }

        for (regionID, decoyColumn) in [
            (0, first.column),
            (1, first.column - direction),
        ] {
            let cat = solution[regionID]
            guard abs(cat.column - decoyColumn) == 1,
                  grid[cat.row][decoyColumn] == backgroundRegionID else {
                return nil
            }
            grid[cat.row][decoyColumn] = regionID
        }

        let regionTwoDecoy = CellPosition(row: 1, column: first.column)
        guard grid[regionTwoDecoy.row][regionTwoDecoy.column] == backgroundRegionID else {
            return nil
        }
        grid[regionTwoDecoy.row][regionTwoDecoy.column] = 2
        let regionOneBridge = CellPosition(
            row: 0,
            column: first.column - direction
        )
        guard grid[regionOneBridge.row][regionOneBridge.column] == backgroundRegionID else {
            return nil
        }
        grid[regionOneBridge.row][regionOneBridge.column] = 1

        for column in stride(
            from: first.column + direction,
            through: linkCat.column + direction,
            by: direction
        ) {
            guard grid[linkCat.row][column] == backgroundRegionID
                    || column == linkCat.column else {
                return nil
            }
            grid[linkCat.row][column] = 3
        }

        for column in stride(
            from: linkCat.column,
            through: followupCat.column,
            by: direction
        ) {
            guard grid[followupCat.row][column] == backgroundRegionID
                    || column == followupCat.column else {
                return nil
            }
            grid[followupCat.row][column] = 4
        }

        if backgroundRegionID > 5 {
            for regionID in 5..<backgroundRegionID {
                let cat = solution[regionID]
                let previousRow = cat.row - 1
                let available = Set((0..<size).filter {
                    grid[previousRow][$0] == backgroundRegionID
                })
                let segment = connectedSegment(
                    centeredAt: cat.column,
                    availableColumns: available,
                    targetCount: 3,
                    rng: &rng
                )
                guard segment.contains(cat.column) else { return nil }
                for column in segment {
                    grid[previousRow][column] = regionID
                }
            }
        }
        let tailBridgeRegionID = backgroundRegionID - 2
        let tailBridgeColumn = solution[tailBridgeRegionID].column
        let tailBridgeRow = tailBridgeRegionID + 1
        guard grid[tailBridgeRow][tailBridgeColumn] == backgroundRegionID else {
            return nil
        }
        grid[tailBridgeRow][tailBridgeColumn] = tailBridgeRegionID

        absorbDisconnectedComponents(
            of: backgroundRegionID,
            keeping: solution[backgroundRegionID],
            in: &grid
        )

        let partition = RegionPartition(
            size: size,
            solutionByRegionID: seeds,
            regionIDs: grid,
            restrictedRowsByRegionID: [0: [0, 1], 1: [0, 1]]
        )
        let metrics = RegionGeometryAnalyzer.analyze(partition)
        return partition.allRegionsAreConnected
            && RegionGeometryAnalyzer.matches(
                metrics,
                size: size,
                difficulty: .hard,
                profile: .dominantBackground
            )
            ? partition
            : nil
    }

    private static func absorbDisconnectedComponents(
        of regionID: Int,
        keeping anchor: CellPosition,
        in grid: inout [[Int]]
    ) {
        let size = grid.count
        var unseen = Set((0..<size).flatMap { row in
            (0..<size).compactMap { column -> CellPosition? in
                grid[row][column] == regionID
                    ? CellPosition(row: row, column: column)
                    : nil
            }
        })
        var components: [Set<CellPosition>] = []
        while let first = unseen.first {
            var component: Set<CellPosition> = [first]
            var queue = [first]
            unseen.remove(first)
            while let current = queue.popLast() {
                for neighbor in orthogonalNeighbors(of: current, size: size)
                where unseen.remove(neighbor) != nil {
                    component.insert(neighbor)
                    queue.append(neighbor)
                }
            }
            components.append(component)
        }

        let disposable = components
            .filter { !$0.contains(anchor) }
            .sorted { $0.count < $1.count }
        var areas = Dictionary(grouping: grid.flatMap { $0 }, by: { $0 })
            .mapValues(\.count)
        for component in disposable {
            var remaining = component
            while !remaining.isEmpty {
                let frontier = remaining.flatMap { position in
                    Set(orthogonalNeighbors(of: position, size: size).compactMap { neighbor in
                        let neighborRegionID = grid[neighbor.row][neighbor.column]
                        return neighborRegionID == regionID ? nil : neighborRegionID
                    }).map { destination in
                        (position: position, destination: destination)
                    }
                }
                guard let selected = frontier.min(by: { lhs, rhs in
                    let lhsArea = areas[lhs.destination, default: 0]
                    let rhsArea = areas[rhs.destination, default: 0]
                    if lhsArea != rhsArea { return lhsArea < rhsArea }
                    if lhs.position.row != rhs.position.row {
                        return lhs.position.row < rhs.position.row
                    }
                    if lhs.position.column != rhs.position.column {
                        return lhs.position.column < rhs.position.column
                    }
                    return lhs.destination < rhs.destination
                }) else {
                    break
                }
                grid[selected.position.row][selected.position.column] = selected.destination
                areas[selected.destination, default: 0] += 1
                remaining.remove(selected.position)
            }
        }
    }

    private static func connectedSegment(
        centeredAt center: Int,
        availableColumns: Set<Int>,
        targetCount: Int,
        rng: inout SeededRandomNumberGenerator
    ) -> [Int] {
        guard availableColumns.contains(center) else { return [] }
        var segment: Set<Int> = [center]
        while segment.count < targetCount {
            let frontier = Set(segment.flatMap { [$0 - 1, $0 + 1] })
                .intersection(availableColumns)
                .subtracting(segment)
                .sorted()
            guard !frontier.isEmpty else { break }
            segment.insert(frontier[Int.random(in: 0..<frontier.count, using: &rng)])
        }
        return segment.sorted()
    }

    func boundaryMoves() -> [BoundaryMove] {
        var moves: [BoundaryMove] = []
        for row in 0..<size {
            for column in 0..<size {
                let position = CellPosition(row: row, column: column)
                let source = regionIDs[row][column]
                guard solutionByRegionID[source] != position else { continue }

                for destination in Self.adjacentRegionIDs(to: position, in: regionIDs)
                where destination != source {
                    if let rows = restrictedRowsByRegionID[destination],
                       !rows.contains(row) {
                        continue
                    }
                    if let rows = restrictedRowsByRegionID[source],
                       !rows.contains(row) {
                        continue
                    }
                    moves.append(BoundaryMove(
                        position: position,
                        sourceRegionID: source,
                        destinationRegionID: destination
                    ))
                }
            }
        }
        return moves
    }

    func applying(_ move: BoundaryMove) -> RegionPartition? {
        let position = move.position
        guard regionIDs[position.row][position.column] == move.sourceRegionID,
              solutionByRegionID[move.sourceRegionID] != position,
              Self.adjacentRegionIDs(to: position, in: regionIDs)
                .contains(move.destinationRegionID) else {
            return nil
        }

        var updated = self
        updated.regionIDs[position.row][position.column] = move.destinationRegionID
        guard updated.isConnected(regionID: move.sourceRegionID),
              updated.isConnected(regionID: move.destinationRegionID) else {
            return nil
        }
        return updated
    }

    var allRegionsAreConnected: Bool {
        solutionByRegionID.keys.allSatisfy { isConnected(regionID: $0) }
    }

    func isConnected(regionID: Int) -> Bool {
        let cells = Set((0..<size).flatMap { row in
            (0..<size).compactMap { column -> CellPosition? in
                regionIDs[row][column] == regionID
                    ? CellPosition(row: row, column: column)
                    : nil
            }
        })
        guard let first = cells.first else { return false }

        var reached: Set<CellPosition> = [first]
        var queue = [first]
        while let current = queue.popLast() {
            for neighbor in Self.connectedNeighbors(of: current, size: size)
            where cells.contains(neighbor) && reached.insert(neighbor).inserted {
                queue.append(neighbor)
            }
        }
        return reached.count == cells.count
    }

    private static func targetAreas(
        size: Int,
        difficulty: GeneratorDifficulty,
        profile: RegionGeometryProfile,
        anchorRegionID: Int?,
        rng: inout SeededRandomNumberGenerator
    ) -> [Int: Int] {
        let cellCount = size * size
        var targets = Dictionary(uniqueKeysWithValues: (0..<size).map { ($0, size) })

        switch profile {
        case .dominantBackground:
            let background = size - 1
            targets[background] = Int(Double(cellCount) * 0.42)
            let fixed = targets[background, default: 0] + (anchorRegionID == nil ? 0 : 1)
            let flexible = (0..<size).filter { $0 != background && $0 != anchorRegionID }
            let base = max(2, (cellCount - fixed) / max(1, flexible.count))
            for regionID in flexible {
                targets[regionID] = min(12, max(2, base + Int.random(in: -1...1, using: &rng)))
            }
        case .balancedMosaic:
            for regionID in 0..<size {
                targets[regionID] = max(2, size + Int.random(in: -2...2, using: &rng))
            }
        }

        if let anchorRegionID {
            targets[anchorRegionID] = 1
        }
        if difficulty != .easy {
            targets[0] = max(2, min(targets[0, default: size], 4))
            targets[1] = max(2, min(targets[1, default: size], 4))
        }
        return targets
    }

    private static func adjacentRegionIDs(
        to position: CellPosition,
        in grid: [[Int]]
    ) -> [Int] {
        let values = orthogonalNeighbors(of: position, size: grid.count)
            .map { grid[$0.row][$0.column] }
            .filter { $0 >= 0 }
        return Array(Set(values)).sorted()
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

    private static func connectedNeighbors(
        of position: CellPosition,
        size: Int
    ) -> [CellPosition] {
        (-1...1).flatMap { rowOffset in
            (-1...1).compactMap { columnOffset -> CellPosition? in
                guard rowOffset != 0 || columnOffset != 0 else { return nil }
                let neighbor = CellPosition(
                    row: position.row + rowOffset,
                    column: position.column + columnOffset
                )
                return (0..<size).contains(neighbor.row)
                    && (0..<size).contains(neighbor.column)
                    ? neighbor
                    : nil
            }
        }
    }
}
