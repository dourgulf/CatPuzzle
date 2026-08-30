enum DeductionBlueprint {
    static func evaluate(
        difficulty: GeneratorDifficulty,
        result: LogicalSolveResult
    ) -> BlueprintCoverage {
        let report = result.report
        let events = report.events
        let solvedWithoutAssumptions = result.isSolved
            && report.statistics.assumptionCount == 0
        var violations: [String] = []

        guard solvedWithoutAssumptions else {
            return BlueprintCoverage(
                achievedStages: achievedPrefix(difficulty: difficulty, events: events),
                requiredStages: requiredStageCount(difficulty),
                isSatisfied: false,
                violations: ["The candidate is not solved by deterministic logic only."]
            )
        }

        switch difficulty {
        case .easy:
            if events.first.map(isRegionSingle) != true {
                violations.append("Easy must open with a Region single.")
            }
            if report.statistics.lockedPairCount > 1 {
                violations.append("Easy permits at most one locked pair.")
            }
            if report.statistics.lockedTripleCount > 0
                || report.statistics.commonAttackCount > 0
                || report.statistics.strongLinkDeductionCount > 0 {
                violations.append("Easy used a forbidden advanced technique.")
            }

        case .medium:
            if events.first.map(isLockedSet) != true {
                violations.append("Medium must open with a locked pair or triple.")
            }
            if report.statistics.commonAttackCount > 0
                || report.statistics.strongLinkDeductionCount > 0 {
                violations.append("Medium used a Hard-only technique.")
            }
            if !hasTechniqueAfterPlacement(events, matching: isSingle) {
                violations.append("Medium needs a second deduction stage after a cat placement.")
            }

        case .hard:
            if events.first.map(isLockedSet) != true {
                violations.append("Hard must open with a locked set.")
            }
            if !hasTechniqueAfterPlacement(events, matching: isHardTechnique) {
                violations.append("Hard needs a later common attack or strong-link deduction.")
            }
        }

        return BlueprintCoverage(
            achievedStages: achievedPrefix(difficulty: difficulty, events: events),
            requiredStages: requiredStageCount(difficulty),
            isSatisfied: violations.isEmpty,
            violations: violations
        )
    }

    private static func achievedPrefix(
        difficulty: GeneratorDifficulty,
        events: [LogicalTechniqueEvent]
    ) -> Int {
        switch difficulty {
        case .easy:
            return events.first.map(isRegionSingle) == true ? 2 : 0
        case .medium:
            guard events.first.map(isLockedSet) == true else { return 0 }
            guard events.contains(where: isSingle) else { return 1 }
            return hasTechniqueAfterPlacement(events, matching: isSingle) ? 3 : 2
        case .hard:
            guard events.first.map(isLockedSet) == true else { return 0 }
            guard events.contains(where: isSingle) else { return 1 }
            return hasTechniqueAfterPlacement(events, matching: isHardTechnique) ? 3 : 2
        }
    }

    private static func requiredStageCount(_ difficulty: GeneratorDifficulty) -> Int {
        difficulty == .easy ? 2 : 3
    }

    private static func hasTechniqueAfterPlacement(
        _ events: [LogicalTechniqueEvent],
        matching predicate: (LogicalTechniqueEvent) -> Bool
    ) -> Bool {
        guard let placementIndex = events.firstIndex(where: isSingle) else {
            return false
        }
        return events.dropFirst(placementIndex + 1).contains(where: predicate)
    }

    private static func isRegionSingle(_ event: LogicalTechniqueEvent) -> Bool {
        if case .single(.region) = event.technique { return true }
        return false
    }

    private static func isSingle(_ event: LogicalTechniqueEvent) -> Bool {
        if case .single = event.technique { return true }
        return false
    }

    private static func isLockedSet(_ event: LogicalTechniqueEvent) -> Bool {
        if case .lockedSet = event.technique { return true }
        return false
    }

    private static func isHardTechnique(_ event: LogicalTechniqueEvent) -> Bool {
        switch event.technique {
        case .commonAttack, .strongLink:
            return true
        default:
            return false
        }
    }
}
