import XCTest
import Foundation
@testable import CatPuzzleCore

final class PuzzleGeneratorTests: XCTestCase {
    // MARK: - Determinism

    func testSameSeedGeneratesSameSolution() {
        var rngA = SeededRandomNumberGenerator(seed: 999)
        var rngB = SeededRandomNumberGenerator(seed: 999)
        let solutionA = PuzzleGenerator.generateSolution(size: 6, rng: &rngA)
        let solutionB = PuzzleGenerator.generateSolution(size: 6, rng: &rngB)
        XCTAssertEqual(solutionA, solutionB)
    }

    func testSameSeedGeneratesSameLevel() {
        let request = PuzzleGenerationRequest(seed: 4242, mode: .mainline, maxAttempts: 500)
        guard case let .generated(puzzleA) = PuzzleGenerator.generate(request: request),
              case let .generated(puzzleB) = PuzzleGenerator.generate(request: request) else {
            return XCTFail("expected both runs to generate a puzzle")
        }
        XCTAssertEqual(puzzleA.level, puzzleB.level)
        XCTAssertEqual(puzzleA.solution, puzzleB.solution)
        XCTAssertEqual(puzzleA.generationMetadata, puzzleB.generationMetadata)
    }

    func testDifferentSeedsUsuallyGenerateDifferentCandidates() {
        let requestA = PuzzleGenerationRequest(seed: 1, mode: .mainline, maxAttempts: 500)
        let requestB = PuzzleGenerationRequest(seed: 2, mode: .mainline, maxAttempts: 500)
        guard case let .generated(puzzleA) = PuzzleGenerator.generate(request: requestA),
              case let .generated(puzzleB) = PuzzleGenerator.generate(request: requestB) else {
            return XCTFail("expected both seeds to generate a puzzle")
        }
        XCTAssertNotEqual(puzzleA.level.colorIDs, puzzleB.level.colorIDs)
    }

    // MARK: - Solution shape

    func testGeneratedSolutionEachRowAndColumnUnique() {
        var rng = SeededRandomNumberGenerator(seed: 123)
        let solution = PuzzleGenerator.generateSolution(size: 6, rng: &rng)
        XCTAssertEqual(Set(solution.map(\.row)).count, 6)
        XCTAssertEqual(Set(solution.map(\.column)).count, 6)
    }

    func testGeneratedSolutionHasNoAdjacentCats() {
        var rng = SeededRandomNumberGenerator(seed: 123)
        let solution = PuzzleGenerator.generateSolution(size: 6, rng: &rng).sorted { $0.row < $1.row }
        for index in 1..<solution.count {
            XCTAssertGreaterThan(abs(solution[index].column - solution[index - 1].column), 1)
        }
    }

    func testSolutionColorsAreUnique() {
        var rng = SeededRandomNumberGenerator(seed: 123)
        let solution = PuzzleGenerator.generateSolution(size: 6, rng: &rng)
        let colorIDs = PuzzleGenerator.assignColors(size: 6, solution: solution, strategy: .uniform, rng: &rng)
        let solutionColors = solution.map { colorIDs[$0.row][$0.column] }
        XCTAssertEqual(Set(solutionColors).count, 6)
    }

    // MARK: - Difficulty onboarding color strategies

    func testSingletonColorStrategyReservesExactlyOneColorToOneCell() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        let solution = PuzzleGenerator.generateSolution(size: 6, rng: &rng)
        let colorIDs = PuzzleGenerator.assignColors(size: 6, solution: solution, strategy: .singletonColor, rng: &rng)

