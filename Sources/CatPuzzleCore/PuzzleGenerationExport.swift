/// Codable JSON schema for the generator CLI/dev-tool output. This is a
/// research-tool format (see AGENTS.md generator-prototype notes), not a
/// long-term stable production schema — feel free to reshape it as the
/// generator evolves.
public struct DifficultyExport: Codable, Equatable, Sendable {
    public let score: Int
    public let tier: String

    public init(_ difficulty: PuzzleDifficulty) {
        score = difficulty.score
        switch difficulty.tier {
        case .beginner: tier = "beginner"
        case .easy: tier = "easy"
        case .medium: tier = "medium"
        case .hard: tier = "hard"
        case .expert: tier = "expert"
        case .challenge: tier = "challenge"
        }
    }
}

public struct LogicalStatisticsExport: Codable, Equatable, Sendable {
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

    public init(_ statistics: LogicalSolveStatistics) {
        placedCats = statistics.placedCats
        exclusions = statistics.exclusions
        propagationSteps = statistics.propagationSteps
        deductionRounds = statistics.deductionRounds
        assumptionCount = statistics.assumptionCount
        maxAssumptionDepth = statistics.maxAssumptionDepth
        lockedPairCount = statistics.lockedPairCount
        lockedTripleCount = statistics.lockedTripleCount
        commonAttackCount = statistics.commonAttackCount
        strongLinkDeductionCount = statistics.strongLinkDeductionCount
    }
}

public struct GeneratedPuzzleExport: Codable, Equatable, Sendable {
    public let seed: UInt64
    public let attempt: Int
    public let size: Int
    public let solution: [Int]
    public let colorIDs: [[Int]]
    public let difficulty: DifficultyExport
    public let statistics: LogicalStatisticsExport

    public init(_ puzzle: GeneratedPuzzle) {
        seed = puzzle.generationMetadata.seed
        attempt = puzzle.generationMetadata.attempt
        size = puzzle.level.size
        solution = puzzle.solution.sorted { $0.row < $1.row }.map(\.column)
        colorIDs = puzzle.level.colorIDs
        difficulty = DifficultyExport(puzzle.difficulty)
        statistics = LogicalStatisticsExport(puzzle.logicalReport.statistics)
    }
}

public struct PuzzleBatchRejectionsExport: Codable, Equatable, Sendable {
    public let invalidLevel: Int
    public let noSolution: Int
    public let multipleSolutions: Int
    public let wrongUniqueSolution: Int
    public let logicalStuck: Int
    public let notChallenge: Int

    public init(_ statistics: PuzzleBatchStatistics) {
        invalidLevel = statistics.rejectedInvalidLevel
        noSolution = statistics.rejectedNoSolution
        multipleSolutions = statistics.rejectedMultipleSolutions
        wrongUniqueSolution = statistics.rejectedWrongUniqueSolution
        logicalStuck = statistics.rejectedLogicalStuck
        notChallenge = statistics.rejectedNotChallenge
    }
}

public struct PuzzleBatchExport: Codable, Equatable, Sendable {
    public let requestedCount: Int
    public let generatedCount: Int
    public let totalAttempts: Int
    public let acceptanceRate: Double
    public let rejections: PuzzleBatchRejectionsExport
    public let puzzles: [GeneratedPuzzleExport]

    public init(_ result: PuzzleBatchGenerationResult) {
        requestedCount = result.statistics.requestedCount
        generatedCount = result.statistics.generatedCount
        totalAttempts = result.statistics.totalAttempts
        acceptanceRate = result.statistics.acceptanceRate
        rejections = PuzzleBatchRejectionsExport(result.statistics)
        puzzles = result.generated.map(GeneratedPuzzleExport.init)
    }
}
