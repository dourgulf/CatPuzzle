public enum PuzzleSolutionResult: Equatable, Sendable {
    case none
    case unique([CellPosition])
    case multiple
    case inconclusive
}

public struct PuzzleSolverBudget: Equatable, Sendable {
    public static let unlimited = PuzzleSolverBudget(maxVisitedNodes: .max)

    public let maxVisitedNodes: Int

    public init(maxVisitedNodes: Int) {
        self.maxVisitedNodes = max(0, maxVisitedNodes)
    }
}

public struct PuzzleSolverStatistics: Equatable, Sendable {
    public let visitedNodes: Int
    public let candidateChecks: Int
    public let deadEnds: Int
    public let maxDepth: Int
    public let solutionsFound: Int
    public let didExhaustBudget: Bool

    public init(
        visitedNodes: Int,
        candidateChecks: Int,
        deadEnds: Int,
        maxDepth: Int,
        solutionsFound: Int,
        didExhaustBudget: Bool
    ) {
        self.visitedNodes = visitedNodes
        self.candidateChecks = candidateChecks
        self.deadEnds = deadEnds
        self.maxDepth = maxDepth
        self.solutionsFound = solutionsFound
        self.didExhaustBudget = didExhaustBudget
    }
}

public struct PuzzleSolverReport: Equatable, Sendable {
    public let result: PuzzleSolutionResult
    public let statistics: PuzzleSolverStatistics

    public init(
        result: PuzzleSolutionResult,
        statistics: PuzzleSolverStatistics
    ) {
        self.result = result
        self.statistics = statistics
    }
}

public enum PuzzleSolver {
    /// Certifies whether a level has zero, one, or multiple solutions.
    ///
    /// `visitedNodes` counts search states entered, including the root and
    /// complete solutions. If the budget ends before the search proves one
    /// of those outcomes, the result is `.inconclusive` rather than `.none`.
    public static func solve(
        level: LevelDefinition,
        budget: PuzzleSolverBudget = .unlimited
    ) -> PuzzleSolverReport {
        runSearch(level: level, solutionLimit: 2, budget: budget).report
    }

    /// Returns solutions found before `limit`. This unbudgeted helper is
    /// retained for research and tests; production certification should use
    /// `solve(level:budget:)` so an incomplete proof is explicit.
    public static func solutions(
        for level: LevelDefinition,
        limit: Int = 2
    ) -> [[CellPosition]] {
        runSearch(
            level: level,
            solutionLimit: max(0, limit),
            budget: .unlimited
        ).solutions
    }

    private static func runSearch(
        level: LevelDefinition,
        solutionLimit: Int,
        budget: PuzzleSolverBudget
    ) -> ExactSearchResult {
        guard solutionLimit > 0,
              (try? LevelValidator.validate(level)) != nil else {
            return ExactSearchResult.empty
        }

        var engine = ExactSearchEngine(
            level: level,
            solutionLimit: solutionLimit,
            budget: budget
        )
        engine.search(depth: 0)
        return engine.result
    }
}

private struct ExactSearchResult {
    let solutions: [[CellPosition]]
    let report: PuzzleSolverReport

    static let empty = ExactSearchResult(
        solutions: [],
        report: PuzzleSolverReport(
            result: .none,
            statistics: PuzzleSolverStatistics(
                visitedNodes: 0,
                candidateChecks: 0,
                deadEnds: 0,
                maxDepth: 0,
                solutionsFound: 0,
                didExhaustBudget: false
            )
        )
    )
}

private struct ExactSearchEngine {
    let level: LevelDefinition
    let solutionLimit: Int
    let budget: PuzzleSolverBudget
    let regionIndexByID: [Int: Int]
    let constraints: [ConstraintKind]
    let positionsByConstraint: [ConstraintKind: [CellPosition]]

    var occupiedRows: OccupancyBits
    var occupiedColumns: OccupancyBits
    var occupiedRegions: OccupancyBits
    var occupiedCells: OccupancyBits
    var placementsByRow: [CellPosition?]
    var foundSolutions: [[CellPosition]] = []

    var visitedNodes = 0
    var candidateChecks = 0
    var deadEnds = 0
    var maxDepth = 0
    var didExhaustBudget = false

    init(
        level: LevelDefinition,
        solutionLimit: Int,
        budget: PuzzleSolverBudget
    ) {
        self.level = level
        self.solutionLimit = solutionLimit
        self.budget = budget

        let regionIDs = Array(Set(level.regionIDs.flatMap { $0 })).sorted()
        self.regionIndexByID = Dictionary(
            uniqueKeysWithValues: regionIDs.enumerated().map { ($0.element, $0.offset) }
        )
        self.constraints = (0..<level.size).map(ConstraintKind.row)
            + (0..<level.size).map(ConstraintKind.column)
            + regionIDs.map(ConstraintKind.region)

        let positions = (0..<level.size).flatMap { row in
            (0..<level.size).map { column in
                CellPosition(row: row, column: column)
            }
        }
        var positionsByConstraint: [ConstraintKind: [CellPosition]] = [:]
        for position in positions {
            positionsByConstraint[.row(position.row), default: []].append(position)
            positionsByConstraint[.column(position.column), default: []].append(position)
            positionsByConstraint[
                .region(level.regionIDs[position.row][position.column]),
                default: []
            ].append(position)
        }
        self.positionsByConstraint = positionsByConstraint

        self.occupiedRows = OccupancyBits(count: level.size)
        self.occupiedColumns = OccupancyBits(count: level.size)
        self.occupiedRegions = OccupancyBits(count: regionIDs.count)
        self.occupiedCells = OccupancyBits(count: level.size * level.size)
        self.placementsByRow = Array(repeating: nil, count: level.size)
    }

