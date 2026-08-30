import XCTest
@testable import CatPuzzle
import CatPuzzleCore

final class BoardViewTests: XCTestCase {
    func testRegionPresentationCyclesForArbitraryRegionIDs() {
        XCTAssertEqual(CatPuzzleTheme.regionSymbol(for: 0), "circle.fill")
        XCTAssertEqual(CatPuzzleTheme.regionSymbol(for: 5), "hexagon.fill")
        XCTAssertEqual(CatPuzzleTheme.regionSymbol(for: 6), "circle.fill")
        XCTAssertEqual(CatPuzzleTheme.regionSymbol(for: -1), "hexagon.fill")
        XCTAssertEqual(CatPuzzleTheme.regionName(for: 0), "Region 1")
        XCTAssertEqual(CatPuzzleTheme.regionName(for: 7), "Region 2")
    }

    func testBoardLayoutMapsCellCentersAndRejectsGaps() {
        let layout = BoardLayout(side: 360, size: 6, padding: 8, spacing: 4)

        XCTAssertEqual(
            layout.position(at: CGPoint(x: 35, y: 35)),
            CellPosition(row: 0, column: 0)
        )
        XCTAssertNil(layout.position(at: CGPoint(x: 64, y: 35)))
        XCTAssertEqual(
            layout.position(at: CGPoint(x: 93, y: 35)),
            CellPosition(row: 0, column: 1)
        )
    }

    func testBoardLayoutSamplesEveryCellAlongFastDrag() {
        let layout = BoardLayout(side: 360, size: 6, padding: 8, spacing: 4)

        XCTAssertEqual(
            layout.positions(
                from: CGPoint(x: 35, y: 35),
                to: CGPoint(x: 325, y: 35)
            ),
            (0..<6).map { CellPosition(row: 0, column: $0) }
        )
    }

    func testDragModeIsDeterminedByStartingCellState() {
        XCTAssertEqual(BoardDragMode(startingFrom: .empty), .exclude)
        XCTAssertEqual(BoardDragMode(startingFrom: .excluded), .clear)
        XCTAssertEqual(BoardDragMode(startingFrom: .cat), .ignore)
    }
}
