import XCTest
@testable import CatPuzzleCore

final class PuzzleValidatorTests: XCTestCase {
    func testCatCanBePlacedInLegalCell() throws {
        let puzzle = try makePuzzle()

        XCTAssertTrue(PuzzleValidator.canPlaceCat(atRow: 0, column: 0, in: puzzle))
    }

    func testCatCannotBePlacedInOccupiedRow() throws {
        let puzzle = try makePuzzle(states: makeStates(cats: [(0, 4), (0, 5)]))

        XCTAssertFalse(PuzzleValidator.canPlaceCat(atRow: 0, column: 0, in: puzzle))
        XCTAssertTrue(PuzzleValidator.hasRowConflict(in: puzzle))
    }

    func testCatCannotBePlacedInOccupiedColumn() throws {
        let puzzle = try makePuzzle(states: makeStates(cats: [(4, 0), (5, 0)]))

        XCTAssertFalse(PuzzleValidator.canPlaceCat(atRow: 0, column: 0, in: puzzle))
        XCTAssertTrue(PuzzleValidator.hasColumnConflict(in: puzzle))
    }

    func testCatCannotBePlacedInOccupiedRegionEvenWhenCellsAreSeparated() throws {
        let placementPuzzle = try makePuzzle(states: makeStates(cats: [(1, 2)]))
        let conflictingPuzzle = try makePuzzle(
            states: makeStates(cats: [(0, 0), (1, 2)])
        )

        XCTAssertFalse(
            PuzzleValidator.canPlaceCat(atRow: 0, column: 0, in: placementPuzzle)
        )
        XCTAssertTrue(PuzzleValidator.hasRegionConflict(in: conflictingPuzzle))
    }

    func testHorizontalNeighborsConflict() throws {
        let puzzle = try makePuzzle(states: makeStates(cats: [(0, 0), (0, 1)]))

        XCTAssertTrue(PuzzleValidator.hasAdjacentCats(in: puzzle))
    }

    func testVerticalNeighborsConflict() throws {
        let puzzle = try makePuzzle(states: makeStates(cats: [(0, 0), (1, 0)]))

        XCTAssertTrue(PuzzleValidator.hasAdjacentCats(in: puzzle))
    }

    func testDiagonalNeighborsConflict() throws {
        let puzzle = try makePuzzle(states: makeStates(cats: [(1, 2), (2, 3)]))
        let placementPuzzle = try makePuzzle(states: makeStates(cats: [(1, 2)]))

        XCTAssertTrue(PuzzleValidator.hasAdjacentCats(in: puzzle))
        XCTAssertFalse(
            PuzzleValidator.canPlaceCat(atRow: 2, column: 3, in: placementPuzzle)
        )
    }

    func testCompleteValidSixBySixSolutionIsSolved() throws {
        let puzzle = try makePuzzle(
            states: makeStates(cats: [(0, 1), (1, 3), (2, 5), (3, 0), (4, 2), (5, 4)])
        )

        XCTAssertTrue(PuzzleValidator.isSolved(puzzle, catCount: 6))
    }

    func testIncompletePuzzleIsNotSolved() throws {
        let puzzle = try makePuzzle(
            states: makeStates(cats: [(0, 1), (1, 3), (2, 5), (3, 0), (4, 2)])
        )

        XCTAssertFalse(PuzzleValidator.isSolved(puzzle, catCount: 6))
    }

    func testCatCannotBePlacedOutsideBoard() throws {
        let puzzle = try makePuzzle()

        XCTAssertFalse(PuzzleValidator.canPlaceCat(atRow: -1, column: 0, in: puzzle))
        XCTAssertFalse(PuzzleValidator.canPlaceCat(atRow: 0, column: 6, in: puzzle))
    }

    private func makePuzzle(states: [[CellState]]? = nil) throws -> Puzzle {
        try Puzzle(
            size: 6,
            regionIDs: [
                [0, 0, 0, 1, 1, 1],
                [0, 0, 0, 1, 1, 1],
                [2, 2, 2, 3, 3, 3],
                [2, 2, 2, 3, 3, 3],
                [4, 4, 4, 5, 5, 5],
                [4, 4, 4, 5, 5, 5],
            ],
            states: states
        )
    }

    private func makeStates(cats: [(Int, Int)]) -> [[CellState]] {
        var states = Array(
            repeating: Array(repeating: CellState.empty, count: 6),
            count: 6
        )
        for (row, column) in cats {
            states[row][column] = .cat
        }
        return states
    }
}
