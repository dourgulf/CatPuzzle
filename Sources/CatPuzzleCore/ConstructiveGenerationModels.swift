public enum GeneratorDifficulty: String, CaseIterable, Equatable, Sendable {
    case easy
    case medium
    case hard
}

public enum RegionGeometryProfile: String, CaseIterable, Equatable, Sendable {
    case dominantBackground
    case balancedMosaic
}

public struct GenerationBudget: Equatable, Sendable {
    /// Maximum solution permutations considered by one generation request.
    public let solutionRestarts: Int
    /// Global maximum partition builds across all solution permutations.
    public let partitionRestarts: Int
    /// Global maximum accepted or rejected boundary moves.
    public let boundaryMutations: Int
    /// Global maximum calls to the deterministic logical solver.
    public let logicalEvaluations: Int
    public let exactSolverNodes: Int
    public let beamWidth: Int

    public init(
        solutionRestarts: Int = 20,
        partitionRestarts: Int = 800,
        boundaryMutations: Int = 64,
        logicalEvaluations: Int = 64,
        exactSolverNodes: Int = 250_000,
        beamWidth: Int = 8
    ) {
        self.solutionRestarts = max(0, solutionRestarts)
        self.partitionRestarts = max(0, partitionRestarts)
        self.boundaryMutations = max(0, boundaryMutations)
        self.logicalEvaluations = max(0, logicalEvaluations)
        self.exactSolverNodes = max(0, exactSolverNodes)
        self.beamWidth = max(1, beamWidth)
    }
}

public struct ConstructiveGenerationRequest: Equatable, Sendable {
    public let size: Int
    public let seed: UInt64
    public let difficulty: GeneratorDifficulty
    public let profile: RegionGeometryProfile
    public let maxMistakes: Int
    public let budget: GenerationBudget
    /// Number of solution cells shipped pre-placed as locked `given` cats,
    /// giving the player a gentle opening independent of Region geometry
    /// (human sample: levels 231 and 232 ship a dominant-background layout
    /// with one given cat). Defaults to 0. A given anchor is an optional
    /// overlay on an already-accepted level: it never changes which layout
    /// is certified, only pre-reveals cells of that layout's unique solution.
    public let givenAnchorCount: Int

    public init(
        size: Int,
        seed: UInt64,
        difficulty: GeneratorDifficulty,
        profile: RegionGeometryProfile,
        maxMistakes: Int = 5,
        budget: GenerationBudget = GenerationBudget(),
        givenAnchorCount: Int = 0
    ) {
        self.size = size
        self.seed = seed
        self.difficulty = difficulty
        self.profile = profile
        self.maxMistakes = maxMistakes
        self.budget = budget
        self.givenAnchorCount = max(0, givenAnchorCount)
    }
}

public struct RegionGeometryMetrics: Equatable, Sendable {
    public let areasByRegionID: [Int: Int]
    public let connectedRegionCount: Int
    public let regionsWithHoles: [Int]
    public let singletonRegionCount: Int
    public let largestRegionFraction: Double
    public let narrowCorridorCellCount: Int

    public init(
        areasByRegionID: [Int: Int],
        connectedRegionCount: Int,
        regionsWithHoles: [Int],
        singletonRegionCount: Int,
        largestRegionFraction: Double,
        narrowCorridorCellCount: Int
    ) {
        self.areasByRegionID = areasByRegionID
        self.connectedRegionCount = connectedRegionCount
        self.regionsWithHoles = regionsWithHoles
        self.singletonRegionCount = singletonRegionCount
        self.largestRegionFraction = largestRegionFraction
        self.narrowCorridorCellCount = narrowCorridorCellCount
    }
}

public struct BlueprintCoverage: Equatable, Sendable {
    public let achievedStages: Int
    public let requiredStages: Int
    public let isSatisfied: Bool
    public let violations: [String]

    public init(
        achievedStages: Int,
        requiredStages: Int,
        isSatisfied: Bool,
        violations: [String]
    ) {
        self.achievedStages = achievedStages
        self.requiredStages = requiredStages
        self.isSatisfied = isSatisfied
        self.violations = violations
    }
}

public struct GenerationWork: Equatable, Sendable {
    public let solutionRestarts: Int
    public let partitionRestarts: Int
    public let boundaryMutations: Int
    public let logicalEvaluations: Int

    public init(
        solutionRestarts: Int,
        partitionRestarts: Int,
        boundaryMutations: Int,
        logicalEvaluations: Int
    ) {
        self.solutionRestarts = solutionRestarts
        self.partitionRestarts = partitionRestarts
        self.boundaryMutations = boundaryMutations
        self.logicalEvaluations = logicalEvaluations
    }
}

public struct ConstructiveGeneratedPuzzle: Equatable, Sendable {
    public static let algorithmVersion = 1

    public let level: LevelDefinition
    public let solution: [CellPosition]
    public let logicalReport: LogicalSolveReport
    public let exactSolverReport: PuzzleSolverReport
    public let difficulty: GeneratorDifficulty
    public let profile: RegionGeometryProfile
    public let blueprintCoverage: BlueprintCoverage
    public let geometry: RegionGeometryMetrics
    public let seed: UInt64
    public let work: GenerationWork

    public init(
        level: LevelDefinition,
        solution: [CellPosition],
        logicalReport: LogicalSolveReport,
        exactSolverReport: PuzzleSolverReport,
        difficulty: GeneratorDifficulty,
        profile: RegionGeometryProfile,
        blueprintCoverage: BlueprintCoverage,
        geometry: RegionGeometryMetrics,
        seed: UInt64,
        work: GenerationWork
    ) {
        self.level = level
        self.solution = solution
        self.logicalReport = logicalReport
        self.exactSolverReport = exactSolverReport
        self.difficulty = difficulty
        self.profile = profile
        self.blueprintCoverage = blueprintCoverage
        self.geometry = geometry
        self.seed = seed
        self.work = work
    }
}

public enum GenerationFailureStage: String, Equatable, Sendable {
    case invalidRequest
    case cancelled
    case solution
    case partition
    case logicalSearch
    case certification
}

public struct GenerationFailure: Error, Equatable, Sendable {
    public let stage: GenerationFailureStage
    public let seed: UInt64
    public let message: String
    public let work: GenerationWork
    public let bestLogicalReport: LogicalSolveReport?
    public let bestGeometry: RegionGeometryMetrics?

    public init(
        stage: GenerationFailureStage,
        seed: UInt64,
        message: String,
        work: GenerationWork,
        bestLogicalReport: LogicalSolveReport? = nil,
        bestGeometry: RegionGeometryMetrics? = nil
    ) {
        self.stage = stage
        self.seed = seed
        self.message = message
        self.work = work
        self.bestLogicalReport = bestLogicalReport
        self.bestGeometry = bestGeometry
    }
}
