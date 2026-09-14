public struct LogicalHint: Equatable, Sendable {
    public let actions: [LogicalAction]
    public let reason: LogicalReason

    public init(actions: [LogicalAction], reason: LogicalReason) {
        self.actions = actions
        self.reason = reason
    }

    public var positions: [CellPosition] {
        actions.map { action in
            switch action {
            case let .placeCat(position), let .exclude(position):
                position
            }
        }
    }
}

/// Why a board can no longer be finished — always the player's own doing,
/// since every level ships with a unique solution.
public enum LogicalHintDiagnosis: Equatable, Sendable {
    /// This row/column/Region has no cat and no cell left to put one in:
    /// one of the player's exclusions must be wrong.
    case starvedConstraint(ConstraintKind)
    /// Two placed cats cannot coexist.
    case clashingCats(CellPosition, CellPosition)
}

/// What the hint button can offer for the player's current board.
public enum LogicalHintOutcome: Equatable, Sendable {
    /// A next step to preview and apply.
    case hint(LogicalHint)
    /// The board is already broken; nothing can be deduced until it is fixed.
    case contradiction(LogicalHintDiagnosis)
    /// The board is consistent but even a depth-1 trial finds no next step.
    case unavailable

    /// The step to preview, when this outcome carries one.
    public var hint: LogicalHint? {
        if case let .hint(hint) = self { return hint }
        return nil
    }
}

/// Produces one deterministic deduction from the player's current board.
/// This module deliberately has no fixture or known-solution input.
public enum LogicalHintEngine {
    /// Hints are ranked by how easy they are to see, not by the solver's
    /// internal scan order, because hints are a limited resource: the one
    /// the player gets should be the one they could most plausibly have
    /// found themselves. Only when no deterministic technique applies does
    /// this fall back to a depth-1 proof by contradiction.
    public static func nextHint(
        level: LevelDefinition,
        puzzle: Puzzle
    ) -> LogicalHintOutcome {
        if let diagnosis = LogicalPuzzleSolver.diagnoseContradiction(
            level: level,
            puzzle: puzzle
        ) {
            return .contradiction(diagnosis)
        }
        if let hint = LogicalPuzzleSolver.easiestHint(level: level, puzzle: puzzle) {
            return .hint(hint)
        }
        if let hint = LogicalPuzzleSolver.assumptionHint(level: level, puzzle: puzzle) {
            return .hint(hint)
        }
        return .unavailable
    }
}
