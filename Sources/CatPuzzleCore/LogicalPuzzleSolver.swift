public enum LogicalPuzzleSolver {
    public static func solve(
        level: LevelDefinition,
        puzzle: Puzzle? = nil,
        mode: LogicalSolveMode = .logicOnly
    ) -> LogicalSolveResult {
        guard (try? LevelValidator.validate(level)) != nil,
              let startingPuzzle = puzzle ?? (try? level.makePuzzle()),
              startingPuzzle.matches(level) else {
            return .contradiction(emptyReport(for: level))
        }

        var engine = LogicalSolveEngine(level: level, puzzle: startingPuzzle)
        let outcome = engine.solve(maxAssumptionDepth: mode.assumptionDepth)
        return outcome.result(with: engine.report)
    }

    private static func emptyReport(for level: LevelDefinition) -> LogicalSolveReport {
        LogicalSolveReport(
            steps: [],
            assumptions: [],
            finalBoard: LogicalBoardSnapshot(size: max(0, level.size), states: []),
            statistics: LogicalSolveStatistics(
                placedCats: 0,
                exclusions: 0,
                propagationSteps: 0,
                deductionRounds: 0,
                assumptionCount: 0,
                maxAssumptionDepth: 0
            )
        )
    }
}

private enum LogicalOutcome: Equatable {
    case solved
    case stuck
    case contradiction

    func result(with report: LogicalSolveReport) -> LogicalSolveResult {
        switch self {
        case .solved:
            return .solved(report)
        case .stuck:
            return .stuck(report)
        case .contradiction:
            return .contradiction(report)
        }
    }
}

private struct LogicalSolveEngine {
    let level: LevelDefinition
    var board: CandidateBoard
    var steps: [LogicalStep] = []
    var assumptions: [LogicalAssumption] = []
    var placedCats = 0
    var exclusions = 0
    var propagationSteps = 0
    var deductionRounds = 0
    var assumptionCount = 0
    var reachedAssumptionDepth = 0

    init(level: LevelDefinition, puzzle: Puzzle) {
        self.level = level
        self.board = CandidateBoard(level: level, puzzle: puzzle)
    }

    var report: LogicalSolveReport {
        LogicalSolveReport(
            steps: steps,
            assumptions: assumptions,
            finalBoard: board.snapshot,
            statistics: LogicalSolveStatistics(
                placedCats: placedCats,
                exclusions: exclusions,
                propagationSteps: propagationSteps,
                deductionRounds: deductionRounds,
                assumptionCount: assumptionCount,
                maxAssumptionDepth: reachedAssumptionDepth
            )
        )
    }

    mutating func solve(maxAssumptionDepth: Int) -> LogicalOutcome {
        propagateInitialCats()
        return resolve(
            currentAssumptionDepth: 0,
            maxAssumptionDepth: maxAssumptionDepth
        )
    }

    private mutating func resolve(
        currentAssumptionDepth: Int,
        maxAssumptionDepth: Int
    ) -> LogicalOutcome {
        while true {
            if hasContradiction { return .contradiction }
            if isSolved { return .solved }

            if let deduction = nextDeduction() {
                deductionRounds += 1
                placeCat(at: deduction.position, reason: deduction.reason)
                continue
            }

            guard currentAssumptionDepth < maxAssumptionDepth else {
                return .stuck
            }

            var excludedByContradiction = false
            for position in board.sortedCandidates {
                let assumptionDepth = currentAssumptionDepth + 1
                reachedAssumptionDepth = max(
                    reachedAssumptionDepth,
                    assumptionDepth
                )

                let existingAssumptionCount = assumptionCount
                let existingRecordCount = assumptions.count
                var branch = self
                branch.forceAssumedCat(at: position)
                let branchOutcome = branch.resolve(
                    currentAssumptionDepth: assumptionDepth,
                    maxAssumptionDepth: maxAssumptionDepth
                )
                let nestedAssumptionCount =
                    branch.assumptionCount - existingAssumptionCount
                assumptionCount += 1 + nestedAssumptionCount
                reachedAssumptionDepth = max(
                    reachedAssumptionDepth,
                    branch.reachedAssumptionDepth
                )
                assumptions.append(
                    LogicalAssumption(
                        assumedCat: position,
                        depth: assumptionDepth,
                        outcome: branchOutcome.assumptionOutcome
                    )
                )
                assumptions.append(
                    contentsOf: branch.assumptions.dropFirst(existingRecordCount)
                )

                if branchOutcome == .contradiction {
                    exclude(
                        position,
                        reason: .contradictionFromAssumption(assumed: position)
                    )
                    excludedByContradiction = true
                    break
                }
            }

            if !excludedByContradiction { return .stuck }
        }
    }

