import XCTest
@testable import CatPuzzle
import CatPuzzleCore

@MainActor
final class GameViewModelTests: XCTestCase {
    func testInitializationExposesSelectedLevel() throws {
        let viewModel = try GameViewModel(level: BuiltInLevels.river)

        XCTAssertEqual(viewModel.level.id, "river")
        XCTAssertEqual(viewModel.puzzle.size, 6)
        XCTAssertFalse(viewModel.canUndo)
        XCTAssertFalse(viewModel.isSolved)
        XCTAssertFalse(viewModel.isFailed)
        XCTAssertEqual(viewModel.mistakeCount, 0)
        XCTAssertEqual(viewModel.remainingMistakes, 5)
        XCTAssertEqual(viewModel.mistakeSummary, "Mistakes: 0 / 5")
    }

    func testSingleTapIntentTogglesExcludedState() throws {
        let viewModel = try GameViewModel()

        viewModel.toggleExcluded(atRow: 0, column: 0)
        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 0), .excluded)
        XCTAssertTrue(viewModel.canUndo)

        viewModel.toggleExcluded(atRow: 0, column: 0)
        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 0), .empty)

        viewModel.toggleCat(atRow: 0, column: 0)
        viewModel.toggleExcluded(atRow: 0, column: 0)
        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 0), .cat)
    }

    func testDoubleTapIntentTogglesCatState() throws {
        let viewModel = try GameViewModel()
        viewModel.toggleExcluded(atRow: 0, column: 1)

        viewModel.toggleCat(atRow: 0, column: 1)
        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 1), .cat)

        viewModel.toggleCat(atRow: 0, column: 1)
        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 1), .empty)
    }

    func testExcludeDragMarksCellsWithoutChangingCats() throws {
        let viewModel = try GameViewModel()
        viewModel.toggleCat(atRow: 0, column: 1)
        viewModel.toggleExcluded(atRow: 0, column: 2)

        viewModel.setExcludedDuringDrag(true, atRow: 0, column: 0)
        viewModel.setExcludedDuringDrag(true, atRow: 0, column: 1)
        viewModel.setExcludedDuringDrag(true, atRow: 0, column: 2)

        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 0), .excluded)
        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 1), .cat)
        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 2), .excluded)
    }

    func testClearDragClearsExcludedWithoutChangingCats() throws {
        let viewModel = try GameViewModel()
        viewModel.toggleCat(atRow: 0, column: 1)
        viewModel.toggleExcluded(atRow: 0, column: 2)

        viewModel.setExcludedDuringDrag(false, atRow: 0, column: 0)
        viewModel.setExcludedDuringDrag(false, atRow: 0, column: 1)
        viewModel.setExcludedDuringDrag(false, atRow: 0, column: 2)

        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 2), .empty)
        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 1), .cat)

        viewModel.undo()
        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 2), .excluded)
    }

    func testFirstRawTapShowsExcludedPreviewBeforeDomainCommit() throws {
        let viewModel = try GameViewModel(
            doubleTapInterval: .seconds(5)
        )

        viewModel.handleCellTap(atRow: 0, column: 0)

        XCTAssertEqual(
            viewModel.displayState(atRow: 0, column: 0),
            .excluded
        )
        XCTAssertEqual(
            viewModel.puzzle.state(atRow: 0, column: 0),
            .empty
        )
        XCTAssertFalse(viewModel.canUndo)
    }

    func testRawDoubleTapCommitsOnlyCatAndCreatesOneUndoEntry() throws {
        var changedStates: [GameState] = []
        let viewModel = GameViewModel(
            engine: try GameEngine(level: BuiltInLevels.meadow),
            doubleTapInterval: .seconds(5),
            onGameStateChanged: { changedStates.append($0) }
        )

        viewModel.handleCellTap(atRow: 0, column: 1)
        viewModel.handleCellTap(atRow: 0, column: 1)

        XCTAssertEqual(
            viewModel.displayState(atRow: 0, column: 1),
            .cat
        )
        XCTAssertEqual(changedStates.count, 1)
        XCTAssertEqual(
            changedStates.first?.puzzle.state(atRow: 0, column: 1),
            .cat
        )

        viewModel.undo()

        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 1), .empty)
        XCTAssertFalse(viewModel.canUndo)
    }

    func testRapidTapsOnDifferentCellsRemainIndependentPreviews() throws {
        let viewModel = try GameViewModel(
            doubleTapInterval: .seconds(5)
        )

        viewModel.handleCellTap(atRow: 0, column: 0)
        viewModel.handleCellTap(atRow: 1, column: 2)

        XCTAssertEqual(viewModel.displayState(atRow: 0, column: 0), .excluded)
        XCTAssertEqual(viewModel.displayState(atRow: 1, column: 2), .excluded)
        XCTAssertTrue(viewModel.puzzle.states.allSatisfy { $0 == .empty })
    }

    func testRawSingleTapCommitsAfterDoubleTapInterval() async throws {
        let viewModel = try GameViewModel(
            doubleTapInterval: .milliseconds(10)
        )

        viewModel.handleCellTap(atRow: 0, column: 0)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(
            viewModel.puzzle.state(atRow: 0, column: 0),
            .excluded
        )
        XCTAssertEqual(
            viewModel.displayState(atRow: 0, column: 0),
            .excluded
        )
        XCTAssertTrue(viewModel.canUndo)
    }

    func testRestartCancelsPendingTapWithoutLateMutation() async throws {
        let viewModel = try GameViewModel(
            doubleTapInterval: .milliseconds(20)
        )
        viewModel.handleCellTap(atRow: 0, column: 0)

        viewModel.restart()
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(viewModel.displayState(atRow: 0, column: 0), .empty)
        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 0), .empty)
        XCTAssertFalse(viewModel.canUndo)
    }

    func testUndoCancelsPendingTapWithoutCreatingHistory() async throws {
        let viewModel = try GameViewModel(
            doubleTapInterval: .milliseconds(20)
        )
        viewModel.handleCellTap(atRow: 0, column: 0)

        viewModel.undo()
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(viewModel.displayState(atRow: 0, column: 0), .empty)
        XCTAssertEqual(viewModel.puzzle.state(atRow: 0, column: 0), .empty)
        XCTAssertFalse(viewModel.canUndo)
    }

    func testIllegalCatIntentPreservesPuzzleAndExposesFeedback() throws {
        let viewModel = try GameViewModel()
        viewModel.toggleCat(atRow: 0, column: 0)
        let puzzleBeforeFailure = viewModel.puzzle

        viewModel.toggleCat(atRow: 0, column: 4)

        XCTAssertEqual(viewModel.puzzle, puzzleBeforeFailure)
        XCTAssertEqual(
            viewModel.feedbackMessage,
            "That cat conflicts with another cat."
        )
        XCTAssertEqual(viewModel.mistakeCount, 1)
        XCTAssertEqual(viewModel.remainingMistakes, 4)
        XCTAssertEqual(viewModel.mistakeSummary, "Mistakes: 1 / 5")
    }

    func testUndoRestoresPreviousPuzzle() throws {
        let viewModel = try GameViewModel()
        viewModel.toggleExcluded(atRow: 2, column: 2)

        viewModel.undo()

        XCTAssertEqual(viewModel.puzzle.state(atRow: 2, column: 2), .empty)
        XCTAssertFalse(viewModel.canUndo)
    }

    func testRestartRestoresInitialPuzzleAndClearsHistory() throws {
        let viewModel = try GameViewModel()
        viewModel.toggleCat(atRow: 0, column: 1)
        viewModel.toggleExcluded(atRow: 2, column: 2)

        viewModel.restart()

        XCTAssertTrue(viewModel.puzzle.states.allSatisfy { $0 == .empty })
        XCTAssertFalse(viewModel.canUndo)
        XCTAssertFalse(viewModel.isSolved)
        XCTAssertEqual(viewModel.mistakeCount, 0)
    }

    func testSolvedStateReflectsCompletedMeadow() throws {
        let viewModel = try GameViewModel(level: BuiltInLevels.meadow)

        for position in BuiltInLevels.meadowFixture.solution {
            viewModel.toggleCat(atRow: position.row, column: position.column)
        }

        XCTAssertTrue(viewModel.isSolved)
    }

    func testFailureStateIsExposedAfterMaximumMistakes() throws {
        let viewModel = try GameViewModel()
        viewModel.toggleCat(atRow: 0, column: 0)

        for _ in 0..<viewModel.level.maxMistakes {
            viewModel.toggleCat(atRow: 0, column: 4)
        }

        XCTAssertTrue(viewModel.isFailed)
        XCTAssertEqual(viewModel.remainingMistakes, 0)
        XCTAssertEqual(
            viewModel.puzzle.state(atRow: 0, column: 4),
            .empty
        )

        viewModel.restart()

        XCTAssertFalse(viewModel.isFailed)
        XCTAssertEqual(viewModel.mistakeCount, 0)
    }
}

