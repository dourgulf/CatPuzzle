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

    private func report(
        assumptionCount: Int,
        maxAssumptionDepth: Int
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
                maxAssumptionDepth: maxAssumptionDepth
            )
        )
    }
}
