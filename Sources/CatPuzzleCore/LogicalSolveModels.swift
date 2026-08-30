public enum LogicalCellState: Equatable, Sendable {
    case candidate
    case excluded
    case confirmedCat
}

public struct LogicalBoardSnapshot: Equatable, Sendable {
    public let size: Int
    public let states: [LogicalCellState]

    public init(size: Int, states: [LogicalCellState]) {
        self.size = size
        self.states = states
    }

    public func state(atRow row: Int, column: Int) -> LogicalCellState? {
        guard (0..<size).contains(row), (0..<size).contains(column) else {
            return nil
        }
        let index = row * size + column
        guard states.indices.contains(index) else { return nil }
        return states[index]
    }
}

public enum LogicalAction: Equatable, Sendable {
    case placeCat(CellPosition)
    case exclude(CellPosition)
}

public enum LogicalReason: Equatable, Sendable {
    case onlyCandidateInRow(row: Int)
    case onlyCandidateInColumn(column: Int)
    case onlyCandidateForRegion(regionID: Int)
    case rowAlreadyHasCat(row: Int)
    case columnAlreadyHasCat(column: Int)
    case regionAlreadyHasCat(regionID: Int)
    case adjacentToConfirmedCat(CellPosition)
    case contradictionFromAssumption(assumed: CellPosition)

    /// A generalized locked set (Hall set): the candidates of `sources`
    /// fall entirely within `targets` (|sources| == |targets|), so any
    /// candidate in `targets` that is not also a candidate of `sources`
    /// can be excluded. `sources.count` distinguishes pair (2) vs triple (3).
    case lockedSet(sources: [ConstraintKind], targets: [ConstraintKind])

    /// `constraint` must eventually place its cat at one of
    /// `candidatePositions`; the excluded position conflicts with every
    /// one of them, so it can never be a cat.
    case commonAttack(constraint: ConstraintKind, candidatePositions: [CellPosition])

    /// `link` has exactly two candidates and exactly one of them must be
    /// a cat; the excluded position conflicts with both, so it can never
    /// be a cat.
    case strongLinkCommonElimination(link: StrongLink)
}

public struct LogicalStep: Equatable, Sendable {
    public let action: LogicalAction
    public let reason: LogicalReason

    public init(action: LogicalAction, reason: LogicalReason) {
        self.action = action
        self.reason = reason
    }
}

/// A solver-level technique category independent of difficulty presets or
/// generator blueprints. Detailed constraints and positions remain in the
/// event's `steps`, so consumers can interpret the same trace differently.
public enum LogicalTechnique: Equatable, Sendable {
    case single(ConstraintKind)
    case propagation(confirmedCat: CellPosition)
    case lockedSet(size: Int)
    case commonAttack
    case strongLink
    case contradictionElimination(assumed: CellPosition)
}

/// One atomic logical event and the candidate board immediately after it.
/// A placement event includes the direct propagation caused by that cat;
/// advanced deductions group all exclusions sharing the same reason.
public struct LogicalTechniqueEvent: Equatable, Sendable {
    public let technique: LogicalTechnique
    public let steps: [LogicalStep]
    public let boardAfter: LogicalBoardSnapshot

    public init(
        technique: LogicalTechnique,
        steps: [LogicalStep],
        boardAfter: LogicalBoardSnapshot
    ) {
        self.technique = technique
        self.steps = steps
        self.boardAfter = boardAfter
    }
}

public enum LogicalAssumptionOutcome: Equatable, Sendable {
    case contradiction
    case solvedBranch
    case inconclusive
}

public struct LogicalAssumption: Equatable, Sendable {
    public let assumedCat: CellPosition
    public let depth: Int
    public let outcome: LogicalAssumptionOutcome

    public init(
        assumedCat: CellPosition,
        depth: Int,
        outcome: LogicalAssumptionOutcome
    ) {
        self.assumedCat = assumedCat
        self.depth = depth
        self.outcome = outcome
    }
}

public struct LogicalSolveStatistics: Equatable, Sendable {
    public let placedCats: Int
    public let exclusions: Int
    public let propagationSteps: Int
    public let deductionRounds: Int
    public let assumptionCount: Int
    public let maxAssumptionDepth: Int
    public let lockedPairCount: Int
    public let lockedTripleCount: Int
    public let commonAttackCount: Int
    public let strongLinkDeductionCount: Int

    public init(
        placedCats: Int,
        exclusions: Int,
        propagationSteps: Int,
        deductionRounds: Int,
        assumptionCount: Int,
        maxAssumptionDepth: Int,
        lockedPairCount: Int = 0,
        lockedTripleCount: Int = 0,
        commonAttackCount: Int = 0,
        strongLinkDeductionCount: Int = 0
    ) {
        self.placedCats = placedCats
        self.exclusions = exclusions
        self.propagationSteps = propagationSteps
        self.deductionRounds = deductionRounds
        self.assumptionCount = assumptionCount
        self.maxAssumptionDepth = maxAssumptionDepth
        self.lockedPairCount = lockedPairCount
        self.lockedTripleCount = lockedTripleCount
        self.commonAttackCount = commonAttackCount
        self.strongLinkDeductionCount = strongLinkDeductionCount
    }
}

public struct LogicalSolveReport: Equatable, Sendable {
    public let steps: [LogicalStep]
    public let events: [LogicalTechniqueEvent]
    public let assumptions: [LogicalAssumption]
    public let finalBoard: LogicalBoardSnapshot
    public let statistics: LogicalSolveStatistics

    public init(
        steps: [LogicalStep],
        events: [LogicalTechniqueEvent] = [],
        assumptions: [LogicalAssumption] = [],
        finalBoard: LogicalBoardSnapshot,
        statistics: LogicalSolveStatistics
    ) {
        self.steps = steps
        self.events = events
        self.assumptions = assumptions
        self.finalBoard = finalBoard
        self.statistics = statistics
    }
}

public enum LogicalSolveResult: Equatable, Sendable {
    case solved(LogicalSolveReport)
    case stuck(LogicalSolveReport)
    case contradiction(LogicalSolveReport)

    public var report: LogicalSolveReport {
        switch self {
        case let .solved(report), let .stuck(report), let .contradiction(report):
            return report
        }
    }

    public var isSolved: Bool {
        if case .solved = self { return true }
        return false
    }
}

public enum LogicalSolveMode: Equatable, Sendable {
    case logicOnly
    case challenge(maxAssumptionDepth: Int)

    var assumptionDepth: Int {
        switch self {
        case .logicOnly:
            return 0
        case let .challenge(maxAssumptionDepth):
            return max(0, maxAssumptionDepth)
        }
    }
}