    private mutating func propagateInitialCats() {
        for position in board.sortedConfirmedCats {
            propagateConstraints(from: position)
        }
    }

    private mutating func placeCat(
        at position: CellPosition,
        reason: LogicalReason
    ) {
        guard board.confirmCat(at: position) else { return }
        steps.append(LogicalStep(action: .placeCat(position), reason: reason))
        placedCats += 1
        propagateConstraints(from: position)
    }

    private mutating func forceAssumedCat(at position: CellPosition) {
        guard board.confirmCat(at: position) else { return }
        propagateConstraints(from: position)
    }

    private mutating func exclude(
        _ position: CellPosition,
        reason: LogicalReason
    ) {
        guard board.exclude(at: position) else { return }
        steps.append(LogicalStep(action: .exclude(position), reason: reason))
        exclusions += 1
    }

    private mutating func propagateConstraints(from cat: CellPosition) {
        var eventExcludedCount = 0
        let catColorID = level.colorIDs[cat.row][cat.column]

        for position in board.sortedCandidates {
            let reason: LogicalReason?
            if position.row == cat.row {
                reason = .rowAlreadyHasCat(row: cat.row)
            } else if position.column == cat.column {
                reason = .columnAlreadyHasCat(column: cat.column)
            } else if level.colorIDs[position.row][position.column] == catColorID {
                reason = .colorAlreadyHasCat(colorID: catColorID)
            } else if areAdjacent(position, cat) {
                reason = .adjacentToConfirmedCat(cat)
            } else {
                reason = nil
            }

            if let reason, board.exclude(at: position) {
                steps.append(
                    LogicalStep(action: .exclude(position), reason: reason)
                )
                exclusions += 1
                eventExcludedCount += 1
            }
        }

        if eventExcludedCount > 0 {
            propagationSteps += 1
        }
    }

    private func nextDeduction() -> Deduction? {
        for row in 0..<level.size where !board.hasCat(inRow: row) {
            let candidates = board.candidates(inRow: row)
            if candidates.count == 1 {
                return Deduction(
                    position: candidates[0],
                    reason: .onlyCandidateInRow(row: row)
                )
            }
        }

        for column in 0..<level.size where !board.hasCat(inColumn: column) {
            let candidates = board.candidates(inColumn: column)
            if candidates.count == 1 {
                return Deduction(
                    position: candidates[0],
                    reason: .onlyCandidateInColumn(column: column)
                )
            }
        }

        for colorID in board.colorIDs where !board.hasCat(forColor: colorID) {
            let candidates = board.candidates(forColor: colorID)
            if candidates.count == 1 {
                return Deduction(
                    position: candidates[0],
                    reason: .onlyCandidateForColor(colorID: colorID)
                )
            }
        }

        return nil
    }

    private var hasContradiction: Bool {
        guard board.confirmedCats.count <= level.catCount else { return true }

        let cats = board.sortedConfirmedCats
        for firstIndex in cats.indices {
            for secondIndex in cats.index(after: firstIndex)..<cats.endIndex {
                let first = cats[firstIndex]
                let second = cats[secondIndex]
                if first.row == second.row
                    || first.column == second.column
                    || level.colorIDs[first.row][first.column]
                        == level.colorIDs[second.row][second.column]
                    || areAdjacent(first, second) {
                    return true
                }
            }
        }

        for row in 0..<level.size
        where !board.hasCat(inRow: row) && board.candidates(inRow: row).isEmpty {
            return true
        }
        for column in 0..<level.size
        where !board.hasCat(inColumn: column)
            && board.candidates(inColumn: column).isEmpty {
            return true
        }
        for colorID in board.colorIDs
        where !board.hasCat(forColor: colorID)
            && board.candidates(forColor: colorID).isEmpty {
            return true
        }

        return false
    }