    var result: ExactSearchResult {
        let solutionResult: PuzzleSolutionResult
        if foundSolutions.count >= 2 {
            solutionResult = .multiple
        } else if didExhaustBudget {
            solutionResult = .inconclusive
        } else if let solution = foundSolutions.first {
            solutionResult = .unique(solution)
        } else {
            solutionResult = .none
        }

        return ExactSearchResult(
            solutions: foundSolutions,
            report: PuzzleSolverReport(
                result: solutionResult,
                statistics: PuzzleSolverStatistics(
                    visitedNodes: visitedNodes,
                    candidateChecks: candidateChecks,
                    deadEnds: deadEnds,
                    maxDepth: maxDepth,
                    solutionsFound: foundSolutions.count,
                    didExhaustBudget: didExhaustBudget
                )
            )
        )
    }

    mutating func search(depth: Int) {
        guard foundSolutions.count < solutionLimit, !didExhaustBudget else {
            return
        }
        guard visitedNodes < budget.maxVisitedNodes else {
            didExhaustBudget = true
            return
        }

        visitedNodes += 1
        maxDepth = max(maxDepth, depth)

        if depth == level.catCount {
            foundSolutions.append(placementsByRow.compactMap { $0 })
            return
        }

        guard let choice = nextConstraintChoice() else {
            deadEnds += 1
            return
        }
        guard !choice.candidates.isEmpty else {
            deadEnds += 1
            return
        }

        for position in choice.candidates {
            place(position)
            search(depth: depth + 1)
            remove(position)

            if foundSolutions.count >= solutionLimit || didExhaustBudget {
                return
            }
        }
    }

    private mutating func nextConstraintChoice() -> ConstraintChoice? {
        var best: ConstraintChoice?

        for constraint in constraints where !isOccupied(constraint) {
            let candidates = legalCandidates(for: constraint)
            let choice = ConstraintChoice(candidates: candidates)
            if candidates.isEmpty {
                return choice
            }
            if best == nil || candidates.count < best!.candidates.count {
                best = choice
            }
        }

        return best
    }

    private mutating func legalCandidates(
        for constraint: ConstraintKind
    ) -> [CellPosition] {
        (positionsByConstraint[constraint] ?? []).filter { position in
            candidateChecks += 1
            return isLegal(position)
        }
    }

    private func isLegal(_ position: CellPosition) -> Bool {
        let regionID = level.regionIDs[position.row][position.column]
        guard let regionIndex = regionIndexByID[regionID] else { return false }
        return !occupiedRows.contains(position.row)
            && !occupiedColumns.contains(position.column)
            && !occupiedRegions.contains(regionIndex)
            && !hasAdjacentCat(to: position)
    }

    private func isOccupied(_ constraint: ConstraintKind) -> Bool {
        switch constraint {
        case let .row(row):
            return occupiedRows.contains(row)
        case let .column(column):
            return occupiedColumns.contains(column)
        case let .region(regionID):
            guard let index = regionIndexByID[regionID] else { return false }
            return occupiedRegions.contains(index)
        }
    }

    private func hasAdjacentCat(to position: CellPosition) -> Bool {
        let minimumRow = max(0, position.row - 1)
        let maximumRow = min(level.size - 1, position.row + 1)
        let minimumColumn = max(0, position.column - 1)
        let maximumColumn = min(level.size - 1, position.column + 1)

        for row in minimumRow...maximumRow {
            for column in minimumColumn...maximumColumn
            where occupiedCells.contains(row * level.size + column) {
                return true
            }
        }
        return false
    }

    private mutating func place(_ position: CellPosition) {
        let regionID = level.regionIDs[position.row][position.column]
        guard let regionIndex = regionIndexByID[regionID] else { return }
        occupiedRows.insert(position.row)
        occupiedColumns.insert(position.column)
        occupiedRegions.insert(regionIndex)
        occupiedCells.insert(position.row * level.size + position.column)
        placementsByRow[position.row] = position
    }

    private mutating func remove(_ position: CellPosition) {
        let regionID = level.regionIDs[position.row][position.column]
        guard let regionIndex = regionIndexByID[regionID] else { return }
        occupiedRows.remove(position.row)
        occupiedColumns.remove(position.column)
        occupiedRegions.remove(regionIndex)
        occupiedCells.remove(position.row * level.size + position.column)
        placementsByRow[position.row] = nil
    }
}

private struct ConstraintChoice {
    let candidates: [CellPosition]
}

private struct OccupancyBits {
    private var words: [UInt64]

    init(count: Int) {
        words = Array(repeating: 0, count: max(0, count + 63) / 64)
    }

    func contains(_ index: Int) -> Bool {
        guard index >= 0, index / 64 < words.count else { return false }
        return words[index / 64] & (UInt64(1) << UInt64(index % 64)) != 0
    }

    mutating func insert(_ index: Int) {
        guard index >= 0, index / 64 < words.count else { return }
        words[index / 64] |= UInt64(1) << UInt64(index % 64)
    }

    mutating func remove(_ index: Int) {
        guard index >= 0, index / 64 < words.count else { return }
        words[index / 64] &= ~(UInt64(1) << UInt64(index % 64))
    }
}
