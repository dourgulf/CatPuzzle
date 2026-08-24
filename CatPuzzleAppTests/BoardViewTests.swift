import XCTest
@testable import CatPuzzle
import CatPuzzleCore

final class BoardViewTests: XCTestCase {
    func testGroupPresentationCyclesForArbitraryColorIDs() {
        XCTAssertEqual(CatPuzzleTheme.groupSymbol(for: 0), "circle.fill")
        XCTAssertEqual(CatPuzzleTheme.groupSymbol(for: 5), "hexagon.fill")
        XCTAssertEqual(CatPuzzleTheme.groupSymbol(for: 6), "circle.fill")
        XCTAssertEqual(CatPuzzleTheme.groupSymbol(for: -1), "hexagon.fill")
        XCTAssertEqual(CatPuzzleTheme.groupName(for: 0), "Group 1")
        XCTAssertEqual(CatPuzzleTheme.groupName(for: 7), "Group 2")
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
