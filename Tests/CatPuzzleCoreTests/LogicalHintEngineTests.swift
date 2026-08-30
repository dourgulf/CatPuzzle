import XCTest
@testable import CatPuzzleCore

final class LogicalHintEngineTests: XCTestCase {
    func testNextHintPlacesOnlyTheDirectlyDeducedCat() throws {
        let level = BuiltInLevels.meadow
        var puzzle = try level.makePuzzle()
        for column in 0..<level.size where column != 1 {
            try puzzle.setState(.excluded, atRow: 0, column: column)
        }

        let hint = try XCTUnwrap(
            LogicalHintEngine.nextHint(level: level, puzzle: puzzle)
        )

        XCTAssertEqual(
            hint,
            LogicalHint(
                actions: [.placeCat(CellPosition(row: 0, column: 1))],
                reason: .onlyCandidateInRow(row: 0)
            )
        )
    }

    func testHintFromConfirmedCatGroupsOneTrueExclusionReason() throws {
        let level = BuiltInLevels.meadow
        var puzzle = try level.makePuzzle()
        try puzzle.setState(.cat, atRow: 0, column: 1)

        let hint = try XCTUnwrap(
            LogicalHintEngine.nextHint(level: level, puzzle: puzzle)
        )

        XCTAssertEqual(hint.reason, .rowAlreadyHasCat(row: 0))
        XCTAssertFalse(hint.actions.isEmpty)
        XCTAssertTrue(hint.actions.allSatisfy {
            if case .exclude = $0 { return true }
            return false
        })
        XCTAssertTrue(hint.positions.allSatisfy { $0.row == 0 })
    }

    func testStuckBoardDoesNotPeekAtACompleteSolution() throws {
        let level = LevelDefinition(
            id: "hint-stuck",
            size: 4,
            catCount: 4,
            maxMistakes: 5,
            regionIDs: [
                [0, 0, 0, 0],
                [1, 1, 1, 1],
                [2, 2, 2, 2],
                [3, 3, 3, 3],
            ]
        )

        XCTAssertNil(
            LogicalHintEngine.nextHint(
                level: level,
                puzzle: try level.makePuzzle()
            )
        )
    }

    func testApplyingMultiCellHintIsOneUndoStep() throws {
        let level = BuiltInLevels.meadow
        var startingPuzzle = try level.makePuzzle()
        try startingPuzzle.setState(.cat, atRow: 0, column: 1)
        let hint = try XCTUnwrap(
            LogicalHintEngine.nextHint(level: level, puzzle: startingPuzzle)
        )
        XCTAssertGreaterThan(hint.actions.count, 1)
        var engine = try GameEngine(level: level, puzzle: startingPuzzle)

        try engine.applyHint(hint)

        XCTAssertNotEqual(engine.state.puzzle, startingPuzzle)
        XCTAssertTrue(engine.canUndo)
        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle, startingPuzzle)
        XCTAssertFalse(engine.undo())
    }
}
