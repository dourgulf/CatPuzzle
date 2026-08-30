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

/// Produces one deterministic deduction from the player's current board.
/// This module deliberately has no fixture or known-solution input.
public enum LogicalHintEngine {
    public static func nextHint(
        level: LevelDefinition,
        puzzle: Puzzle
    ) -> LogicalHint? {
        let result = LogicalPuzzleSolver.solve(
            level: level,
            puzzle: puzzle,
            mode: .logicOnly
        )
        if case .contradiction = result {
            return nil
        }
        return firstHint(in: result.report.events)
    }

    private static func firstHint(
        in events: [LogicalTechniqueEvent]
    ) -> LogicalHint? {
        for event in events {
            if let placement = event.steps.first(where: { step in
                if case .placeCat = step.action { return true }
                return false
            }) {
                return LogicalHint(
                    actions: [placement.action],
                    reason: placement.reason
                )
            }

            guard let firstExclusion = event.steps.first(where: { step in
                if case .exclude = step.action { return true }
                return false
            }) else {
                continue
            }
            let actions = event.steps.compactMap { step -> LogicalAction? in
                guard step.reason == firstExclusion.reason,
                      case .exclude = step.action else {
                    return nil
                }
                return step.action
            }
            if !actions.isEmpty {
                return LogicalHint(
                    actions: actions,
                    reason: firstExclusion.reason
                )
            }
        }
        return nil
    }
}
