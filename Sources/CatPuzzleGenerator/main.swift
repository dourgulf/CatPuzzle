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
    var maxMistakes = 5
    var size = 6
    var bias: Double?
    var jsonPath: String?
}

func printUsageAndExit() -> Never {
    print("""
    Usage: CatPuzzleGenerator [options]
      --count <Int>            Number of puzzles to generate (default 10)
      --seed <UInt64>          Starting seed (default 1)
      --mode mainline|challenge:<depth>   Acceptance mode (default mainline)
      --max-attempts <Int>     Max attempts per puzzle (default 500)
      --max-mistakes <Int>     maxMistakes on generated levels (default 5)
      --bias <Double>          Nearby-Region bias probability [0,1] (default: uniform, no bias)
      --json <path>            Write JSON results to path
    """)
    exit(1)
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
        case "--max-mistakes":
            guard let value = Int(nextValue()) else { printUsageAndExit() }
            options.maxMistakes = value
        case "--size":
            guard let value = Int(nextValue()) else { printUsageAndExit() }
            options.size = value
        case "--bias":
            guard let value = Double(nextValue()) else { printUsageAndExit() }
            options.bias = value
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

guard options.size == 6 else {
    print("Generator prototype only supports size = 6 for now (got \(options.size)).")
    exit(1)
}

let strategy: RegionAssignmentStrategy = options.bias.map { .biased(nearbySampleProbability: $0) } ?? .uniform

let batchRequest = PuzzleBatchGenerationRequest(
    startSeed: options.seed,
    count: options.count,
    mode: options.mode,
    maxAttemptsPerPuzzle: options.maxAttempts,
    size: options.size,
    maxMistakes: options.maxMistakes,
    regionAssignmentStrategy: strategy
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
logicalStuck: \(stats.rejectedLogicalStuck), notChallenge: \(stats.rejectedNotChallenge)
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
    print("higherOrderLockedSet: \(stats.higherOrderLockedSetCount)")
    print("commonAttack: \(stats.commonAttackCount)")
    print("strongLink: \(stats.strongLinkDeductionCount)")
    print("assumptions: \(stats.assumptionCount)")
    print("regionIDs: \(puzzle.level.regionIDs)")
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
