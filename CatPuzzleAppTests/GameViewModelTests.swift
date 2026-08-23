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
    }

    func testSolvedStateReflectsCompletedMeadow() throws {
        let viewModel = try GameViewModel(level: BuiltInLevels.meadow)

        for position in BuiltInLevels.meadowFixture.solution {
            viewModel.toggleCat(atRow: position.row, column: position.column)
        }

        XCTAssertTrue(viewModel.isSolved)
    }
}
