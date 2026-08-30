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
        XCTAssertNotEqual(puzzleA.level.regionIDs, puzzleB.level.regionIDs)
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

    func testSolutionRegionsAreUnique() {
        var rng = SeededRandomNumberGenerator(seed: 123)
        let solution = PuzzleGenerator.generateSolution(size: 6, rng: &rng)
        let regionIDs = PuzzleGenerator.assignRegions(size: 6, solution: solution, strategy: .uniform, rng: &rng)
        let solutionRegions = solution.map { regionIDs[$0.row][$0.column] }
        XCTAssertEqual(Set(solutionRegions).count, 6)
    }

    // MARK: - Acceptance pipeline

    func testAcceptedPuzzlePassesLevelValidatorAndUniqueSolver() throws {
        let request = PuzzleGenerationRequest(seed: 4242, mode: .mainline, maxAttempts: 500)
        guard case let .generated(puzzle) = PuzzleGenerator.generate(request: request) else {
            return XCTFail("expected a generated puzzle")
        }
        try LevelValidator.validate(puzzle.level)
        XCTAssertEqual(
            PuzzleSolver.solve(level: puzzle.level).result,
            .unique(puzzle.solution)
        )
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
            + stats.rejectedCertificationInconclusive
            + stats.rejectedMultipleSolutions
            + stats.rejectedWrongUniqueSolution
            + stats.rejectedLogicalStuck
            + stats.rejectedNotChallenge
        XCTAssertEqual(rejectedTotal, stats.totalAttempts - stats.generatedCount)
    }

    // MARK: - JSON export round-trip

    func testJSONExportRoundTrips() throws {
        let request = PuzzleBatchGenerationRequest(startSeed: 5, count: 2, mode: .mainline, maxAttemptsPerPuzzle: 500)
        let result = PuzzleGenerator.generateBatch(request: request)
        let export = PuzzleBatchExport(result)

        let encoder = JSONEncoder()
        let data = try encoder.encode(export)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PuzzleBatchExport.self, from: data)

        XCTAssertFalse(export.puzzles.isEmpty)
        XCTAssertTrue(json.contains("\"regionIDs\""))
        XCTAssertFalse(json.contains("\"colorIDs\""))
        XCTAssertEqual(decoded, export)
    }
}