final class CellTapInterpreterTests: XCTestCase {
    func testFirstTapStartsPendingSingle() {
        var interpreter = CellTapInterpreter()
        let position = CellPosition(row: 1, column: 2)

        let result = interpreter.registerTap(at: position)

        guard case let .pendingSingle(token) = result else {
            return XCTFail("Expected a pending single tap")
        }
        XCTAssertTrue(interpreter.commitSingle(at: position, token: token))
    }

    func testSecondTapOnSameCellResolvesDoubleAndInvalidatesTimeout() {
        var interpreter = CellTapInterpreter()
        let position = CellPosition(row: 1, column: 2)
        guard case let .pendingSingle(token) = interpreter.registerTap(
            at: position
        ) else {
            return XCTFail("Expected a pending single tap")
        }

        XCTAssertEqual(interpreter.registerTap(at: position), .doubleTap)
        XCTAssertFalse(interpreter.commitSingle(at: position, token: token))
    }

    func testDifferentCellsHaveIndependentPendingSingles() {
        var interpreter = CellTapInterpreter()
        let first = CellPosition(row: 0, column: 0)
        let second = CellPosition(row: 0, column: 1)
        guard case let .pendingSingle(firstToken) = interpreter.registerTap(
            at: first
        ), case let .pendingSingle(secondToken) = interpreter.registerTap(
            at: second
        ) else {
            return XCTFail("Expected independent pending taps")
        }

        XCTAssertTrue(interpreter.commitSingle(at: first, token: firstToken))
        XCTAssertTrue(interpreter.commitSingle(at: second, token: secondToken))
    }

    func testCancelAllInvalidatesEveryPendingTimeout() {
        var interpreter = CellTapInterpreter()
        let first = CellPosition(row: 0, column: 0)
        let second = CellPosition(row: 0, column: 1)
        guard case let .pendingSingle(firstToken) = interpreter.registerTap(
            at: first
        ), case let .pendingSingle(secondToken) = interpreter.registerTap(
            at: second
        ) else {
            return XCTFail("Expected independent pending taps")
        }

        interpreter.cancelAll()

        XCTAssertFalse(interpreter.commitSingle(at: first, token: firstToken))
        XCTAssertFalse(interpreter.commitSingle(at: second, token: secondToken))
    }
}