    private var isSolved: Bool {
        guard board.confirmedCats.count == level.catCount else { return false }
        return (0..<level.size).allSatisfy(board.hasCat(inRow:))
            && (0..<level.size).allSatisfy(board.hasCat(inColumn:))
            && board.colorIDs.allSatisfy(board.hasCat(forColor:))
            && !hasContradiction
    }

    private func areAdjacent(
        _ first: CellPosition,
        _ second: CellPosition
    ) -> Bool {
        abs(first.row - second.row) <= 1
            && abs(first.column - second.column) <= 1
    }
}

private extension LogicalOutcome {
    var assumptionOutcome: LogicalAssumptionOutcome {
        switch self {
        case .solved:
            return .solvedBranch
        case .stuck:
            return .inconclusive
        case .contradiction:
            return .contradiction
        }
    }
}

private struct Deduction {
    let position: CellPosition
    let reason: LogicalReason
}

private struct CandidateBoard {
    let size: Int
    let colorIDsByCell: [[Int]]
    var candidates: Set<CellPosition>
    var confirmedCats: Set<CellPosition>
    var excluded: Set<CellPosition>

    init(level: LevelDefinition, puzzle: Puzzle) {
        self.size = level.size
        self.colorIDsByCell = level.colorIDs
        self.candidates = []
        self.confirmedCats = []
        self.excluded = []

        for row in 0..<level.size {
            for column in 0..<level.size {
                let position = CellPosition(row: row, column: column)
                switch puzzle.state(atRow: row, column: column) {
                case .cat:
                    confirmedCats.insert(position)
                case .excluded:
                    excluded.insert(position)
                case .empty:
                    candidates.insert(position)
                case nil:
                    break
                }
            }
        }
    }

    var colorIDs: [Int] {
        Array(Set(colorIDsByCell.flatMap { $0 })).sorted()
    }

    var sortedCandidates: [CellPosition] {
        candidates.sorted(by: Self.rowMajor)
    }

    var sortedConfirmedCats: [CellPosition] {
        confirmedCats.sorted(by: Self.rowMajor)
    }

    var snapshot: LogicalBoardSnapshot {
        let states: [LogicalCellState] = (0..<size).flatMap { row in
            (0..<size).map { column in
                let position = CellPosition(row: row, column: column)
                if confirmedCats.contains(position) {
                    return LogicalCellState.confirmedCat
                }
                if excluded.contains(position) {
                    return LogicalCellState.excluded
                }
                return LogicalCellState.candidate
            }
        }
        return LogicalBoardSnapshot(size: size, states: states)
    }

    mutating func confirmCat(at position: CellPosition) -> Bool {
        guard candidates.remove(position) != nil else { return false }
        confirmedCats.insert(position)
        return true
    }

    mutating func exclude(at position: CellPosition) -> Bool {
        guard candidates.remove(position) != nil else { return false }
        excluded.insert(position)
        return true
    }

    func hasCat(inRow row: Int) -> Bool {
        confirmedCats.contains { $0.row == row }
    }

    func hasCat(inColumn column: Int) -> Bool {
        confirmedCats.contains { $0.column == column }
    }

    func hasCat(forColor colorID: Int) -> Bool {
        confirmedCats.contains {
            colorIDsByCell[$0.row][$0.column] == colorID
        }
    }

    func candidates(inRow row: Int) -> [CellPosition] {
        sortedCandidates.filter { $0.row == row }
    }

    func candidates(inColumn column: Int) -> [CellPosition] {
        sortedCandidates.filter { $0.column == column }
    }

    func candidates(forColor colorID: Int) -> [CellPosition] {
        sortedCandidates.filter {
            colorIDsByCell[$0.row][$0.column] == colorID
        }
    }

    private static func rowMajor(
        _ lhs: CellPosition,
        _ rhs: CellPosition
    ) -> Bool {
        lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
    }
}

private extension Puzzle {
    func matches(_ level: LevelDefinition) -> Bool {
        guard size == level.size, cells.count == level.size * level.size else {
            return false
        }
        return cells.allSatisfy {
            $0.colorID == level.colorIDs[$0.row][$0.column]
        }
    }
}
