import XCTest
@testable import CatPuzzleCore

final class BuiltInLogicalAnalysisTests: XCTestCase {
    func testBuiltInLevelsRemainUnique() {
        for fixture in BuiltInLevels.fixtures {
            XCTAssertEqual(
                PuzzleSolver.solve(level: fixture.level),
                .unique(fixture.solution),
                fixture.level.id
            )
        }
    }

    func testBuiltInLogicalAnalysisIsStable() {
        for fixture in BuiltInLevels.fixtures {
            let first = LogicalPuzzleSolver.solve(level: fixture.level)
            let second = LogicalPuzzleSolver.solve(level: fixture.level)

            XCTAssertEqual(first, second, fixture.level.id)
            XCTAssertEqual(
                PuzzleDifficultyAnalyzer.analyze(first.report),
                PuzzleDifficultyAnalyzer.analyze(second.report),
                fixture.level.id
            )
        }
    }

    func testBuiltInLevelsHaveExpectedLogicalAnalysis() {
        let expected: [String: (steps: Int, rounds: Int, score: Int, tier: DifficultyTier)] = [
            "meadow": (36, 6, 32, .medium),
            "river": (36, 6, 35, .medium),
            "terraces": (36, 6, 37, .hard),
        ]

        for fixture in BuiltInLevels.fixtures {
            let result = LogicalPuzzleSolver.solve(level: fixture.level)
            let difficulty = PuzzleDifficultyAnalyzer.analyze(result.report)
            guard let expectedAnalysis = expected[fixture.level.id] else {
                return XCTFail("Missing expected analysis for \(fixture.level.id)")
            }

            XCTAssertTrue(result.isSolved, fixture.level.id)
            XCTAssertEqual(result.report.steps.count, expectedAnalysis.steps)
            XCTAssertEqual(
                result.report.statistics.deductionRounds,
                expectedAnalysis.rounds
            )
            XCTAssertEqual(result.report.statistics.assumptionCount, 0)
            XCTAssertEqual(difficulty.score, expectedAnalysis.score)
            XCTAssertEqual(difficulty.tier, expectedAnalysis.tier)
        }
    }
}
