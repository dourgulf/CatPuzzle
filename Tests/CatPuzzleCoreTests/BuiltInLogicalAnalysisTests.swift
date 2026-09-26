import XCTest
@testable import CatPuzzleCore

final class BuiltInLogicalAnalysisTests: XCTestCase {
    func testShippedLevelsRemainUnique() {
        for fixture in BuiltInLevels.fixtures {
            XCTAssertEqual(
                PuzzleSolver.solve(level: fixture.level).result,
                .unique(fixture.solution),
                fixture.level.id
            )
        }
    }

    func testShippedLogicalAnalysisIsStable() {
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

    /// Every shipped level must be reachable by explainable deduction alone.
    /// The ladder is generated, so this asserts the contract rather than
    /// per-level numbers, which change whenever it is regenerated.
    func testShippedLevelsSolveWithoutAssumptions() {
        for fixture in BuiltInLevels.fixtures {
            let result = LogicalPuzzleSolver.solve(level: fixture.level, mode: .logicOnly)

            XCTAssertTrue(result.isSolved, fixture.level.id)
            XCTAssertEqual(result.report.statistics.assumptionCount, 0, fixture.level.id)
        }
    }
}

final class SampleLevelAnalysisTests: XCTestCase {
    func testSampleLevelsHaveExpectedLogicalAnalysis() {
        let expected: [String: (steps: Int, rounds: Int, score: Int, tier: DifficultyTier)] = [
            "meadow": (36, 6, 32, .medium),
            "river": (36, 6, 35, .medium),
            "terraces": (36, 6, 37, .hard),
        ]

        for fixture in SampleLevels.fixtures {
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

    /// The sample levels are fully solvable with basic row/column/Region
    /// singles alone; the advanced locked-set / common-attack / strong-link
    /// techniques must not spuriously fire on them. (Shipped ladder levels are
    /// allowed to need those techniques — that is what makes the later slots
    /// harder.)
    func testSampleLevelsDoNotNeedAdvancedTechniques() {
        for fixture in SampleLevels.fixtures {
            let result = LogicalPuzzleSolver.solve(level: fixture.level)
            let statistics = result.report.statistics

            XCTAssertTrue(result.isSolved, fixture.level.id)
            XCTAssertEqual(statistics.lockedPairCount, 0, fixture.level.id)
            XCTAssertEqual(statistics.lockedTripleCount, 0, fixture.level.id)
            XCTAssertEqual(statistics.commonAttackCount, 0, fixture.level.id)
            XCTAssertEqual(statistics.strongLinkDeductionCount, 0, fixture.level.id)
        }
    }
}
