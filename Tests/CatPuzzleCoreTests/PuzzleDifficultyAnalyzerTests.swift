import XCTest
@testable import CatPuzzleCore

final class PuzzleDifficultyAnalyzerTests: XCTestCase {
    func testDifficultyScoreIsDeterministic() {
        let report = LogicalPuzzleSolver.solve(level: BuiltInLevels.meadow).report

        XCTAssertEqual(
            PuzzleDifficultyAnalyzer.analyze(report),
            PuzzleDifficultyAnalyzer.analyze(report)
        )
    }

    func testAssumptionPuzzleIsAlwaysChallengeTier() {
        let report = report(assumptionCount: 1, maxAssumptionDepth: 1)

        XCTAssertEqual(PuzzleDifficultyAnalyzer.analyze(report).tier, .challenge)
    }

    func testLogicOnlyPuzzleIsNeverChallengeTier() {
        let report = report(assumptionCount: 0, maxAssumptionDepth: 0)

        XCTAssertNotEqual(PuzzleDifficultyAnalyzer.analyze(report).tier, .challenge)
    }

    func testAdvancedTechniquesIncreaseScore() {
        let baseline = report(assumptionCount: 0, maxAssumptionDepth: 0)
        let withAdvanced = report(
            assumptionCount: 0,
            maxAssumptionDepth: 0,
            lockedPairCount: 1,
            lockedTripleCount: 1,
            commonAttackCount: 1,
            strongLinkDeductionCount: 1
        )

        let baseScore = PuzzleDifficultyAnalyzer.analyze(baseline).score
        let advancedScore = PuzzleDifficultyAnalyzer.analyze(withAdvanced).score

        // +4 (locked pair) + 7 (locked triple) + 5 (common attack) + 8 (strong link)
        XCTAssertEqual(advancedScore - baseScore, 24)
    }

    private func report(
        assumptionCount: Int,
        maxAssumptionDepth: Int,
        lockedPairCount: Int = 0,
        lockedTripleCount: Int = 0,
        commonAttackCount: Int = 0,
        strongLinkDeductionCount: Int = 0
    ) -> LogicalSolveReport {
        LogicalSolveReport(
            steps: [],
            finalBoard: LogicalBoardSnapshot(size: 1, states: [.confirmedCat]),
            statistics: LogicalSolveStatistics(
                placedCats: 1,
                exclusions: 0,
                propagationSteps: 0,
                deductionRounds: 1,
                assumptionCount: assumptionCount,
                maxAssumptionDepth: maxAssumptionDepth,
                lockedPairCount: lockedPairCount,
                lockedTripleCount: lockedTripleCount,
                commonAttackCount: commonAttackCount,
                strongLinkDeductionCount: strongLinkDeductionCount
            )
        )
    }
}
