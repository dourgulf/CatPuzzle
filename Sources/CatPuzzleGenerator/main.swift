import CatPuzzleCore
import Foundation

// Minimal hand-rolled argument parsing (no ArgumentParser dependency, per
// the generator-prototype spec). This is a research/dev CLI, not a
// production tool, so failures just print usage and exit.

struct CLIOptions {
    var count = 10
    var seed: UInt64 = 1
    var mode: PuzzleGenerationMode = .mainline
    var maxAttempts = 500
    var maxRepairAttempts = 300
    var maxMistakes = 5
    // 8x8-10x10 is the generator's primary target; 6x6 remains fully
    // supported (BuiltInLevels already ships hand-verified 6x6 fixtures,
    // so the generator only needs to cover it for occasional playtesting).
    var size = 9
    // Empirically the best default for the 8-10 primary target: at size 9
    // it reaches hard/medium tiers in ~15-180 attempts, versus plain
    // uniform coloring needing hundreds of attempts just to find *any*
    // mainline-solvable candidate (most of which still land on expert).
    var colorStrategy: ColorAssignmentStrategy = .confinedColorPair(axis: .rows)
    var targetTiers: Set<DifficultyTier> = []
    var jsonPath: String?
}

func printUsageAndExit() -> Never {
    print("""
    Usage: CatPuzzleGenerator [options]
      --count <Int>            Number of puzzles to generate (default 10)
      --seed <UInt64>          Starting seed (default 1)
      --mode mainline|challenge:<depth>   Acceptance mode (default mainline)
      --max-attempts <Int>     Max attempts per puzzle (default 500)
      --max-repair-attempts <Int>  Max recolors tried per attempt to force
                                a unique solution (default 300) — this is
                                what makes 8-10 sized boards practical;
                                see repairForUniqueSolution in PuzzleGenerator.
      --max-mistakes <Int>     maxMistakes on generated levels (default 5)
      --size <Int>             Board size (default 9; primary target is 8-10,
                                6 remains supported for occasional playtesting)
      --color-strategy <spec>  uniform | biased:<p> | singleton |
                                confined-rows (default) | confined-columns
                                See below for what each strategy does.
      --tiers <list>           Comma-separated difficulty tiers to accept
                                (beginner,easy,medium,hard,expert,challenge).
                                Default: accept any tier.
      --json <path>            Write JSON results to path

    Color strategies:
      uniform            Every non-solution cell gets a uniformly random color.
      biased:<p>          Each non-solution cell has probability p [0,1] of
                          reusing its nearest solution cat's color.
      singleton           One random color is confined to its own solution
                          cell, giving an immediate onlyCandidateForColor
                          foothold — aim for beginner/easy tiers.
      confined-rows        Two random colors are confined to just the two
                          rows their solution cats sit in, giving an
                          immediate locked-pair foothold — aim for easy/
                          medium tiers.
      confined-columns     Same as confined-rows, but confines to columns.

    Recommended for the 8-10 primary target: --tiers medium,hard along
    with the default confined-rows strategy — this reaches an accepted
    puzzle in tens to a couple hundred attempts, versus effectively never
    with uniform coloring and no tier filter.
    """)
    exit(1)
}

func parseColorStrategy(_ raw: String) -> ColorAssignmentStrategy? {
    switch raw {
    case "uniform":
        return .uniform
    case "singleton":
        return .singletonColor
    case "confined-rows":
        return .confinedColorPair(axis: .rows)
    case "confined-columns":
        return .confinedColorPair(axis: .columns)
    default:
        guard raw.hasPrefix("biased:"), let probability = Double(raw.dropFirst("biased:".count)) else {
            return nil
        }
        return .biased(nearbySampleProbability: probability)
    }
}

func parseTier(_ raw: String) -> DifficultyTier? {
    switch raw {
    case "beginner": return .beginner
    case "easy": return .easy
    case "medium": return .medium
    case "hard": return .hard
    case "expert": return .expert
    case "challenge": return .challenge
    default: return nil
    }
}

