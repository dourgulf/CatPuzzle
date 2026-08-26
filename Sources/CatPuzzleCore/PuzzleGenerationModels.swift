/// Which acceptance bar a generated candidate must clear.
///
/// `.mainline` requires the puzzle to be fully solvable by
/// `LogicalPuzzleSolver` in `.logicOnly` mode (no assumptions). `.challenge`
/// requires `.logicOnly` to get stuck, and a bounded `.challenge` solve
/// (at most `maxAssumptionDepth`) to reach the solution — i.e. it genuinely
/// needs proof-by-contradiction, not just more of the same deterministic
/// techniques.
public enum PuzzleGenerationMode: Equatable, Sendable {
    case mainline
    case challenge(maxAssumptionDepth: Int)
}

/// How non-solution cells are colored once the six solution cats have
/// claimed one color each. Colors are never required to be connected
/// regions (see CLAUDE.md); this only controls how "clumpy" the coloring
/// looks to a human player.
public enum ColorAssignmentStrategy: Equatable, Sendable {
    /// Every non-solution cell gets a uniformly random color.
    case uniform
    /// Each non-solution cell has `nearbySampleProbability` chance of
    /// reusing the color of its nearest solution cat (Manhattan distance,
    /// ties broken by row then column) instead of a uniform draw.
    case biased(nearbySampleProbability: Double)
}

public struct PuzzleGenerationRequest: Sendable {
    public let size: Int
    public let seed: UInt64
    public let mode: PuzzleGenerationMode
    public let maxAttempts: Int
    public let maxMistakes: Int
    public let colorAssignmentStrategy: ColorAssignmentStrategy

    public init(
        size: Int = 6,
        seed: UInt64,
        mode: PuzzleGenerationMode,
        maxAttempts: Int = 500,
        maxMistakes: Int = 5,
        colorAssignmentStrategy: ColorAssignmentStrategy = .uniform
    ) {
        self.size = size
        self.seed = seed
        self.mode = mode
        self.maxAttempts = maxAttempts
        self.maxMistakes = maxMistakes
        self.colorAssignmentStrategy = colorAssignmentStrategy
    }
}

public struct PuzzleGenerationMetadata: Equatable, Sendable {
    public let seed: UInt64
    public let attempt: Int

    public init(seed: UInt64, attempt: Int) {
        self.seed = seed
        self.attempt = attempt
    }
}

public struct GeneratedPuzzle: Equatable, Sendable {
    public let level: LevelDefinition
    public let solution: [CellPosition]
    public let logicalReport: LogicalSolveReport
    public let difficulty: PuzzleDifficulty
    public let generationMetadata: PuzzleGenerationMetadata

    public init(
        level: LevelDefinition,
        solution: [CellPosition],
        logicalReport: LogicalSolveReport,
        difficulty: PuzzleDifficulty,
        generationMetadata: PuzzleGenerationMetadata
    ) {
        self.level = level
        self.solution = solution
        self.logicalReport = logicalReport
        self.difficulty = difficulty
        self.generationMetadata = generationMetadata
    }
}

/// Why candidates were thrown away during a `generate`/`generateBatch` run.
/// Every candidate that isn't accepted increments exactly one of these, in
/// pipeline order (structural validity, then solvability, then logic mode).
public struct PuzzleGenerationRejectionCounts: Equatable, Sendable {
    public var invalidLevel: Int = 0
    public var noSolution: Int = 0
    public var multipleSolutions: Int = 0
    public var wrongUniqueSolution: Int = 0
    public var logicalStuck: Int = 0
    public var notChallenge: Int = 0

    public init(
        invalidLevel: Int = 0,
        noSolution: Int = 0,
        multipleSolutions: Int = 0,
        wrongUniqueSolution: Int = 0,
        logicalStuck: Int = 0,
        notChallenge: Int = 0
    ) {
        self.invalidLevel = invalidLevel
        self.noSolution = noSolution
        self.multipleSolutions = multipleSolutions
        self.wrongUniqueSolution = wrongUniqueSolution
        self.logicalStuck = logicalStuck
        self.notChallenge = notChallenge
    }

