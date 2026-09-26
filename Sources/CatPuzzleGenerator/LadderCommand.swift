import CatPuzzleCore
import Foundation

/// `--ladder` support for the research CLI: produce the shipped level ladder
/// offline and emit it as `BuiltInLevels.swift` source.
///
/// The player experience is a repeating ten-level cycle: one 8x8 opener, three
/// 9x9 levels, five 10x10 levels, and a final 10x10 at the next difficulty
/// tier. `--cycles` many cycles are emitted back to back, each cycle covering
/// the same difficulty shape with different puzzles.
///
/// Difficulty is placed twice over. The generator's own `GeneratorDifficulty`
/// decides which deduction blueprint a level must satisfy; `PuzzleDifficulty`
/// then orders the accepted candidates inside one slot group, so the five
/// consecutive 10x10 slots rise in measured difficulty instead of landing in
/// arbitrary order.

/// One slot group of the ten-level cycle: the slots share a board size and
/// draw from one candidate pool.
///
/// A group lists the generator difficulties its pool may draw from rather than
/// a single one. `GeneratorDifficulty` picks which deduction blueprint a level
/// must satisfy, and at 9x9/10x10 that does *not* order levels by measured
/// difficulty — `easy` boards routinely score above `medium` ones, because the
/// score counts deduction volume while the blueprint constrains technique.
/// Pooling both tiers and ordering by `PuzzleDifficulty` gives a ramp that
/// actually rises. The final slot is the exception: it draws from `hard` only,
/// so every cycle ends on a board that genuinely needs advanced techniques.
struct LadderGroup {
    /// 1-based positions inside one ten-level cycle.
    let positions: [Int]
    let size: Int
    let difficulties: [GeneratorDifficulty]
}

enum LadderSpec {
    static let groups: [LadderGroup] = [
        LadderGroup(positions: [1], size: 8, difficulties: [.easy]),
        LadderGroup(positions: [2, 3, 4], size: 9, difficulties: [.easy, .medium]),
        LadderGroup(positions: [5, 6, 7, 8, 9], size: 10, difficulties: [.easy, .medium]),
        LadderGroup(positions: [10], size: 10, difficulties: [.hard]),
    ]

    static var levelsPerCycle: Int {
        groups.reduce(0) { $0 + $1.positions.count }
    }
}

struct LadderOptions {
    var cycles = 3
    var seed: UInt64 = 1
    var maxMistakes = 5
    /// Candidates generated per level actually shipped. A wider pool gives the
    /// score-based ordering more range to spread the slots across.
    var poolMultiplier = 4
    var swiftPath: String?
    var jsonPath: String?
}

private let ladderBudget = GenerationBudget(
    solutionRestarts: 40,
    partitionRestarts: 2_000,
    boundaryMutations: 128,
    logicalEvaluations: 128,
    exactSolverNodes: 500_000,
    beamWidth: 12
)

private struct ScoredCandidate {
    let puzzle: ConstructiveGeneratedPuzzle
    let difficulty: PuzzleDifficulty

    /// Row-ordered cat columns. Two boards with different Region layouts can
    /// still land on the same cat placement; shipping both in one ladder reads
    /// as a repeat, so this is what the ladder de-duplicates on.
    var solutionKey: [Int] {
        puzzle.solution.sorted { $0.row < $1.row }.map(\.column)
    }
}

private struct LadderEntry {
    let index: Int
    let cycle: Int
    let position: Int
    let id: String
    let puzzle: ConstructiveGeneratedPuzzle
    let difficulty: PuzzleDifficulty
}

private struct LadderExportLevel: Encodable {
    let id: String
    let index: Int
    let cycle: Int
    let position: Int
    let size: Int
    let requestedDifficulty: String
    let profile: String
    let seed: UInt64
    let score: Int
    let tier: String
    let regionIDs: [[Int]]
    let solution: [[Int]]
}

