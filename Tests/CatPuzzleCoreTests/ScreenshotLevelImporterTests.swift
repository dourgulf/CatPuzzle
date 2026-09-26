import XCTest
@testable import CatPuzzleCore

final class ScreenshotLevelImporterTests: XCTestCase {
    private let fixture = SampleLevels.meadowFixture
    private var regionIDs: [[Int]] { fixture.level.regionIDs }

    private func blankStates() -> [[CellState]] {
        [[CellState]](
            repeating: [CellState](repeating: .empty, count: 6),
            count: 6
        )
    }

    private func pixels(_ states: [[CellState]]? = nil) -> ScreenshotPixels {
        SyntheticBoardImage().render(regionIDs: regionIDs, states: states)
    }

    func testImportsABlankBoardWithItsCertifiedSolution() throws {
        let imported = try ScreenshotLevelImporter.makeLevel(from: pixels())

        XCTAssertEqual(imported.level.size, 6)
        XCTAssertEqual(imported.level.catCount, 6)
        XCTAssertEqual(
            imported.level.regionIDs,
            canonicalRegionIDs(regionIDs)
        )
        XCTAssertEqual(
            Set(imported.fixture.solution),
            Set(fixture.solution)
        )
        XCTAssertFalse(imported.isAlreadySolved)
        XCTAssertFalse(imported.hasCorrections)
    }

    func testMarksOnTheScreenshotAreCarriedIntoTheImportedBoard() throws {
        var states = blankStates()
        states[0][1] = .cat
        states[0][0] = .excluded
        states[4][4] = .excluded

        let imported = try ScreenshotLevelImporter.makeLevel(from: pixels(states))

        XCTAssertEqual(imported.puzzle.state(atRow: 0, column: 1), .cat)
        XCTAssertEqual(imported.puzzle.state(atRow: 0, column: 0), .excluded)
        XCTAssertEqual(imported.puzzle.state(atRow: 4, column: 4), .excluded)
        XCTAssertFalse(imported.hasCorrections)
    }

    /// The whole point of importing marks is to keep playing, so the result
    /// has to be a board `GameEngine` will accept and can still be won.
    func testTheImportedBoardIsPlayableAndStillWinnable() throws {
        var states = blankStates()
        states[0][1] = .cat
        states[1][3] = .cat

        let imported = try ScreenshotLevelImporter.makeLevel(from: pixels(states))
        var engine = try GameEngine(
            fixture: imported.fixture,
            puzzle: imported.puzzle,
            mode: .challenge
        )

        for cat in imported.fixture.solution
        where engine.state.puzzle.state(atRow: cat.row, column: cat.column) != .cat {
            try engine.setState(.cat, atRow: cat.row, column: cat.column)
        }

        XCTAssertTrue(engine.state.isSolved)
        XCTAssertEqual(engine.state.mistakeCount, 0)
    }

    /// A screenshot can hold a cat the level's solution rules out — whoever
    /// took it had made a mistake, or one cell was misread. Dropping it keeps
    /// the import useful instead of handing the player a dead board.
    func testACatTheSolutionRulesOutIsDropped() throws {
        var states = blankStates()
        let wrong = CellPosition(row: 0, column: 3)
        states[wrong.row][wrong.column] = .cat

        let imported = try ScreenshotLevelImporter.makeLevel(from: pixels(states))

        XCTAssertEqual(imported.discardedCats, [wrong])
        XCTAssertTrue(imported.discardedExclusions.isEmpty)
        XCTAssertEqual(
            imported.puzzle.state(atRow: wrong.row, column: wrong.column),
            .empty
        )
        XCTAssertTrue(imported.hasCorrections)
    }

    func testAnExclusionOnASolutionCellIsDropped() throws {
        var states = blankStates()
        let cat = fixture.solution[2]
        states[cat.row][cat.column] = .excluded

        let imported = try ScreenshotLevelImporter.makeLevel(from: pixels(states))

        XCTAssertEqual(imported.discardedExclusions, [cat])
        XCTAssertEqual(
            imported.puzzle.state(atRow: cat.row, column: cat.column),
            .empty
        )
    }

    func testASolvedScreenshotImportsAsACompletedBoard() throws {
        var states = blankStates()
        for cat in fixture.solution {
            states[cat.row][cat.column] = .cat
        }

        let imported = try ScreenshotLevelImporter.makeLevel(from: pixels(states))

        XCTAssertTrue(imported.isAlreadySolved)
        XCTAssertTrue(
            try GameEngine(
                fixture: imported.fixture,
                puzzle: imported.puzzle,
                mode: .exploration
            ).state.isSolved
        )
    }

    /// A layout with more than one solution is a real puzzle to look at but
    /// not one this game can score, so the import refuses it rather than
    /// silently picking a branch.
    func testABoardWithSeveralSolutionsIsRejected() {
        let ambiguous = [
            [0, 0, 1, 1],
            [0, 0, 1, 1],
            [2, 2, 3, 3],
            [2, 2, 3, 3],
        ]

        XCTAssertThrowsError(
            try ScreenshotLevelImporter.makeLevel(
                from: SyntheticBoardImage().render(regionIDs: ambiguous)
            )
        ) {
            XCTAssertEqual(
                $0 as? ScreenshotImportError,
                .multipleSolutions
            )
        }
    }

    func testATranscriptionFailureIsReportedAsSuch() {
        let blank = try! ScreenshotPixels(
            width: 200,
            height: 400,
            rgb: [UInt8](repeating: 255, count: 200 * 400 * 3)
        )

        XCTAssertThrowsError(
            try ScreenshotLevelImporter.makeLevel(from: blank)
        ) {
            XCTAssertEqual(
                $0 as? ScreenshotImportError,
                .transcription(.boardNotFound)
            )
        }
    }
}