        let counts = colorIDs.flatMap { $0 }.reduce(into: [Int: Int]()) { counts, colorID in
            counts[colorID, default: 0] += 1
        }
        XCTAssertTrue(counts.values.contains(1), "expected some color to appear exactly once")
    }

    func testConfinedColorPairStrategyConfinesTwoColorsToTwoRows() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        let solution = PuzzleGenerator.generateSolution(size: 6, rng: &rng)
        let colorIDs = PuzzleGenerator.assignColors(
            size: 6,
            solution: solution,
            strategy: .confinedColorPair(axis: .rows),
            rng: &rng
        )

        XCTAssertTrue(hasColorPairConfinedToTwoLines(colorIDs: colorIDs, size: 6, byRow: true))
    }

    func testConfinedColorPairStrategyConfinesTwoColorsToTwoColumns() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        let solution = PuzzleGenerator.generateSolution(size: 6, rng: &rng)
        let colorIDs = PuzzleGenerator.assignColors(
            size: 6,
            solution: solution,
            strategy: .confinedColorPair(axis: .columns),
            rng: &rng
        )

        XCTAssertTrue(hasColorPairConfinedToTwoLines(colorIDs: colorIDs, size: 6, byRow: false))
    }

    private func hasColorPairConfinedToTwoLines(colorIDs: [[Int]], size: Int, byRow: Bool) -> Bool {
        for colorA in 0..<size {
            for colorB in (colorA + 1)..<size {
                var lines: Set<Int> = []
                for row in 0..<size {
                    for column in 0..<size where colorIDs[row][column] == colorA || colorIDs[row][column] == colorB {
                        lines.insert(byRow ? row : column)
                    }
                }
                if lines.count == 2 { return true }
            }
        }
        return false
    }

    // MARK: - Difficulty tier filtering

    func testTargetTiersOnlyAcceptsMatchingTier() {
        let request = PuzzleGenerationRequest(
            seed: 1,
            mode: .mainline,
            maxAttempts: 20000,
            colorAssignmentStrategy: .singletonColor,
            targetTiers: [.medium]
        )
        guard case let .generated(puzzle) = PuzzleGenerator.generate(request: request) else {
            return XCTFail("expected a generated puzzle matching the requested tier")
        }
        XCTAssertEqual(puzzle.difficulty.tier, .medium)
    }

    func testTargetTiersExhaustsWhenModeCanNeverProduceThatTier() {
        // Mainline candidates always have assumptionCount == 0, so their
        // tier can never be .challenge — this always exhausts regardless
        // of seed, a deterministic way to exercise the difficultyMismatch
        // rejection path. Not every attempt reaches difficulty analysis
        // (some are rejected earlier for having multiple solutions, or for
        // getting logically stuck), so this only asserts the exhaustion
        // itself and that the new rejection path fired at least once.
        let request = PuzzleGenerationRequest(
            seed: 1,
            mode: .mainline,
            maxAttempts: 10,
            targetTiers: [.challenge]
        )
        guard case let .exhausted(report) = PuzzleGenerator.generate(request: request) else {
            return XCTFail("expected generation to exhaust its attempts")
        }
        XCTAssertEqual(report.attempts, 10)
        XCTAssertGreaterThan(report.rejections.difficultyMismatch, 0)
    }

    // MARK: - Uniqueness repair (8x8-10x10 support)

    /// Plain random coloring's odds of landing on a unique solution
    /// collapse past ~7x7 — confirmed empirically: 500/500 `.uniform`
    /// attempts at size 8 were rejected for having multiple solutions, with
    /// no repair. `repairForUniqueSolution` is what makes larger boards
    /// practical, so this directly proves it converges at exactly the
    /// sizes plain rejection sampling could not handle.
    func testRepairForUniqueSolutionAchievesUniquenessAtLargerSizes() {
        for size in [8, 9, 10] {
            var rng = SeededRandomNumberGenerator(seed: 1)
            let solution = PuzzleGenerator.generateSolution(size: size, rng: &rng)
            let colorIDs = PuzzleGenerator.assignColors(
                size: size,
                solution: solution,
                strategy: .uniform,
                rng: &rng
            )
            let level = LevelDefinition(
                id: "repair-test-\(size)",
                size: size,
                catCount: size,
                maxMistakes: 5,
                colorIDs: colorIDs
            )

            guard let repaired = PuzzleGenerator.repairForUniqueSolution(
                level: level,
                solution: solution,
                maxRepairAttempts: 300
            ) else {
                return XCTFail("expected repair to converge for size \(size)")
            }
            XCTAssertEqual(PuzzleSolver.solve(level: repaired), .unique(solution), "size \(size)")
        }
    }

    func testRepairNeverModifiesSolutionCellColors() {
        var rng = SeededRandomNumberGenerator(seed: 1)
        let solution = PuzzleGenerator.generateSolution(size: 9, rng: &rng)
        let colorIDs = PuzzleGenerator.assignColors(size: 9, solution: solution, strategy: .uniform, rng: &rng)
        let level = LevelDefinition(id: "repair-preserve", size: 9, catCount: 9, maxMistakes: 5, colorIDs: colorIDs)

        guard let repaired = PuzzleGenerator.repairForUniqueSolution(
            level: level,
            solution: solution,
            maxRepairAttempts: 300
        ) else {
            return XCTFail("expected repair to converge")
        }

        for position in solution {
            XCTAssertEqual(
                repaired.colorIDs[position.row][position.column],
                colorIDs[position.row][position.column]
            )
        }
    }

    func testRepairWithZeroAttemptsReturnsNilWithoutCrashing() {
        var rng = SeededRandomNumberGenerator(seed: 1)
        let solution = PuzzleGenerator.generateSolution(size: 8, rng: &rng)
        let colorIDs = PuzzleGenerator.assignColors(size: 8, solution: solution, strategy: .uniform, rng: &rng)
        let level = LevelDefinition(id: "repair-zero", size: 8, catCount: 8, maxMistakes: 5, colorIDs: colorIDs)

        XCTAssertNil(PuzzleGenerator.repairForUniqueSolution(
            level: level,
            solution: solution,
            maxRepairAttempts: 0
        ))
    }

    // MARK: - Acceptance pipeline

    func testAcceptedPuzzlePassesLevelValidatorAndUniqueSolver() throws {
        let request = PuzzleGenerationRequest(seed: 4242, mode: .mainline, maxAttempts: 500)
        guard case let .generated(puzzle) = PuzzleGenerator.generate(request: request) else {
            return XCTFail("expected a generated puzzle")
        }
        try LevelValidator.validate(puzzle.level)
        XCTAssertEqual(PuzzleSolver.solve(level: puzzle.level), .unique(puzzle.solution))
    }

    // MARK: - Mainline mode

    func testMainlineCandidateIsSolvedByLogicOnlyWithNoAssumptions() {
        let request = PuzzleGenerationRequest(seed: 4242, mode: .mainline, maxAttempts: 500)
        guard case let .generated(puzzle) = PuzzleGenerator.generate(request: request) else {
            return XCTFail("expected a generated puzzle")
        }
        let result = LogicalPuzzleSolver.solve(level: puzzle.level, mode: .logicOnly)
        XCTAssertTrue(result.isSolved)
        XCTAssertEqual(result.report.statistics.assumptionCount, 0)
        XCTAssertEqual(puzzle.logicalReport.statistics.assumptionCount, 0)
    }

    // MARK: - Challenge mode

    func testChallengeCandidateIsStuckLogicOnlyButSolvedByChallenge() {
        let request = PuzzleGenerationRequest(seed: 7, mode: .challenge(maxAssumptionDepth: 3), maxAttempts: 2000)
        guard case let .generated(puzzle) = PuzzleGenerator.generate(request: request) else {
            return XCTFail("expected a generated challenge puzzle")
        }
        let logicOnly = LogicalPuzzleSolver.solve(level: puzzle.level, mode: .logicOnly)
        XCTAssertFalse(logicOnly.isSolved)

        let challenge = LogicalPuzzleSolver.solve(level: puzzle.level, mode: .challenge(maxAssumptionDepth: 3))
        XCTAssertTrue(challenge.isSolved)
        XCTAssertGreaterThan(challenge.report.statistics.assumptionCount, 0)
        XCTAssertLessThanOrEqual(challenge.report.statistics.maxAssumptionDepth, 3)
        XCTAssertGreaterThan(puzzle.logicalReport.statistics.assumptionCount, 0)
    }

    // MARK: - Attempt / batch bookkeeping

    func testMaxAttemptsIsRespectedWhenPipelineCannotSucceed() {
        // maxAssumptionDepth: 0 can never be satisfied by a genuine
        // challenge candidate (any assumption has depth >= 1), so this
        // always exhausts regardless of seed — a deterministic way to
        // exercise the exhausted path without depending on RNG luck.
        let request = PuzzleGenerationRequest(seed: 99, mode: .challenge(maxAssumptionDepth: 0), maxAttempts: 5)
        guard case let .exhausted(report) = PuzzleGenerator.generate(request: request) else {
            return XCTFail("expected generation to exhaust its attempts")
        }
        XCTAssertEqual(report.attempts, 5)
        XCTAssertEqual(report.seed, 99)
    }

    func testBatchRequestedCountIsRespected() {
        let request = PuzzleBatchGenerationRequest(startSeed: 1, count: 4, mode: .mainline, maxAttemptsPerPuzzle: 500)
        let result = PuzzleGenerator.generateBatch(request: request)
        XCTAssertEqual(result.statistics.requestedCount, 4)
        XCTAssertLessThanOrEqual(result.generated.count, 4)
        XCTAssertEqual(result.generated.count, result.statistics.generatedCount)
    }

    func testBatchGenerationIsDeterministic() {
        let request = PuzzleBatchGenerationRequest(startSeed: 5, count: 4, mode: .mainline, maxAttemptsPerPuzzle: 500)
        let resultA = PuzzleGenerator.generateBatch(request: request)
        let resultB = PuzzleGenerator.generateBatch(request: request)
        XCTAssertEqual(resultA, resultB)
    }

    func testRejectionStatisticsAccountForEveryAttempt() {
        let request = PuzzleBatchGenerationRequest(startSeed: 5, count: 6, mode: .mainline, maxAttemptsPerPuzzle: 500)
        let result = PuzzleGenerator.generateBatch(request: request)
        let stats = result.statistics
        let rejectedTotal = stats.rejectedInvalidLevel
            + stats.rejectedNoSolution
            + stats.rejectedMultipleSolutions
            + stats.rejectedWrongUniqueSolution
            + stats.rejectedLogicalStuck
            + stats.rejectedNotChallenge
            + stats.rejectedDifficultyMismatch
        XCTAssertEqual(rejectedTotal, stats.totalAttempts - stats.generatedCount)
    }

    // MARK: - JSON export round-trip

    func testJSONExportRoundTrips() throws {
        let request = PuzzleBatchGenerationRequest(startSeed: 5, count: 2, mode: .mainline, maxAttemptsPerPuzzle: 500)
        let result = PuzzleGenerator.generateBatch(request: request)
        let export = PuzzleBatchExport(result)

        let encoder = JSONEncoder()
        let data = try encoder.encode(export)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PuzzleBatchExport.self, from: data)

        XCTAssertEqual(decoded, export)
    }
}
