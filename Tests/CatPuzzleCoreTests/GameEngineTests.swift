import XCTest
@testable import CatPuzzleCore

final class GameEngineTests: XCTestCase {
    func testEngineStartsWithEmptyGameState() throws {
        let engine = try GameEngine(level: BuiltInLevels.meadow)

        XCTAssertEqual(engine.state.level, BuiltInLevels.meadow)
        XCTAssertTrue(engine.state.puzzle.states.allSatisfy { $0 == .empty })
        XCTAssertFalse(engine.state.isSolved)
        XCTAssertFalse(engine.canUndo)
    }

    func testToggleCyclesThroughAllCellStates() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)

        XCTAssertEqual(
            try engine.toggleCell(atRow: 0, column: 0),
            .excluded
        )
        XCTAssertEqual(try engine.toggleCell(atRow: 0, column: 0), .cat)
        XCTAssertEqual(try engine.toggleCell(atRow: 0, column: 0), .empty)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 0), .empty)
        XCTAssertTrue(engine.canUndo)
    }

    func testIllegalCatPlacementIsRejectedWithoutChangingState() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        try engine.toggleCell(atRow: 0, column: 0)
        try engine.toggleCell(atRow: 0, column: 0)
        try engine.toggleCell(atRow: 0, column: 4)

        XCTAssertThrowsError(
            try engine.toggleCell(atRow: 0, column: 4)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .illegalCatPlacement)
        }
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 0), .cat)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 4), .excluded)
        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 4), .empty)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 0), .cat)
    }

    func testUndoRestoresSuccessfulMovesInReverseOrder() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        try engine.toggleCell(atRow: 0, column: 0)
        try engine.toggleCell(atRow: 1, column: 1)

        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle.state(atRow: 1, column: 1), .empty)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 0), .excluded)
        XCTAssertTrue(engine.canUndo)

        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 0), .empty)
        XCTAssertFalse(engine.canUndo)
        XCTAssertFalse(engine.undo())
    }

    func testRestartRestoresInitialStateAndClearsHistory() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        try engine.toggleCell(atRow: 0, column: 0)
        try engine.toggleCell(atRow: 0, column: 0)
        try engine.toggleCell(atRow: 2, column: 2)

        engine.restart()

        XCTAssertTrue(engine.state.puzzle.states.allSatisfy { $0 == .empty })
        XCTAssertFalse(engine.state.isSolved)
        XCTAssertFalse(engine.canUndo)
        XCTAssertFalse(engine.undo())
    }

    func testCompletingValidMovesUpdatesSolvedState() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        let catPositions = [
            (0, 1), (1, 3), (2, 5), (3, 0), (4, 2), (5, 4),
        ]

        for (row, column) in catPositions {
            try engine.toggleCell(atRow: row, column: column)
            try engine.toggleCell(atRow: row, column: column)
        }

        XCTAssertTrue(engine.state.isSolved)
    }

    func testInvalidCoordinateDoesNotCreateUndoHistory() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)

        XCTAssertThrowsError(
            try engine.toggleCell(atRow: -1, column: 0)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .invalidCell)
        }
        XCTAssertFalse(engine.canUndo)
    }
}