func parseArguments(_ arguments: [String]) -> CLIOptions {
    var options = CLIOptions()
    var index = 0
    func nextValue() -> String {
        index += 1
        guard index < arguments.count else { printUsageAndExit() }
        return arguments[index]
    }

    while index < arguments.count {
        switch arguments[index] {
        case "--count":
            guard let value = Int(nextValue()) else { printUsageAndExit() }
            options.count = value
        case "--seed":
            guard let value = UInt64(nextValue()) else { printUsageAndExit() }
            options.seed = value
        case "--mode":
            let raw = nextValue()
            if raw == "mainline" {
                options.mode = .mainline
            } else if raw.hasPrefix("challenge:"), let depth = Int(raw.dropFirst("challenge:".count)) {
                options.mode = .challenge(maxAssumptionDepth: depth)
            } else {
                printUsageAndExit()
            }
        case "--max-attempts":
            guard let value = Int(nextValue()) else { printUsageAndExit() }
            options.maxAttempts = value
        case "--max-repair-attempts":
            guard let value = Int(nextValue()) else { printUsageAndExit() }
            options.maxRepairAttempts = value
        case "--max-mistakes":
            guard let value = Int(nextValue()) else { printUsageAndExit() }
            options.maxMistakes = value
        case "--size":
            guard let value = Int(nextValue()), value >= 2 else { printUsageAndExit() }
            options.size = value
        case "--color-strategy":
            guard let strategy = parseColorStrategy(nextValue()) else { printUsageAndExit() }
            options.colorStrategy = strategy
        case "--tiers":
            let raw = nextValue()
            let tiers = raw.split(separator: ",").map(String.init).map(parseTier)
            guard !tiers.isEmpty, tiers.allSatisfy({ $0 != nil }) else { printUsageAndExit() }
            options.targetTiers = Set(tiers.compactMap { $0 })
        case "--json":
            options.jsonPath = nextValue()
        case "--help", "-h":
            printUsageAndExit()
        default:
            printUsageAndExit()
        }
        index += 1
    }
    return options
}

let options = parseArguments(Array(CommandLine.arguments.dropFirst()))

let batchRequest = PuzzleBatchGenerationRequest(
    startSeed: options.seed,
    count: options.count,
    mode: options.mode,
    maxAttemptsPerPuzzle: options.maxAttempts,
    size: options.size,
    maxMistakes: options.maxMistakes,
    colorAssignmentStrategy: options.colorStrategy,
    targetTiers: options.targetTiers,
    maxRepairAttempts: options.maxRepairAttempts
)

let start = DispatchTime.now()
let result = PuzzleGenerator.generateBatch(request: batchRequest)
let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

let stats = result.statistics
print("Generated \(stats.generatedCount) puzzles")
print("Total attempts: \(stats.totalAttempts)")
print(String(format: "Acceptance rate: %.2f%%", stats.acceptanceRate * 100))
if stats.generatedCount > 0 {
    let averageAttempts = Double(stats.totalAttempts) / Double(stats.generatedCount)
    print(String(format: "Average attempts per accepted puzzle: %.2f", averageAttempts))
}
print(String(format: "Elapsed: %.3fs", elapsedSeconds))
print("""
Rejections — invalidLevel: \(stats.rejectedInvalidLevel), noSolution: \(stats.rejectedNoSolution), \
multipleSolutions: \(stats.rejectedMultipleSolutions), wrongUniqueSolution: \(stats.rejectedWrongUniqueSolution), \
logicalStuck: \(stats.rejectedLogicalStuck), notChallenge: \(stats.rejectedNotChallenge), \
difficultyMismatch: \(stats.rejectedDifficultyMismatch)
""")
print("")

func tierName(_ tier: DifficultyTier) -> String {
    switch tier {
    case .beginner: return "beginner"
    case .easy: return "easy"
    case .medium: return "medium"
    case .hard: return "hard"
    case .expert: return "expert"
    case .challenge: return "challenge"
    }
}

func solutionColumns(_ puzzle: GeneratedPuzzle) -> [Int] {
    puzzle.solution.sorted { $0.row < $1.row }.map(\.column)
}

for (index, puzzle) in result.generated.enumerated() {
    let stats = puzzle.logicalReport.statistics
    print("#\(index + 1)")
    print("seed: \(puzzle.generationMetadata.seed)")
    print("solution: \(solutionColumns(puzzle))")
    print("score: \(puzzle.difficulty.score)")
    print("tier: \(tierName(puzzle.difficulty.tier))")
    print("lockedPair: \(stats.lockedPairCount)")
    print("lockedTriple: \(stats.lockedTripleCount)")
    print("commonAttack: \(stats.commonAttackCount)")
    print("strongLink: \(stats.strongLinkDeductionCount)")
    print("assumptions: \(stats.assumptionCount)")
    print("colorIDs: \(puzzle.level.colorIDs)")
    print("")
}

if let jsonPath = options.jsonPath {
    let batchExport = PuzzleBatchExport(result)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let data = try encoder.encode(batchExport)
        try data.write(to: URL(fileURLWithPath: jsonPath))
        print("Wrote JSON results to \(jsonPath)")
    } catch {
        print("Failed to write JSON: \(error)")
        exit(1)
    }
}
