public enum DifficultyTier: Equatable, Sendable {
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
    public static func analyze(_ report: LogicalSolveReport) -> PuzzleDifficulty {
        let statistics = report.statistics
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

        let score = statistics.placedCats
            + statistics.exclusions / 10
            + statistics.deductionRounds * 2
            + statistics.propagationSteps
            + singleWeight
            + statistics.assumptionCount * 20
            + assumptionDepthWeight(statistics.maxAssumptionDepth)

        let tier: DifficultyTier
        if statistics.assumptionCount > 0 {
            tier = .challenge
        } else {
            switch score {
            case ...12:
                tier = .beginner
            case ...22:
                tier = .easy
            case ...35:
                tier = .medium
            case ...50:
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
