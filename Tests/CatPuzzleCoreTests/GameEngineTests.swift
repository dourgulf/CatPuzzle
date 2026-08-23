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

    func testSetStateCanExcludeCellDirectly() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)

        try engine.setState(.excluded, atRow: 2, column: 3)

        XCTAssertEqual(engine.state.puzzle.state(atRow: 2, column: 3), .excluded)
        XCTAssertTrue(engine.canUndo)
    }

    func testSetStateCanPlaceLegalCatDirectly() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)

        try engine.setState(.cat, atRow: 2, column: 3)

        XCTAssertEqual(engine.state.puzzle.state(atRow: 2, column: 3), .cat)
        XCTAssertTrue(engine.canUndo)
    }

    func testSettingSameStateIsNoOpWithoutUndoHistory() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        try engine.setState(.excluded, atRow: 2, column: 3)
        let puzzleBeforeNoOp = engine.state.puzzle

        try engine.setState(.excluded, atRow: 2, column: 3)

        XCTAssertEqual(engine.state.puzzle, puzzleBeforeNoOp)
        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle.state(atRow: 2, column: 3), .empty)
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
        try engine.setState(.cat, atRow: 0, column: 0)
        try engine.setState(.excluded, atRow: 0, column: 4)
        let puzzleBeforeFailure = engine.state.puzzle

        XCTAssertThrowsError(
            try engine.setState(.cat, atRow: 0, column: 4)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .illegalCatPlacement)
        }
        XCTAssertEqual(engine.state.puzzle, puzzleBeforeFailure)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 0), .cat)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 4), .excluded)
        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 4), .empty)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 0), .cat)
    }

    func testUndoRestoresSuccessfulMovesInReverseOrder() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        try engine.setState(.excluded, atRow: 0, column: 0)
        try engine.setState(.excluded, atRow: 1, column: 1)

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
        try engine.setState(.cat, atRow: 0, column: 0)
        try engine.setState(.excluded, atRow: 2, column: 2)

        engine.restart()

        XCTAssertTrue(engine.state.puzzle.states.allSatisfy { $0 == .empty })
        XCTAssertFalse(engine.state.isSolved)
        XCTAssertFalse(engine.canUndo)
        XCTAssertFalse(engine.undo())
    }

    func testCompletingValidMovesUpdatesSolvedState() throws {
        let fixture = BuiltInLevels.meadowFixture
        var engine = try GameEngine(level: fixture.level)

        for position in fixture.solution {
            try engine.setState(
                .cat,
                atRow: position.row,
                column: position.column
            )
        }

        XCTAssertTrue(engine.state.isSolved)
    }

    func testInvalidCoordinateDoesNotCreateUndoHistory() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        try engine.setState(.excluded, atRow: 1, column: 1)
        let puzzleBeforeFailure = engine.state.puzzle

        XCTAssertThrowsError(
            try engine.setState(.excluded, atRow: -1, column: 0)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .invalidCell)
        }
        XCTAssertEqual(engine.state.puzzle, puzzleBeforeFailure)
        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle.state(atRow: 1, column: 1), .empty)
        XCTAssertFalse(engine.canUndo)
    }
}
