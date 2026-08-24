import XCTest
@testable import CatPuzzle
import CatPuzzleCore

final class BoardViewTests: XCTestCase {
    func testCellBordersIdentifyOuterAndColorEdges() throws {
        let puzzle = try BuiltInLevels.meadow.makePuzzle()

        XCTAssertEqual(
            CellBorders.resolve(in: puzzle, row: 0, column: 0),
            CellBorders(top: true, bottom: true, leading: true, trailing: true)
        )
        XCTAssertEqual(
            CellBorders.resolve(in: puzzle, row: 0, column: 2),
            CellBorders(top: true, bottom: false, leading: true, trailing: false)
        )
    }
}
