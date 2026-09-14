import XCTest
@testable import CatPuzzleCore

final class ScreenshotBoardTranscriberTests: XCTestCase {
    private let regionIDs = BuiltInLevels.meadow.regionIDs

    func testReadsTheRegionLayoutOutOfAScreenshot() throws {
        let board = try ScreenshotBoardTranscriber.transcribe(
            SyntheticBoardImage().render(regionIDs: regionIDs)
        )

        XCTAssertEqual(board.size, 6)
        XCTAssertEqual(board.regionIDs, canonicalRegionIDs(regionIDs))
        XCTAssertEqual(board.regionColors.count, 6)
        XCTAssertTrue(board.states.allSatisfy { $0.allSatisfy { $0 == .empty } })
    }

    func testReadsCatsAndExclusionsDrawnOnTheBoard() throws {
        var states = [[CellState]](
            repeating: [CellState](repeating: .empty, count: 6),
            count: 6
        )
        states[0][1] = .cat
        states[3][0] = .cat
        states[0][0] = .excluded
        states[2][4] = .excluded
        states[5][5] = .excluded

        let board = try ScreenshotBoardTranscriber.transcribe(
            SyntheticBoardImage().render(regionIDs: regionIDs, states: states)
        )

        XCTAssertEqual(board.states, states)
    }

    /// A cat glyph is classified by covering the cell's axes, not by being
    /// dark: this app draws a *light* disc where the reference app draws a
    /// dark face, and a screenshot of either has to read the same.
    func testALightCatGlyphReadsAsACatJustLikeADarkOne() throws {
        var states = [[CellState]](
            repeating: [CellState](repeating: .empty, count: 6),
            count: 6
        )
        states[2][2] = .cat
        states[2][3] = .excluded

        var builder = SyntheticBoardImage()
        builder.catGlyph = .lightDisc
        let board = try ScreenshotBoardTranscriber.transcribe(
            builder.render(regionIDs: regionIDs, states: states)
        )

        XCTAssertEqual(board.states[2][2], .cat)
        XCTAssertEqual(board.states[2][3], .excluded)
    }

    func testHeaderContentAboveTheBoardIsIgnored() throws {
        var builder = SyntheticBoardImage()
        builder.headerHeight = 240
        builder.banner = true

        let board = try ScreenshotBoardTranscriber.transcribe(
            builder.render(regionIDs: regionIDs)
        )

        XCTAssertEqual(board.size, 6)
        XCTAssertEqual(board.regionIDs, canonicalRegionIDs(regionIDs))
    }

    func testReadsTheLargestSupportedBoard() throws {
        let large = (0..<12).map { row in (0..<12).map { ($0 + row) % 12 } }

        let board = try ScreenshotBoardTranscriber.transcribe(
            SyntheticBoardImage().render(regionIDs: large)
        )

        XCTAssertEqual(board.size, 12)
        XCTAssertEqual(board.regionIDs, canonicalRegionIDs(large))
    }

    func testAScreenshotWithNoBoardIsRejected() {
        let blank = try! ScreenshotPixels(
            width: 200,
            height: 400,
            rgb: [UInt8](repeating: 255, count: 200 * 400 * 3)
        )

        XCTAssertThrowsError(try ScreenshotBoardTranscriber.transcribe(blank)) {
            XCTAssertEqual(
                $0 as? ScreenshotTranscriptionError,
                .boardNotFound
            )
        }
    }

    /// One Region per row is a rule of the puzzle, so a board that reads back
    /// with any other number of colors was misread and must not be offered as
    /// a level.
    func testABoardWithTheWrongNumberOfColorsIsRejected() {
        // Region 5 repainted in region 4's color, leaving 5 colors on a 6×6
        // board — what a misread of two near-identical fills looks like.
        let wrong = regionIDs.map { $0.map { $0 == 5 ? 4 : $0 } }

        XCTAssertThrowsError(
            try ScreenshotBoardTranscriber.transcribe(
                SyntheticBoardImage().render(regionIDs: wrong)
            )
        ) {
            XCTAssertEqual(
                $0 as? ScreenshotTranscriptionError,
                .regionCountMismatch(regions: 5, size: 6)
            )
        }
    }

    func testABoardSmallerThanTheSupportedRangeIsRejected() {
        let tiny = [[0, 1], [1, 0]]
        var builder = SyntheticBoardImage()
        builder.margin = 8

        XCTAssertThrowsError(
            try ScreenshotBoardTranscriber.transcribe(
                builder.render(regionIDs: tiny)
            )
        ) {
            XCTAssertEqual(
                $0 as? ScreenshotTranscriptionError,
                .unsupportedBoardSize(2)
            )
        }
    }

    func testRunsBridgeShortGapsButNotLongOnes() {
        let flags = [true, false, true, false, false, false, true]

        XCTAssertEqual(
            ScreenshotBoardTranscriber.runs(flags, maxGap: 1),
            [0...2, 6...6]
        )
        XCTAssertEqual(
            ScreenshotBoardTranscriber.runs(flags, maxGap: 3),
            [0...6]
        )
        XCTAssertEqual(ScreenshotBoardTranscriber.runs([], maxGap: 1), [])
    }
}
