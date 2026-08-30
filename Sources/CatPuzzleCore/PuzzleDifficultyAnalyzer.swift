public enum DifficultyTier: Equatable, Hashable, Sendable, CaseIterable {
    case beginner
    case easy
    case medium
    case hard
    case expert
    case challenge
}

public struct PuzzleDifficulty: Equatable, Sendable {
    public let score: Int
    public let tier: DifficultyTier

    public init(score: Int, tier: DifficultyTier) {
        self.score = score
        self.tier = tier
    }
}

public enum PuzzleDifficultyAnalyzer {
    /// `placedCats` and `deductionRounds` are always exactly `size` for any
    /// fully mainline-solved report (one deduction round places exactly one
    /// cat), so their contribution to a raw, un-normalized score grows
    /// linearly with board size even for the logically simplest possible
    /// solve path. Left unchecked, that baseline alone pushes every puzzle
    /// past "beginner"/"easy" once the board is bigger than a handful of
    /// rows — confirmed empirically: the hand-verified 6x6 `BuiltInLevels`
    /// score `medium`/`medium`/`hard` even though they're meant to be the
    /// gentlest levels in the game. `structuralScore` divides that
    /// per-cell/per-round baseline by `size` so it stays roughly constant
    /// per solved puzzle regardless of board size, while `techniqueScore`
    /// (locked sets, common attacks, strong links) and `assumptionScore`
    /// stay absolute — one locked pair is the same reasoning leap whether
    /// the board is 6x6 or 10x10.
    public static func analyze(_ report: LogicalSolveReport) -> PuzzleDifficulty {
        let statistics = report.statistics
        let size = max(1, report.finalBoard.size)
        let singleWeight = report.steps.reduce(into: 0) { score, step in
            switch step.reason {
            case .onlyCandidateInRow, .onlyCandidateInColumn:
                score += 1
            case .onlyCandidateForColor:
                score += 2
            default:
                break
            }
        }

        let structuralScore = statistics.placedCats
            + statistics.exclusions / 10
            + statistics.deductionRounds * 2
            + statistics.propagationSteps
            + singleWeight
        let normalizedStructuralScore = Int((Double(structuralScore) / Double(size)).rounded())

        let techniqueScore = statistics.lockedPairCount * 4
            + statistics.lockedTripleCount * 7
            + statistics.commonAttackCount * 5
            + statistics.strongLinkDeductionCount * 8

        let assumptionScore = statistics.assumptionCount * 20
            + assumptionDepthWeight(statistics.maxAssumptionDepth)

        let score = normalizedStructuralScore + techniqueScore + assumptionScore

        let tier: DifficultyTier
        if statistics.assumptionCount > 0 {
            tier = .challenge
        } else {
            switch score {
            case ...4:
                tier = .beginner
            case ...9:
                tier = .easy
            case ...16:
                tier = .medium
            case ...26:
                tier = .hard
            default:
                tier = .expert
            }
        }

        return PuzzleDifficulty(score: score, tier: tier)
    }

    private static func assumptionDepthWeight(_ depth: Int) -> Int {
        switch depth {
        case ...0:
            return 0
        case 1:
            return 20
        default:
            return 60 + (depth - 2) * 40
        }
    }
}
