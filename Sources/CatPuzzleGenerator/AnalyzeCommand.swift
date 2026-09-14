import CatPuzzleCore
import Foundation

/// `--analyze` support for the research CLI: score levels that already exist
/// (e.g. transcribed from a design screenshot) instead of generating new ones.
///
/// Read-only — it runs `LogicalPuzzleSolver` + `PuzzleDifficultyAnalyzer`
/// exactly as shipped and prints their verdict as JSON, so the Python
/// step-by-step solver's difficulty rating can be compared against Core's
/// without either side changing behaviour.

struct AnalyzeInputLevel: Decodable {
    let id: String?
    let size: Int
    let catCount: Int?
    let maxMistakes: Int?
    let regionIDs: [[Int]]
}

struct AnalyzeOutputLevel: Encodable {
    let id: String
    let size: Int
    /// Outcome with no assumptions allowed (Core's mainline acceptance mode).
    let logicOnlyStatus: String
    /// Outcome allowing depth-1 proof by contradiction, matching the reach of
    /// the Python step-by-step solver.
    let status: String
    let score: Int
    let tier: String
    let steps: Int
    let placedCats: Int
    let exclusions: Int
    let propagationSteps: Int
    let deductionRounds: Int
    let lockedPair: Int
    let lockedTriple: Int
    let higherOrderLockedSet: Int
    let commonAttack: Int
    let strongLink: Int
    let assumptions: Int
    let maxAssumptionDepth: Int
}

private func statusName(_ result: LogicalSolveResult) -> String {
    switch result {
    case .solved: return "solved"
    case .stuck: return "stuck"
    case .contradiction: return "contradiction"
    }
}

/// Decodes either a single level object or an array of them.
private func decodeLevels(from data: Data) throws -> [AnalyzeInputLevel] {
    let decoder = JSONDecoder()
    if let many = try? decoder.decode([AnalyzeInputLevel].self, from: data) {
        return many
    }
    return [try decoder.decode(AnalyzeInputLevel.self, from: data)]
}

func runAnalyze(path: String, assumptionDepth: Int) -> Never {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else {
        FileHandle.standardError.write(Data("analyze: cannot read \(path)\n".utf8))
        exit(1)
    }
    let inputs: [AnalyzeInputLevel]
    do {
        inputs = try decodeLevels(from: data)
    } catch {
        FileHandle.standardError.write(Data("analyze: bad JSON — \(error)\n".utf8))
        exit(1)
    }

    var outputs: [AnalyzeOutputLevel] = []
    for (index, input) in inputs.enumerated() {
        let level = LevelDefinition(
            id: input.id ?? "level-\(index + 1)",
            size: input.size,
            catCount: input.catCount ?? input.size,
            maxMistakes: input.maxMistakes ?? 3,
            regionIDs: input.regionIDs
        )
        let logicOnly = LogicalPuzzleSolver.solve(level: level, mode: .logicOnly)
        let result = assumptionDepth > 0
            ? LogicalPuzzleSolver.solve(
                level: level,
                mode: .challenge(maxAssumptionDepth: assumptionDepth))
            : logicOnly
        let report = result.report
        let stats = report.statistics
        let difficulty = PuzzleDifficultyAnalyzer.analyze(report)
        outputs.append(AnalyzeOutputLevel(
            id: level.id,
            size: level.size,
            logicOnlyStatus: statusName(logicOnly),
            status: statusName(result),
            score: difficulty.score,
            tier: tierName(difficulty.tier),
            steps: report.steps.count,
            placedCats: stats.placedCats,
            exclusions: stats.exclusions,
            propagationSteps: stats.propagationSteps,
            deductionRounds: stats.deductionRounds,
            lockedPair: stats.lockedPairCount,
            lockedTriple: stats.lockedTripleCount,
            higherOrderLockedSet: stats.higherOrderLockedSetCount,
            commonAttack: stats.commonAttackCount,
            strongLink: stats.strongLinkDeductionCount,
            assumptions: stats.assumptionCount,
            maxAssumptionDepth: stats.maxAssumptionDepth
        ))
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let out = try? encoder.encode(outputs) else {
        FileHandle.standardError.write(Data("analyze: cannot encode result\n".utf8))
        exit(1)
    }
    FileHandle.standardOutput.write(out)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

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
