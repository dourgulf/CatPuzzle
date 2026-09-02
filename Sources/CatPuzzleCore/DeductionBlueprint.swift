enum DeductionBlueprint {
    /// Minimum common attacks a Hard layout must force. Kept at the value the
    /// current Hard geometry can reliably reach; see the Hard branch below.
    static let hardCommonAttackFloor = 1

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
            // A locked pair is the mildest non-single technique. The count a
            // solvable layout needs scales with the board: an 8x8 dominant
            // background resolves with at most one, but a 9x9/10x10 background
            // spans so many rows and columns that pinning its single cat needs
            // a few pairs even though nothing harder is ever required. Cap the
            // allowance proportionally so large Easy boards stay generatable
            // while the profile stays gentle (no triple/common attack/strong
            // link/assumption below still holds).
            let maximumLockedPairs = easyLockedPairAllowance(size: report.finalBoard.size)
            if report.statistics.lockedPairCount > maximumLockedPairs {
                violations.append(
                    "Easy permits at most \(maximumLockedPairs) locked pair(s) at size \(report.finalBoard.size)."
                )
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
            // Density band: a common attack is the signature Hard technique in
            // the human sample, so require at least one rather than accepting a
            // strong-link-only layout. The human levels reach 3–9 common
            // attacks (level 242 has nine); the current dominant-background
            // Hard motif structurally tops out near one, so the floor stays at
            // one and `EvaluatedCandidate` ranking pursues higher density up to
            // whatever the geometry allows. Raising this floor toward the human
            // range needs a richer Hard region motif (a separate follow-up).
            if report.statistics.commonAttackCount < hardCommonAttackFloor {
                violations.append(
                    "Hard must force at least \(hardCommonAttackFloor) common attack."
                )
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

    /// Locked pairs an Easy layout may use, scaled with board size: one per
    /// board up to 8x8, then one more for each larger dimension (9 -> 2,
    /// 10 -> 3). Keeps small boards strictly single-driven while letting the
    /// larger dominant-background cascade resolve its big Region.
    static func easyLockedPairAllowance(size: Int) -> Int {
        max(1, size - 7)
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
