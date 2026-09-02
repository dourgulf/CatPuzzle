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

/// Ordered (source family, target family) pairs scanned by locked-set
/// deduction. Both directions of each of the three unordered family pairs
/// (Row/Column, Row/Region, Column/Region) are covered, and the order is
/// fixed so repeated solves are deterministic.
private let lockedSetFamilyPairs: [(ConstraintFamily, ConstraintFamily)] = [
    (.row, .column),
    (.column, .row),
    (.row, .region),
    (.region, .row),
    (.column, .region),
    (.region, .column),
]

/// Largest locked set (Hall set) the solver will search for. Sizes 2 and 3
/// (locked pair/triple) run at their historical priority; sizes 4...this cap
/// run only as a last resort before an assumption (see
/// `nextHigherOrderLockedSetDeduction`). Large boards such as Level 258 need a
/// single size-4 step, which this turns from a trial into pure logic.
private let maxLockedSetSize = 4

private enum AdvancedDeductionKind {
    case lockedPair
    case lockedTriple
    case higherOrderLockedSet(size: Int)
    case commonAttack
    case strongLink
}

private struct AdvancedDeductionEvent {
    let reason: LogicalReason
    let exclusions: [CellPosition]
    let kind: AdvancedDeductionKind
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
    var events: [LogicalTechniqueEvent] = []
    var assumptions: [LogicalAssumption] = []
    var placedCats = 0
    var exclusions = 0
    var propagationSteps = 0
    var deductionRounds = 0
    var assumptionCount = 0
    var reachedAssumptionDepth = 0
    var lockedPairCount = 0
    var lockedTripleCount = 0
    var higherOrderLockedSetCount = 0
    var commonAttackCount = 0
    var strongLinkDeductionCount = 0

    init(level: LevelDefinition, puzzle: Puzzle) {
        self.level = level
        self.board = CandidateBoard(level: level, puzzle: puzzle)
    }

    var report: LogicalSolveReport {
        LogicalSolveReport(
            steps: steps,
            events: events,
            assumptions: assumptions,
            finalBoard: board.snapshot,
            statistics: LogicalSolveStatistics(
                placedCats: placedCats,
                exclusions: exclusions,
                propagationSteps: propagationSteps,
                deductionRounds: deductionRounds,
                assumptionCount: assumptionCount,
                maxAssumptionDepth: reachedAssumptionDepth,
                lockedPairCount: lockedPairCount,
                lockedTripleCount: lockedTripleCount,
                higherOrderLockedSetCount: higherOrderLockedSetCount,
                commonAttackCount: commonAttackCount,
                strongLinkDeductionCount: strongLinkDeductionCount
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

            if let event = nextAdvancedDeduction() {
                apply(event)
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
                    let eventStart = steps.count
                    if exclude(
                        position,
                        reason: .contradictionFromAssumption(assumed: position)
                    ) {
                        recordEvent(
                            .contradictionElimination(assumed: position),
                            startingAt: eventStart
                        )
                        excludedByContradiction = true
                        break
                    }
                }
            }

            if !excludedByContradiction { return .stuck }
        }
    }

    private mutating func propagateInitialCats() {
        for position in board.sortedConfirmedCats {
            let eventStart = steps.count
            propagateConstraints(from: position)
            recordEvent(
                .propagation(confirmedCat: position),
                startingAt: eventStart
            )
        }
    }

    private mutating func placeCat(
        at position: CellPosition,
        reason: LogicalReason
    ) {
        let eventStart = steps.count
        guard board.confirmCat(at: position) else { return }
        steps.append(LogicalStep(action: .placeCat(position), reason: reason))
        placedCats += 1
        propagateConstraints(from: position)
        guard let technique = singleTechnique(for: reason) else { return }
        recordEvent(technique, startingAt: eventStart)
    }

    private mutating func forceAssumedCat(at position: CellPosition) {
        guard board.confirmCat(at: position) else { return }
        propagateConstraints(from: position)
    }

    @discardableResult
    private mutating func exclude(
        _ position: CellPosition,
        reason: LogicalReason
    ) -> Bool {
        guard board.exclude(at: position) else { return false }
        steps.append(LogicalStep(action: .exclude(position), reason: reason))
        exclusions += 1
        return true
    }