/// Generates `needed` accepted candidates' worth of pool for one bucket.
private func generatePool(
    size: Int,
    difficulties: [GeneratorDifficulty],
    target: Int,
    startSeed: UInt64,
    maxMistakes: Int
) -> [ConstructiveGeneratedPuzzle] {
    var accepted: [ConstructiveGeneratedPuzzle] = []
    var seed = startSeed
    var attempts = 0
    let attemptLimit = target * 12

    while accepted.count < target, attempts < attemptLimit {
        // Cycling difficulty and geometry profile together keeps one band from
        // looking like ten variations of the same board, and keeps the pool
        // evenly drawn from every blueprint the group allows.
        let difficulty = difficulties[attempts % difficulties.count]
        let profile: RegionGeometryProfile = (attempts / difficulties.count) % 2 == 0
            ? .dominantBackground
            : .balancedMosaic
        let request = ConstructiveGenerationRequest(
            size: size,
            seed: seed,
            difficulty: difficulty,
            profile: profile,
            maxMistakes: maxMistakes,
            budget: ladderBudget
        )
        if case let .success(puzzle) = ConstructivePuzzleGenerator.generate(request: request) {
            accepted.append(puzzle)
        }
        seed &+= 1
        attempts += 1
    }
    return accepted
}

/// Chooses which pool candidates fill a group's slots.
///
/// Spreading the *slots* across the sorted pool is what builds the ramp;
/// taking each slot's `perSlot` candidates from adjacent positions is what
/// keeps every cycle's version of that slot comparable, which is the point of
/// running the same ten-level shape each lap. Spreading within a slot instead
/// would hand the last cycle every band's hardest board.
private func slotPicks(
    from pool: [ScoredCandidate],
    slots: Int,
    perSlot: Int
) -> [ScoredCandidate] {
    let needed = slots * perSlot
    guard slots > 0, perSlot > 0, pool.count > needed else { return pool }

    var picks: [ScoredCandidate] = []
    let chunk = pool.count / slots
    for slot in 0..<slots {
        let lower = slot * chunk
        let upper = slot == slots - 1 ? pool.count : lower + chunk
        let start = lower + max(0, (upper - lower - perSlot) / 2)
        picks.append(contentsOf: pool[start..<(start + perSlot)])
    }
    return picks
}

private func profileName(_ profile: RegionGeometryProfile) -> String {
    switch profile {
    case .dominantBackground: return "dominantBackground"
    case .balancedMosaic: return "balancedMosaic"
    }
}

private func swiftSource(for entries: [LadderEntry], cycles: Int) -> String {
    var lines: [String] = []
    lines.append("// Generated by `swift run -c release CatPuzzleGenerator --ladder`.")
    lines.append("// Do not edit by hand — regenerate instead (see Docs/LevelLadder.md).")
    lines.append("//")
    lines.append("// \(cycles) cycles of \(LadderSpec.levelsPerCycle) levels. Each cycle opens on an 8x8")
    lines.append("// and climbs to a 10x10 at the next difficulty tier, then the next cycle")
    lines.append("// starts over on a fresh 8x8.")
    lines.append("public enum BuiltInLevels {")
    lines.append("    public static let fixtures: [LevelFixture] = [")

    for entry in entries {
        let level = entry.puzzle.level
        lines.append("        // #\(entry.index + 1) — cycle \(entry.cycle + 1) slot \(entry.position), "
            + "\(level.size)x\(level.size), blueprint \(entry.puzzle.difficulty.rawValue), "
            + "score \(entry.difficulty.score), "
            + "seed \(entry.puzzle.seed) \(profileName(entry.puzzle.profile))")
        lines.append("        LevelFixture(")
        lines.append("            level: LevelDefinition(")
        lines.append("                id: \"\(entry.id)\",")
        lines.append("                size: \(level.size),")
        lines.append("                catCount: \(level.catCount),")
        lines.append("                maxMistakes: \(level.maxMistakes),")
        lines.append("                regionIDs: [")
        for row in level.regionIDs {
            lines.append("                    [\(row.map(String.init).joined(separator: ", "))],")
        }
        lines.append("                ]")
        lines.append("            ),")
        lines.append("            solution: [")
        for position in entry.puzzle.solution.sorted(by: { $0.row < $1.row }) {
            lines.append("                CellPosition(row: \(position.row), column: \(position.column)),")
        }
        lines.append("            ]")
        lines.append("        ),")
    }

    lines.append("    ]")
    lines.append("")
    lines.append("    public static let all = fixtures.map(\\.level)")
    lines.append("")
    lines.append("    /// Levels per difficulty cycle. Progress wraps back to the first level")
    lines.append("    /// once every shipped level is complete.")
    lines.append("    public static let levelsPerCycle = \(LadderSpec.levelsPerCycle)")
    lines.append("}")
    lines.append("")
    return lines.joined(separator: "\n")
}

