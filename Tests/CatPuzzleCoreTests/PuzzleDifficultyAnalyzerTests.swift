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

    /// `placedCats`, `deductionRounds`, and `propagationSteps` are each
    /// exactly `size` for a report shaped like a pure singles-only cascade
    /// (one deduction round places one cat, one propagation event per
    /// placement) — regardless of board size. Before size-normalization,
    /// their contribution to `score` grew linearly with `size` alone, so
    /// the same logically-simple solve shape scored higher — and landed in
    /// a harder tier — purely because the board was bigger. This asserts
    /// that no longer happens: the same solve shape at two very different
    /// sizes must land on the identical score and tier.
    func testStructuralBaselineScoreIsSizeInvariant() {
        let small = shapedReport(size: 6)
        let large = shapedReport(size: 10)

        let smallDifficulty = PuzzleDifficultyAnalyzer.analyze(small)
        let largeDifficulty = PuzzleDifficultyAnalyzer.analyze(large)

        XCTAssertEqual(smallDifficulty.score, largeDifficulty.score)
        XCTAssertEqual(smallDifficulty.tier, largeDifficulty.tier)
    }

    private func shapedReport(size: Int) -> LogicalSolveReport {
        LogicalSolveReport(
            steps: [],
            finalBoard: LogicalBoardSnapshot(size: size, states: []),
            statistics: LogicalSolveStatistics(
                placedCats: size,
                exclusions: 0,
                propagationSteps: size,
                deductionRounds: size,
                assumptionCount: 0,
                maxAssumptionDepth: 0
            )
        )
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
