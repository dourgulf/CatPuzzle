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

/// Which axis a `.confinedColorPair` strategy confines its two colors to.
public enum ConfinementAxis: Equatable, Sendable {
    case rows
    case columns
}

/// How non-solution cells are colored once the solution cats have claimed
/// one color each. Colors are never required to be connected regions (see
/// CLAUDE.md); this only controls how "clumpy" the coloring looks to a
/// human player, and — for the two onboarding strategies — how early a
/// deterministic foothold is available to `LogicalPuzzleSolver`.
public enum ColorAssignmentStrategy: Equatable, Sendable {
    /// Every non-solution cell gets a uniformly random color.
    case uniform
    /// Each non-solution cell has `nearbySampleProbability` chance of
    /// reusing the color of its nearest solution cat (Manhattan distance,
    /// ties broken by row then column) instead of a uniform draw.
    case biased(nearbySampleProbability: Double)
    /// One randomly chosen color is confined to its own solution cell —
    /// no other cell on the board reuses it. That color's candidate set
    /// starts at exactly one cell, so `LogicalPuzzleSolver` can place it
    /// immediately via `.onlyCandidateForColor`, giving beginner-tier
    /// puzzles a deterministic first move instead of requiring an advanced
    /// deduction just to get started.
    case singletonColor
    /// Two randomly chosen colors are confined to only the two rows (or
    /// columns, per `axis`) their own solution cats sit in — no cell of
    /// either color appears outside those two rows/columns. This creates a
    /// locked-pair (color → row/column) deduction available from the very
    /// first move, a gentler foothold than the deeper chains random
    /// coloring tends to require.
    case confinedColorPair(axis: ConfinementAxis)
}

public struct PuzzleGenerationRequest: Sendable {
    public let size: Int
    public let seed: UInt64
    public let mode: PuzzleGenerationMode
    public let maxAttempts: Int
    public let maxMistakes: Int
    public let colorAssignmentStrategy: ColorAssignmentStrategy
    /// Difficulty tiers a candidate's analyzed `PuzzleDifficulty.tier` must
    /// belong to for acceptance. Empty (the default) accepts any tier,
    /// matching the pre-filter behavior.
    public let targetTiers: Set<DifficultyTier>
    /// How many single-cell recolors `repairForUniqueSolution` may try, per
    /// candidate, to eliminate competing solutions before giving up and
    /// letting the normal uniqueness check reject the candidate. Plain
    /// random coloring's odds of landing on a unique solution collapse
    /// past ~7x7 (empirically: size 8 with uniform coloring rejected 500/500
    /// attempts as multiple-solutions), so repair is what makes 8-10 sized
    /// boards practically generatable at all.
    public let maxRepairAttempts: Int

    public init(
        size: Int = 6,
        seed: UInt64,
        mode: PuzzleGenerationMode,
        maxAttempts: Int = 500,
        maxMistakes: Int = 5,
        colorAssignmentStrategy: ColorAssignmentStrategy = .uniform,
        targetTiers: Set<DifficultyTier> = [],
        maxRepairAttempts: Int = 300
    ) {
        self.size = size
        self.seed = seed
        self.mode = mode
        self.maxAttempts = maxAttempts
        self.maxMistakes = maxMistakes
        self.colorAssignmentStrategy = colorAssignmentStrategy
        self.targetTiers = targetTiers
        self.maxRepairAttempts = maxRepairAttempts
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
    public var difficultyMismatch: Int = 0

    public init(
        invalidLevel: Int = 0,
        noSolution: Int = 0,
        multipleSolutions: Int = 0,
        wrongUniqueSolution: Int = 0,
        logicalStuck: Int = 0,
        notChallenge: Int = 0,
        difficultyMismatch: Int = 0
    ) {
        self.invalidLevel = invalidLevel
        self.noSolution = noSolution
        self.multipleSolutions = multipleSolutions
        self.wrongUniqueSolution = wrongUniqueSolution
        self.logicalStuck = logicalStuck
        self.notChallenge = notChallenge
        self.difficultyMismatch = difficultyMismatch
    }

    static func += (lhs: inout Self, rhs: Self) {
        lhs.invalidLevel += rhs.invalidLevel
        lhs.noSolution += rhs.noSolution
        lhs.multipleSolutions += rhs.multipleSolutions
        lhs.wrongUniqueSolution += rhs.wrongUniqueSolution
        lhs.logicalStuck += rhs.logicalStuck
        lhs.notChallenge += rhs.notChallenge
        lhs.difficultyMismatch += rhs.difficultyMismatch
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
    public let targetTiers: Set<DifficultyTier>
    public let maxRepairAttempts: Int

    public init(
        startSeed: UInt64,
        count: Int,
        mode: PuzzleGenerationMode,
        maxAttemptsPerPuzzle: Int = 500,
        size: Int = 6,
        maxMistakes: Int = 5,
        colorAssignmentStrategy: ColorAssignmentStrategy = .uniform,
        targetTiers: Set<DifficultyTier> = [],
        maxRepairAttempts: Int = 300
    ) {
        self.startSeed = startSeed
        self.count = count
        self.mode = mode
        self.maxAttemptsPerPuzzle = maxAttemptsPerPuzzle
        self.size = size
        self.maxMistakes = maxMistakes
        self.colorAssignmentStrategy = colorAssignmentStrategy
        self.targetTiers = targetTiers
        self.maxRepairAttempts = maxRepairAttempts
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
    public let rejectedDifficultyMismatch: Int

    public init(
        requestedCount: Int,
        generatedCount: Int,
        totalAttempts: Int,
        rejectedInvalidLevel: Int,
        rejectedNoSolution: Int,
        rejectedMultipleSolutions: Int,
        rejectedWrongUniqueSolution: Int,
        rejectedLogicalStuck: Int,
        rejectedNotChallenge: Int,
        rejectedDifficultyMismatch: Int
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
        self.rejectedDifficultyMismatch = rejectedDifficultyMismatch
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