func runLadder(options: LadderOptions) -> Never {
    let cycles = max(1, options.cycles)
    var entries: [LadderEntry] = []
    var seed = options.seed
    let start = DispatchTime.now()
    // Cat placements already shipped. Boards repeating one read as a repeat
    // even when their Regions differ.
    var claimedSolutions: Set<[Int]> = []
    // Highest measured score handed out so far. Groups are processed in slot
    // order, and each one only draws from candidates at or above this floor,
    // so the ramp keeps rising where one board size hands over to the next.
    var scoreFloor = Int.min

    for group in LadderSpec.groups {
        let needed = group.positions.count * cycles
        let target = needed * max(1, options.poolMultiplier)

        let poolStart = DispatchTime.now()
        let pool = generatePool(
            size: group.size,
            difficulties: group.difficulties,
            target: target,
            startSeed: seed,
            maxMistakes: options.maxMistakes
        )
        let poolElapsed = Double(
            DispatchTime.now().uptimeNanoseconds - poolStart.uptimeNanoseconds
        ) / 1_000_000_000
        // Move the seed past everything this group could have consumed so
        // groups never overlap seeds.
        seed &+= UInt64(target * 12)

        var scored: [ScoredCandidate] = []
        for candidate in pool {
            let difficulty = PuzzleDifficultyAnalyzer.analyze(candidate.logicalReport)
            scored.append(ScoredCandidate(puzzle: candidate, difficulty: difficulty))
        }
        scored.sort { left, right in
            if left.difficulty.score != right.difficulty.score {
                return left.difficulty.score < right.difficulty.score
            }
            return left.puzzle.seed < right.puzzle.seed
        }

        let tiers = group.difficulties.map(\.rawValue).joined(separator: "+")
        FileHandle.standardError.write(Data("""
        \(group.size)x\(group.size) \(tiers): pool \(scored.count)/\(target), \
        need \(needed), score \(scored.first?.difficulty.score ?? 0)...\
        \(scored.last?.difficulty.score ?? 0), \(String(format: "%.1fs", poolElapsed))

        """.utf8))

        guard scored.count >= needed else {
            FileHandle.standardError.write(Data("""
            ladder: only \(scored.count) accepted candidates for \
            \(group.size)x\(group.size) \(tiers), need \(needed). \
            Raise --pool or widen the seed range.

            """.utf8))
            exit(1)
        }

        var seenSolutions = claimedSolutions
        let distinct = scored.filter { seenSolutions.insert($0.solutionKey).inserted }
        let eligible = distinct.filter { $0.difficulty.score >= scoreFloor }
        let usable: [ScoredCandidate]
        if eligible.count >= needed {
            usable = eligible
        } else {
            // Not enough candidates clear the previous group's ceiling. Taking
            // the highest-scoring ones keeps the ramp as close to monotonic as
            // this pool allows; the per-cycle report below says whether it held.
            FileHandle.standardError.write(Data("""
            ladder: only \(eligible.count) of \(distinct.count) \
            \(group.size)x\(group.size) candidates reach the previous group's \
            score floor \(scoreFloor); falling back to the top \(needed).

            """.utf8))
            usable = Array(distinct.suffix(needed))
        }

        let picks = slotPicks(
            from: usable,
            slots: group.positions.count,
            perSlot: cycles
        )
        scoreFloor = picks.map(\.difficulty.score).max() ?? scoreFloor
        // picks are score-ascending: the first `cycles` fill the group's first
        // slot in every cycle, the next `cycles` its second slot, and so on,
        // which gives all cycles the same difficulty shape.
        claimedSolutions.formUnion(picks.map(\.solutionKey))

        for (offset, pick) in picks.enumerated() {
            let position = group.positions[offset / cycles]
            let cycle = offset % cycles
            entries.append(LadderEntry(
                index: cycle * LadderSpec.levelsPerCycle + (position - 1),
                cycle: cycle,
                position: position,
                id: "",
                puzzle: pick.puzzle,
                difficulty: pick.difficulty
            ))
        }
    }

    entries.sort { $0.index < $1.index }
    let numbered = entries.enumerated().map { position, entry in
        LadderEntry(
            index: position,
            cycle: entry.cycle,
            position: entry.position,
            id: String(format: "ladder-%02d", position + 1),
            puzzle: entry.puzzle,
            difficulty: entry.difficulty
        )
    }

    let elapsed = Double(
        DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
    ) / 1_000_000_000

    func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    print([
        pad("#", 4), pad("id", 12), pad("slot", 6), pad("size", 7),
        pad("blueprint", 11), pad("score", 7), pad("seed", 7), "profile",
    ].joined())
    for entry in numbered {
        let size = entry.puzzle.level.size
        print([
            pad("\(entry.index + 1)", 4),
            pad(entry.id, 12),
            pad("\(entry.position)", 6),
            pad("\(size)x\(size)", 7),
            pad(entry.puzzle.difficulty.rawValue, 11),
            pad("\(entry.difficulty.score)", 7),
            pad("\(entry.puzzle.seed)", 7),
            profileName(entry.puzzle.profile),
        ].joined())
    }

    // The ramp is the point of the ladder, so say plainly whether it holds
    // instead of leaving it to be discovered in play.
    for cycle in 0..<cycles {
        let scores = numbered
            .filter { $0.cycle == cycle }
            .sorted { $0.position < $1.position }
            .map(\.difficulty.score)
        let rises = zip(scores, scores.dropFirst()).allSatisfy { $0 <= $1 }
        print("cycle \(cycle + 1) scores: \(scores.map(String.init).joined(separator: " -> "))"
            + (rises ? "" : "  [NOT MONOTONIC]"))
    }

    print(String(format: "\nGenerated %d levels in %.1fs", numbered.count, elapsed))

    if let swiftPath = options.swiftPath {
        let source = swiftSource(for: numbered, cycles: cycles)
        do {
            try source.write(toFile: swiftPath, atomically: true, encoding: .utf8)
            print("Wrote Swift fixtures to \(swiftPath)")
        } catch {
            FileHandle.standardError.write(Data("ladder: cannot write \(swiftPath) — \(error)\n".utf8))
            exit(1)
        }
    }

    if let jsonPath = options.jsonPath {
        let export = numbered.map { entry in
            LadderExportLevel(
                id: entry.id,
                index: entry.index + 1,
                cycle: entry.cycle + 1,
                position: entry.position,
                size: entry.puzzle.level.size,
                requestedDifficulty: entry.puzzle.difficulty.rawValue,
                profile: profileName(entry.puzzle.profile),
                seed: entry.puzzle.seed,
                score: entry.difficulty.score,
                tier: tierName(entry.difficulty.tier),
                regionIDs: entry.puzzle.level.regionIDs,
                solution: entry.puzzle.solution
                    .sorted { $0.row < $1.row }
                    .map { [$0.row, $0.column] }
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(export).write(to: URL(fileURLWithPath: jsonPath))
            print("Wrote JSON report to \(jsonPath)")
        } catch {
            FileHandle.standardError.write(Data("ladder: cannot write \(jsonPath) — \(error)\n".utf8))
            exit(1)
        }
    }

    exit(0)
}
