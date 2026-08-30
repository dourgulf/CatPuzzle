enum SolutionPermutationGenerator {
    struct SearchResult {
        let solution: [CellPosition]?
        let visitedNodes: Int
    }

    static func generate(
        size: Int,
        rng: inout SeededRandomNumberGenerator,
        nodeBudget: Int,
        requiresHardBlueprint: Bool = false
    ) -> SearchResult {
        guard size > 0, nodeBudget > 0 else {
            return SearchResult(solution: nil, visitedNodes: 0)
        }

        let requiredColumns: [Int: Int]
        if requiresHardBlueprint {
            guard size >= 5 else {
                return SearchResult(solution: nil, visitedNodes: 0)
            }
            var patterns: [[Int]] = []
            for base in 2...(size - 5) {
                patterns.append([base + 1, base - 2, base, base + 2, base + 4])
            }
            patterns.shuffle(using: &rng)
            guard let pattern = patterns.first else {
                return SearchResult(solution: nil, visitedNodes: 0)
            }
            requiredColumns = Dictionary(uniqueKeysWithValues: pattern.enumerated().map {
                ($0.offset, $0.element)
            })
        } else {
            requiredColumns = [:]
        }

        var columns = Array(repeating: -1, count: size)
        var usedColumns = OccupiedColumns(size: size)
        var visitedNodes = 0

        func search(row: Int) -> Bool {
            guard visitedNodes < nodeBudget else { return false }
            visitedNodes += 1
            if row == size { return true }

            let candidates = Array(0..<size)
                .filter { !usedColumns.contains($0) }
                .filter { column in
                    requiredColumns[row].map { column == $0 } ?? true
                }
                .shuffled(using: &rng)
            for column in candidates {
                if row > 0, abs(columns[row - 1] - column) <= 1 { continue }
                columns[row] = column
                usedColumns.insert(column)
                if search(row: row + 1) { return true }
                usedColumns.remove(column)
                columns[row] = -1
            }
            return false
        }

        guard search(row: 0) else {
            return SearchResult(solution: nil, visitedNodes: visitedNodes)
        }
        return SearchResult(
            solution: columns.enumerated().map {
                CellPosition(row: $0.offset, column: $0.element)
            },
            visitedNodes: visitedNodes
        )
    }
}

private struct OccupiedColumns {
    private var bits: UInt64 = 0
    private let size: Int

    init(size: Int) {
        self.size = size
    }

    func contains(_ column: Int) -> Bool {
        guard column >= 0, column < size, column < 64 else { return false }
        return bits & (UInt64(1) << UInt64(column)) != 0
    }

    mutating func insert(_ column: Int) {
        bits |= UInt64(1) << UInt64(column)
    }

    mutating func remove(_ column: Int) {
        bits &= ~(UInt64(1) << UInt64(column))
    }
}