    private mutating func propagateConstraints(from cat: CellPosition) {
        var eventExcludedCount = 0
        let catRegionID = level.regionIDs[cat.row][cat.column]

        for position in board.sortedCandidates {
            let reason: LogicalReason?
            if position.row == cat.row {
                reason = .rowAlreadyHasCat(row: cat.row)
            } else if position.column == cat.column {
                reason = .columnAlreadyHasCat(column: cat.column)
            } else if level.regionIDs[position.row][position.column] == catRegionID {
                reason = .regionAlreadyHasCat(regionID: catRegionID)
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

        for regionID in board.regionIDs where !board.hasCat(forRegion: regionID) {
            let candidates = board.candidates(forRegion: regionID)
            if candidates.count == 1 {
                return Deduction(
                    position: candidates[0],
                    reason: .onlyCandidateForRegion(regionID: regionID)
                )
            }
        }

        return nil
    }

    /// Applies a batch exclusion event: records one `LogicalStep` per
    /// excluded position (all sharing the same explanatory reason) and
    /// bumps the matching advanced-technique counter, but only if the
    /// event actually removed at least one candidate — a no-op deduction
    /// is not counted or recorded (see item XXI of the design brief).
    private mutating func apply(_ event: AdvancedDeductionEvent) {
        let eventStart = steps.count
        var appliedAny = false
        for position in event.exclusions where board.exclude(at: position) {
            steps.append(LogicalStep(action: .exclude(position), reason: event.reason))
            exclusions += 1
            appliedAny = true
        }
        guard appliedAny else { return }

        switch event.kind {
        case .lockedPair:
            lockedPairCount += 1
            recordEvent(.lockedSet(size: 2), startingAt: eventStart)
        case .lockedTriple:
            lockedTripleCount += 1
            recordEvent(.lockedSet(size: 3), startingAt: eventStart)
        case let .higherOrderLockedSet(size):
            higherOrderLockedSetCount += 1
            recordEvent(.lockedSet(size: size), startingAt: eventStart)
        case .commonAttack:
            commonAttackCount += 1
            recordEvent(.commonAttack, startingAt: eventStart)
        case .strongLink:
            strongLinkDeductionCount += 1
            recordEvent(.strongLink, startingAt: eventStart)
        }
    }

    private func singleTechnique(for reason: LogicalReason) -> LogicalTechnique? {
        switch reason {
        case let .onlyCandidateInRow(row):
            return .single(.row(row))
        case let .onlyCandidateInColumn(column):
            return .single(.column(column))
        case let .onlyCandidateForRegion(regionID):
            return .single(.region(regionID))
        default:
            return nil
        }
    }

    private mutating func recordEvent(
        _ technique: LogicalTechnique,
        startingAt stepIndex: Int
    ) {
        guard stepIndex < steps.count else { return }
        events.append(
            LogicalTechniqueEvent(
                technique: technique,
                steps: Array(steps[stepIndex...]),
                boardAfter: board.snapshot
            )
        )
    }

    /// Scans, in a fixed deterministic order, for the next advanced
    /// deduction: locked pairs, then locked triples, then common attack,
    /// then strong-link common elimination (see item XVI priority order).
    private func nextAdvancedDeduction() -> AdvancedDeductionEvent? {
        if let event = nextLockedSetDeduction() { return event }
        if let event = nextCommonAttackDeduction() { return event }
        if let event = nextStrongLinkDeduction() { return event }
        if let event = nextHigherOrderLockedSetDeduction() { return event }
        return nil
    }

    private func nextLockedSetDeduction() -> AdvancedDeductionEvent? {
        lockedSetDeduction(sizes: [2, 3])
    }

    /// Locked sets of size 4 and up. Deliberately scanned last — after common
    /// attack and strong link — so every board that already solved with the
    /// pair/triple/attack/link set keeps its exact deduction sequence and
    /// statistics; a size-4 set only ever fires where the solver would
    /// otherwise have had to open an assumption branch.
    private func nextHigherOrderLockedSetDeduction() -> AdvancedDeductionEvent? {
        guard maxLockedSetSize >= 4 else { return nil }
        return lockedSetDeduction(sizes: Array(4...maxLockedSetSize))
    }

    private func lockedSetDeduction(sizes: [Int]) -> AdvancedDeductionEvent? {
        for size in sizes {
            for (sourceFamily, targetFamily) in lockedSetFamilyPairs {
                if let event = lockedSetDeduction(
                    sourceFamily: sourceFamily,
                    targetFamily: targetFamily,
                    size: size
                ) {
                    return event
                }
            }
        }
        return nil
    }

    /// Generalized locked set (Hall set): if `size` constraints from
    /// `sourceFamily` have candidates confined entirely within exactly
    /// `size` constraints of `targetFamily`, those target constraints
    /// must be filled by the source constraints' cats — so any other
    /// candidate in those target constraints can be excluded.
    private func lockedSetDeduction(
        sourceFamily: ConstraintFamily,
        targetFamily: ConstraintFamily,
        size: Int
    ) -> AdvancedDeductionEvent? {
        let sources = board.unresolvedConstraints(for: sourceFamily)
        guard sources.count >= size else { return nil }

        for combo in Self.combinations(sources, size) {
            let unionPositions = Set(combo.flatMap(\.candidates))
            let targetKinds = Set(
                unionPositions.map { board.constraintKind(for: $0, family: targetFamily) }
            )
            guard targetKinds.count == size else { continue }

            let sortedTargets = targetKinds.sorted()
            var affected: [CellPosition] = []
            for targetKind in sortedTargets {
                for position in board.candidates(for: targetKind)
                where !unionPositions.contains(position) {
                    affected.append(position)
                }
            }
            guard !affected.isEmpty else { continue }

            return AdvancedDeductionEvent(
                reason: .lockedSet(
                    sources: combo.map(\.kind).sorted(),
                    targets: sortedTargets
                ),
                exclusions: affected.sorted(by: CandidateBoard.rowMajor),
                kind: lockedSetKind(for: size)
            )
        }
        return nil
    }

    private func lockedSetKind(for size: Int) -> AdvancedDeductionKind {
        switch size {
        case 2: return .lockedPair
        case 3: return .lockedTriple
        default: return .higherOrderLockedSet(size: size)
        }
    }

    /// Common attack: an unresolved constraint's eventual cat must land on
    /// one of its 3+ remaining candidates. Any other candidate conflicting
    /// with every one of them can never be a cat. (The 2-candidate case is
    /// handled separately as a strong link — see `nextStrongLinkDeduction`.)
    private func nextCommonAttackDeduction() -> AdvancedDeductionEvent? {
        for family in ConstraintFamily.allCases {
            for constraint in board.unresolvedConstraints(for: family)
            where constraint.candidates.count >= 3 {
                for candidate in board.sortedCandidates
                where !constraint.candidates.contains(candidate)
                    && constraint.candidates.allSatisfy({ board.conflicts(candidate, $0) }) {
                    return AdvancedDeductionEvent(
                        reason: .commonAttack(
                            constraint: constraint.kind,
                            candidatePositions: constraint.candidates
                        ),
                        exclusions: [candidate],
                        kind: .commonAttack
                    )
                }
            }
        }
        return nil
    }

    /// Strong-link common elimination: when a constraint has exactly two
    /// remaining candidates, exactly one of them must be the cat. Any
    /// other candidate that conflicts with both can never be a cat.
    private func nextStrongLinkDeduction() -> AdvancedDeductionEvent? {
        for family in ConstraintFamily.allCases {
            for constraint in board.unresolvedConstraints(for: family)
            where constraint.candidates.count == 2 {
                let link = StrongLink(
                    constraint: constraint.kind,
                    first: constraint.candidates[0],
                    second: constraint.candidates[1]
                )
                for candidate in board.sortedCandidates
                where candidate != link.first
                    && candidate != link.second
                    && board.conflicts(candidate, link.first)
                    && board.conflicts(candidate, link.second) {
                    return AdvancedDeductionEvent(
                        reason: .strongLinkCommonElimination(link: link),
                        exclusions: [candidate],
                        kind: .strongLink
                    )
                }
            }
        }
        return nil
    }

    /// Deterministic combinations of `items` taken `k` at a time, in the
    /// order induced by `items`'s own order (which callers keep canonical).
    private static func combinations<T>(_ items: [T], _ k: Int) -> [[T]] {
        guard k > 0, k <= items.count else { return [] }
        var result: [[T]] = []
        var current: [T] = []
        func combine(_ start: Int) {
            if current.count == k {
                result.append(current)
                return
            }
            guard start < items.count else { return }
            for index in start..<items.count {
                current.append(items[index])
                combine(index + 1)
                current.removeLast()
            }
        }
        combine(0)
        return result
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
                    || level.regionIDs[first.row][first.column]
                        == level.regionIDs[second.row][second.column]
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
        for regionID in board.regionIDs
        where !board.hasCat(forRegion: regionID)
            && board.candidates(forRegion: regionID).isEmpty {
            return true
        }

        return false
    }

    private var isSolved: Bool {
        guard board.confirmedCats.count == level.catCount else { return false }
        return (0..<level.size).allSatisfy(board.hasCat(inRow:))
            && (0..<level.size).allSatisfy(board.hasCat(inColumn:))
            && board.regionIDs.allSatisfy(board.hasCat(forRegion:))
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
    let regionIDsByCell: [[Int]]
    var candidates: Set<CellPosition>
    var confirmedCats: Set<CellPosition>
    var excluded: Set<CellPosition>

    init(level: LevelDefinition, puzzle: Puzzle) {
        self.size = level.size
        self.regionIDsByCell = level.regionIDs
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

    var regionIDs: [Int] {
        Array(Set(regionIDsByCell.flatMap { $0 })).sorted()
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

    func hasCat(forRegion regionID: Int) -> Bool {
        confirmedCats.contains {
            regionIDsByCell[$0.row][$0.column] == regionID
        }
    }

    func candidates(inRow row: Int) -> [CellPosition] {
        sortedCandidates.filter { $0.row == row }
    }

    func candidates(inColumn column: Int) -> [CellPosition] {
        sortedCandidates.filter { $0.column == column }
    }

    func candidates(forRegion regionID: Int) -> [CellPosition] {
        sortedCandidates.filter {
            regionIDsByCell[$0.row][$0.column] == regionID
        }
    }

    func constraintKind(for position: CellPosition, family: ConstraintFamily) -> ConstraintKind {
        switch family {
        case .row:
            return .row(position.row)
        case .column:
            return .column(position.column)
        case .region:
            return .region(regionIDsByCell[position.row][position.column])
        }
    }

    func allConstraintKinds(for family: ConstraintFamily) -> [ConstraintKind] {
        switch family {
        case .row:
            return (0..<size).map { .row($0) }
        case .column:
            return (0..<size).map { .column($0) }
        case .region:
            return regionIDs.map { .region($0) }
        }
    }

    func hasCat(for kind: ConstraintKind) -> Bool {
        switch kind {
        case let .row(row):
            return hasCat(inRow: row)
        case let .column(column):
            return hasCat(inColumn: column)
        case let .region(regionID):
            return hasCat(forRegion: regionID)
        }
    }

    func candidates(for kind: ConstraintKind) -> [CellPosition] {
        switch kind {
        case let .row(row):
            return candidates(inRow: row)
        case let .column(column):
            return candidates(inColumn: column)
        case let .region(regionID):
            return candidates(forRegion: regionID)
        }
    }

    /// All constraints of `family` that do not yet have a confirmed cat,
    /// in canonical (index-ascending) order.
    func unresolvedConstraints(for family: ConstraintFamily) -> [ExactlyOneConstraint] {
        allConstraintKinds(for: family)
            .filter { !hasCat(for: $0) }
            .map { ExactlyOneConstraint(kind: $0, candidates: candidates(for: $0)) }
    }

    /// Whether two distinct positions can never both be cats: same row,
    /// same column, same Region, or 8-neighborhood adjacent.
    func conflicts(_ first: CellPosition, _ second: CellPosition) -> Bool {
        guard first != second else { return false }
        if first.row == second.row || first.column == second.column {
            return true
        }
        if regionIDsByCell[first.row][first.column] == regionIDsByCell[second.row][second.column] {
            return true
        }
        return abs(first.row - second.row) <= 1 && abs(first.column - second.column) <= 1
    }

    static func rowMajor(
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
            $0.regionID == level.regionIDs[$0.row][$0.column]
        }
    }
}