    static func += (lhs: inout Self, rhs: Self) {
        lhs.invalidLevel += rhs.invalidLevel
        lhs.noSolution += rhs.noSolution
        lhs.multipleSolutions += rhs.multipleSolutions
        lhs.wrongUniqueSolution += rhs.wrongUniqueSolution
        lhs.logicalStuck += rhs.logicalStuck
        lhs.notChallenge += rhs.notChallenge
    }
}

/// Returned by `PuzzleGenerator.generate` when no candidate cleared the
/// pipeline within `maxAttempts` tries.
public struct PuzzleGenerationReport: Equatable, Sendable {
    public let seed: UInt64
    public let attempts: Int
    public let rejections: PuzzleGenerationRejectionCounts

    public init(seed: UInt64, attempts: Int, rejections: PuzzleGenerationRejectionCounts) {
        self.seed = seed
        self.attempts = attempts
        self.rejections = rejections
    }
}

public enum PuzzleGenerationResult: Equatable, Sendable {
    case generated(GeneratedPuzzle)
    case exhausted(PuzzleGenerationReport)
}

public struct PuzzleBatchGenerationRequest: Sendable {
    public let startSeed: UInt64
    public let count: Int
    public let mode: PuzzleGenerationMode
    public let maxAttemptsPerPuzzle: Int
    public let size: Int
    public let maxMistakes: Int
    public let colorAssignmentStrategy: ColorAssignmentStrategy

    public init(
        startSeed: UInt64,
        count: Int,
        mode: PuzzleGenerationMode,
        maxAttemptsPerPuzzle: Int = 500,
        size: Int = 6,
        maxMistakes: Int = 5,
        colorAssignmentStrategy: ColorAssignmentStrategy = .uniform
    ) {
        self.startSeed = startSeed
        self.count = count
        self.mode = mode
        self.maxAttemptsPerPuzzle = maxAttemptsPerPuzzle
        self.size = size
        self.maxMistakes = maxMistakes
        self.colorAssignmentStrategy = colorAssignmentStrategy
    }
}

public struct PuzzleBatchStatistics: Equatable, Sendable {
    public let requestedCount: Int
    public let generatedCount: Int
    public let totalAttempts: Int
    public let rejectedInvalidLevel: Int
    public let rejectedNoSolution: Int
    public let rejectedMultipleSolutions: Int
    public let rejectedWrongUniqueSolution: Int
    public let rejectedLogicalStuck: Int
    public let rejectedNotChallenge: Int

    public init(
        requestedCount: Int,
        generatedCount: Int,
        totalAttempts: Int,
        rejectedInvalidLevel: Int,
        rejectedNoSolution: Int,
        rejectedMultipleSolutions: Int,
        rejectedWrongUniqueSolution: Int,
        rejectedLogicalStuck: Int,
        rejectedNotChallenge: Int
    ) {
        self.requestedCount = requestedCount
        self.generatedCount = generatedCount
        self.totalAttempts = totalAttempts
        self.rejectedInvalidLevel = rejectedInvalidLevel
        self.rejectedNoSolution = rejectedNoSolution
        self.rejectedMultipleSolutions = rejectedMultipleSolutions
        self.rejectedWrongUniqueSolution = rejectedWrongUniqueSolution
        self.rejectedLogicalStuck = rejectedLogicalStuck
        self.rejectedNotChallenge = rejectedNotChallenge
    }

    public var acceptanceRate: Double {
        totalAttempts > 0 ? Double(generatedCount) / Double(totalAttempts) : 0
    }
}

public struct PuzzleBatchGenerationResult: Equatable, Sendable {
    public let generated: [GeneratedPuzzle]
    public let statistics: PuzzleBatchStatistics

    public init(generated: [GeneratedPuzzle], statistics: PuzzleBatchStatistics) {
        self.generated = generated
        self.statistics = statistics
    }
}
