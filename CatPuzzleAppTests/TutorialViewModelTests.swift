import CatPuzzleCore
import XCTest
@testable import CatPuzzle

/// `TutorialViewModel`'s own contract, tested by constructing it directly
/// rather than through `AppSession` — it owns its `GameEngine`/`TutorialCoach`
/// independently of `GameViewModel`, and this file is what proves the
/// relocated coaching logic (masking, step advance/reopen, clues, restart,
/// challenge-mode refusal) still behaves exactly as it did when it lived on
/// `GameViewModel`. `AppSession`-level concerns (progression, resume, debug
/// reset) stay covered by `TutorialFlowTests.swift` through the routing this
/// view model is wired into separately.
@MainActor
final class TutorialViewModelTests: XCTestCase {
    private var tutorial: TutorialLevel { TutorialLevels.basics }

    private func makeViewModel() throws -> TutorialViewModel {
        TutorialViewModel(
            engine: try GameEngine(fixture: tutorial.fixture, mode: .challenge),
            script: tutorial.script,
            soundPlayer: RecordingPuzzleSoundPlayer()
        )
    }

    /// Plays the tutorial the way the tutorial asks to be played. Toggling the
    /// solution's cats straight in would be blocked by the very masking this
    /// file is here to check.
    private func followScript(
        _ viewModel: TutorialViewModel,
        stoppingAfter stepCount: Int = .max
    ) async {
        for step in tutorial.script.steps.prefix(stepCount) {
            switch step.task {
            case let .placeCat(position):
                viewModel.toggleCat(atRow: position.row, column: position.column)
            case let .exclude(positions):
                for position in positions {
                    viewModel.toggleExcluded(
                        atRow: position.row,
                        column: position.column
                    )
                }
            }
        }
    }


    func testSingleTapOnCatTargetExplainsDoubleTapAndPreservesStep() async throws {
        let viewModel = try makeViewModel()
        let target = try XCTUnwrap(viewModel.guidedTarget)
        viewModel.handleCellTap(atRow: target.row, column: target.column)
        // Allow the real single/double-tap recognition window to expire.
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(viewModel.feedbackMessage, "Double-tap this cell to place a cat.")
        XCTAssertEqual(viewModel.stepNumber, 1)
        XCTAssertEqual(viewModel.puzzle.state(atRow: target.row, column: target.column), .empty)

        viewModel.handleCellTap(atRow: target.row, column: target.column)
        viewModel.handleCellTap(atRow: target.row, column: target.column)
        XCTAssertEqual(viewModel.stepNumber, 2)
        XCTAssertNil(viewModel.feedbackMessage)
    }

    func testColumnGuideStopsOnlyWhenDraggingStartsAndResetsOnRestart() async throws {
        let viewModel = try makeViewModel()
        await followScript(viewModel, stoppingAfter: 2)
        XCTAssertTrue(viewModel.showsFingerGuide)
        let first = try XCTUnwrap(viewModel.guidedTarget)
        viewModel.toggleExcluded(atRow: first.row, column: first.column)
        XCTAssertTrue(viewModel.showsFingerGuide, "A tap must not stop the drag demonstration")
        let next = try XCTUnwrap(viewModel.guidedTarget)
        viewModel.setExcludedDuringDrag(true, atRow: next.row, column: next.column)
        XCTAssertTrue(viewModel.hasStartedColumnDrag)
        XCTAssertFalse(viewModel.showsFingerGuide)
        viewModel.showIdleReminder()
        XCTAssertFalse(viewModel.showsFingerGuide)
        viewModel.restart()
        await followScript(viewModel, stoppingAfter: 2)
        XCTAssertTrue(viewModel.showsFingerGuide)
        XCTAssertFalse(viewModel.hasStartedColumnDrag)
    }

    // MARK: - The board stays on the script

    /// A wrong cat would leave every later step pointing at a deduction that
    /// is no longer on the board, so the tutorial is played in challenge mode,
    /// where such a cat is refused instead of landing.
    func testAWrongCatIsRefusedRatherThanLeftOnTheBoard() async throws {
        let viewModel = try makeViewModel()

        // The one cell this step lets the player touch, with the wrong gesture
        // for the step after it: a single tap, which would mark it out.
        await followScript(viewModel, stoppingAfter: 1)
        let wrongCat = tutorial.script.steps[1].task.positions[0]
        viewModel.toggleCat(atRow: wrongCat.row, column: wrongCat.column)

        XCTAssertEqual(
            viewModel.puzzle.state(atRow: wrongCat.row, column: wrongCat.column),
            .empty
        )
        XCTAssertEqual(viewModel.stepNumber, 2, "the step moved on anyway")
    }

    func testTheTutorialCannotBeFailedByMisplacingCats() throws {
        let viewModel = try makeViewModel()

        for _ in 0..<30 {
            viewModel.toggleCat(atRow: 5, column: 5)
        }

        XCTAssertEqual(viewModel.isFailed, false)
    }

    // MARK: - Coaching

    func testTheTutorialOpensMaskedDownToTheOneCellRegion() throws {
        let viewModel = try makeViewModel()
        let first = try XCTUnwrap(tutorial.script.steps.first)

        XCTAssertEqual(viewModel.step, first)
        XCTAssertEqual(viewModel.stepNumber, 1)
        XCTAssertEqual(viewModel.stepCount, tutorial.script.steps.count)
        XCTAssertEqual(viewModel.spotlight, Set(first.spotlight))
        XCTAssertEqual(viewModel.interactivePositions, Set(first.task.positions))
    }

    func testAGuidedStepIgnoresEveryCellItHasMaskedOff() throws {
        let viewModel = try makeViewModel()
        let lit = try XCTUnwrap(viewModel.interactivePositions)
        let masked = try XCTUnwrap(
            (0..<tutorial.level.size).flatMap { row in
                (0..<tutorial.level.size).map { CellPosition(row: row, column: $0) }
            }
            .first { !lit.contains($0) }
        )

        viewModel.toggleExcluded(atRow: masked.row, column: masked.column)
        viewModel.toggleCat(atRow: masked.row, column: masked.column)
        viewModel.setExcludedDuringDrag(true, atRow: masked.row, column: masked.column)

        XCTAssertEqual(
            viewModel.puzzle.state(atRow: masked.row, column: masked.column),
            .empty
        )
        XCTAssertEqual(viewModel.stepNumber, 1)
    }

    func testMakingAStepsMoveAdvancesToTheNextStep() async throws {
        let viewModel = try makeViewModel()

        await followScript(viewModel, stoppingAfter: 1)

        XCTAssertEqual(viewModel.stepNumber, 2)
        XCTAssertEqual(viewModel.step, tutorial.script.steps[1])
    }

    func testGuidedExclusionAdvancesOnlyAfterEveryCellIsMarked() async throws {
        let viewModel = try makeViewModel()
        await followScript(viewModel, stoppingAfter: 1)

        let step = tutorial.script.steps[1]
        let first = try XCTUnwrap(step.task.positions.first)
        viewModel.toggleExcluded(atRow: first.row, column: first.column)

        XCTAssertEqual(viewModel.stepNumber, 2)
        XCTAssertEqual(step.remainingPositions(in: viewModel.puzzle).count, step.task.positions.count - 1)
        XCTAssertEqual(viewModel.interactivePositions, Set(step.task.positions.dropFirst()))

        for position in step.task.positions.dropFirst() {
            viewModel.toggleExcluded(atRow: position.row, column: position.column)
        }

        XCTAssertEqual(viewModel.stepNumber, 3)
        XCTAssertTrue(step.remainingPositions(in: viewModel.puzzle).isEmpty)
    }

    func testHandMovesToEachRemainingRowColumnAndCorner() async throws {
        let viewModel = try makeViewModel()
        await followScript(viewModel, stoppingAfter: 1)

        for stepIndex in 1...3 {
            let positions = tutorial.script.steps[stepIndex].task.positions
            for position in positions {
                let previousPlaybackID = viewModel.guidancePlaybackID
                XCTAssertEqual(viewModel.guidedTarget, position)
                viewModel.toggleExcluded(atRow: position.row, column: position.column)
                XCTAssertNotEqual(viewModel.guidancePlaybackID, previousPlaybackID)
            }
        }
        XCTAssertEqual(viewModel.stepNumber, 5)
    }

    func testFirstColumnTeachesContinuousDragWithoutChangingTheCat() async throws {
        let viewModel = try makeViewModel()
        await followScript(viewModel, stoppingAfter: 1)
        XCTAssertFalse(viewModel.teachesColumnDrag)
        XCTAssertNil(viewModel.guidedDragEnd)
        for position in tutorial.script.steps[1].task.positions {
            viewModel.toggleExcluded(atRow: position.row, column: position.column)
        }
        let columnStep = tutorial.script.steps[2]
        XCTAssertTrue(viewModel.teachesColumnDrag)
        XCTAssertEqual(viewModel.guidedTarget, columnStep.task.positions.first)
        XCTAssertEqual(viewModel.guidedDragEnd, columnStep.task.positions.last)
        let cat = try XCTUnwrap(tutorial.script.steps[0].task.positions.first)
        let masked = CellPosition(row: 0, column: (cat.column + 1) % viewModel.level.size)
        let previous = viewModel.puzzle.state(atRow: masked.row, column: masked.column)
        viewModel.setExcludedDuringDrag(true, atRow: masked.row, column: masked.column)
        XCTAssertEqual(viewModel.puzzle.state(atRow: masked.row, column: masked.column), previous)
        for row in 0..<viewModel.level.size {
            viewModel.setExcludedDuringDrag(true, atRow: row, column: cat.column)
        }
        XCTAssertEqual(viewModel.puzzle.state(atRow: cat.row, column: cat.column), .cat)
        XCTAssertTrue(columnStep.isSatisfied(by: viewModel.puzzle))
        XCTAssertEqual(viewModel.step, tutorial.script.steps[3])
        XCTAssertFalse(viewModel.teachesColumnDrag)
        XCTAssertNil(viewModel.guidedDragEnd)
    }

    func testNoTouchingStepNeedsAllFourCornersAroundTheFirstCat() async throws {
        let viewModel = try makeViewModel()
        await followScript(viewModel, stoppingAfter: 3)
        let firstCat = try XCTUnwrap(tutorial.script.steps.first?.task.positions.first)
        let corners = tutorial.script.steps[3].task.positions

        XCTAssertEqual(viewModel.stepNumber, 4)
        XCTAssertEqual(viewModel.puzzle.state(atRow: firstCat.row, column: firstCat.column), .cat)
        XCTAssertEqual(corners.count, 4)

        for position in corners.dropLast() {
            viewModel.toggleExcluded(atRow: position.row, column: position.column)
            XCTAssertEqual(viewModel.stepNumber, 4)
        }
        XCTAssertEqual(viewModel.interactivePositions, Set(corners.suffix(1)))

        let last = try XCTUnwrap(corners.last)
        viewModel.toggleExcluded(atRow: last.row, column: last.column)
        XCTAssertEqual(viewModel.stepNumber, 5)
    }

    /// Clearing a mark walks the tutorial back: the current step is read off
    /// the board, not counted up, so it can never point at a deduction the
    /// board no longer supports.
    func testClearingAnEarlierMarkDuringDiscoveryReopensThatStep() async throws {
        let viewModel = try makeViewModel()
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        await followScript(viewModel, stoppingAfter: guided)
        XCTAssertEqual(viewModel.stepNumber, guided + 1)

        let cleared = try XCTUnwrap(tutorial.script.steps[1].task.positions.first)
        viewModel.toggleExcluded(atRow: cleared.row, column: cleared.column)

        XCTAssertEqual(viewModel.stepNumber, 2)
        XCTAssertEqual(viewModel.step, tutorial.script.steps[1])
        XCTAssertFalse(
            viewModel.spotlight.isEmpty,
            "the reopened step has to explain itself again, not just wait"
        )
    }

    /// While the lesson is still running, though, the mask is what stops a
    /// player from undoing their way out of it.
    func testAGuidedStepWillNotLetAnEarlierMarkBeCleared() async throws {
        let viewModel = try makeViewModel()
        await followScript(viewModel, stoppingAfter: 2)
        XCTAssertEqual(viewModel.stepNumber, 3)

        let marked = try XCTUnwrap(tutorial.script.steps[1].task.positions.first)
        viewModel.toggleExcluded(atRow: marked.row, column: marked.column)

        XCTAssertEqual(
            viewModel.puzzle.state(atRow: marked.row, column: marked.column),
            .excluded
        )
        XCTAssertEqual(viewModel.stepNumber, 3)
    }

    func testRestartingReturnsToTheFirstStep() async throws {
        let viewModel = try makeViewModel()
        await followScript(viewModel, stoppingAfter: 3)
        XCTAssertGreaterThan(viewModel.stepNumber, 1)

        viewModel.restart()

        XCTAssertEqual(viewModel.stepNumber, 1)
        XCTAssertEqual(viewModel.step, tutorial.script.steps.first)
    }

    func testTheCoachingStopsOnceTheBoardIsFinished() async throws {
        let viewModel = try makeViewModel()

        await followScript(viewModel)

        XCTAssertTrue(viewModel.isSolved)
        XCTAssertNil(viewModel.step)
        XCTAssertTrue(viewModel.spotlight.isEmpty)
        XCTAssertNil(viewModel.interactivePositions)
    }

    /// Nothing says the player has to mark every × on their way. Once the
    /// last cat is down the board is finished and the coaching goes with it.
    func testCoachingStopsEvenIfTheBoardIsFinishedWithMarksLeftUnmade() async throws {
        let viewModel = try makeViewModel()
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        await followScript(viewModel, stoppingAfter: guided)

        for position in tutorial.fixture.solution
        where viewModel.puzzle.state(atRow: position.row, column: position.column) != .cat {
            viewModel.toggleCat(atRow: position.row, column: position.column)
        }

        XCTAssertTrue(viewModel.isSolved)
        XCTAssertNil(viewModel.step)
        XCTAssertTrue(viewModel.nudgedPositions.isEmpty)
    }

    /// Once the lesson is over the board is handed over whole: nothing masked,
    /// every cell live.
    func testDiscoveryStepsLeaveTheWholeBoardLive() async throws {
        let viewModel = try makeViewModel()

        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        await followScript(viewModel, stoppingAfter: guided)

        XCTAssertEqual(viewModel.step?.coaching, .discovery)
        XCTAssertTrue(viewModel.spotlight.isEmpty)
        XCTAssertNil(viewModel.interactivePositions)
    }

    func testSecondCatRequiresEveryManualMarkAndRemindsTheWholeLine() async throws {
        let viewModel = try makeViewModel()
        await followScript(viewModel, stoppingAfter: 5)
        let step = try XCTUnwrap(viewModel.step)
        let first = try XCTUnwrap(step.task.positions.first)
        viewModel.toggleExcluded(atRow: first.row, column: first.column)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(viewModel.step, step)
        XCTAssertEqual(step.remainingPositions(in: viewModel.puzzle).count, step.task.positions.count - 1)
        viewModel.showIdleReminder()
        XCTAssertFalse(viewModel.reminderPositions.isEmpty)
        XCTAssertEqual(viewModel.reminderPositions.count, viewModel.level.size)
        XCTAssertTrue(viewModel.reminderPositions.allSatisfy { $0.row == first.row })
        viewModel.recordInteraction()
        XCTAssertTrue(viewModel.reminderPositions.isEmpty)
        for position in step.remainingPositions(in: viewModel.puzzle) {
            viewModel.toggleExcluded(atRow: position.row, column: position.column)
        }
        XCTAssertEqual(viewModel.activeRule, .noTouchingCats)
    }

    func testRulesAreCollectedOnlyAfterTheirFullLessonAndResetOnRestart() async throws {
        let viewModel = try makeViewModel()
        XCTAssertTrue(viewModel.learnedRules.isEmpty)
        await followScript(viewModel, stoppingAfter: 2)
        XCTAssertEqual(viewModel.learnedRules, [.oneCatPerRegion])
        for position in tutorial.script.steps[2].task.positions {
            viewModel.toggleExcluded(atRow: position.row, column: position.column)
        }
        XCTAssertEqual(viewModel.learnedRules, [.oneCatPerRegion, .oneCatPerRowAndColumn])
        for position in tutorial.script.steps[3].task.positions {
            viewModel.toggleExcluded(atRow: position.row, column: position.column)
        }
        XCTAssertEqual(viewModel.learnedRules, Set(PuzzleRule.allCases))
        viewModel.restart()
        XCTAssertTrue(viewModel.learnedRules.isEmpty)
        XCTAssertTrue(viewModel.reminderPositions.isEmpty)
    }

    func testThirdCatGetsDelayedClueAndThenManualLinePractice() async throws {
        let viewModel = try makeViewModel()
        let thirdIndex = try XCTUnwrap(tutorial.script.steps.indices.first { index in
            guard index > 4 else { return false }
            if case .placeCat = tutorial.script.steps[index].task { return true }
            return false
        })
        await followScript(viewModel, stoppingAfter: thirdIndex)
        XCTAssertTrue(viewModel.reminderPositions.isEmpty)
        viewModel.showIdleReminder()
        let target = try XCTUnwrap(viewModel.step?.task.positions.first)
        XCTAssertEqual(viewModel.reminderPositions, [target])
        viewModel.toggleCat(atRow: target.row, column: target.column)
        XCTAssertEqual(viewModel.activeRule, .oneCatPerRowAndColumn)
        XCTAssertTrue(viewModel.reminderPositions.isEmpty)
    }

    // MARK: - Player-requested clue

    func testAnUnguidedStepDoesNotRevealAnAnswerWithoutARequest() async throws {
        let viewModel = try makeViewModel()
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        await followScript(viewModel, stoppingAfter: guided)

        XCTAssertTrue(viewModel.nudgedPositions.isEmpty)
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertTrue(viewModel.nudgedPositions.isEmpty)
    }

    func testARequestedClueShowsOnlyOneUnfinishedCell() async throws {
        let viewModel = try makeViewModel()
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        await followScript(viewModel, stoppingAfter: guided)
        let step = try XCTUnwrap(viewModel.step)
        viewModel.revealClue()

        XCTAssertEqual(
            viewModel.nudgedPositions,
            Set(step.remainingPositions(in: viewModel.puzzle).prefix(1))
        )
    }

    func testClueDisappearsAfterItsStepCompletes() async throws {
        let viewModel = try makeViewModel()
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        await followScript(viewModel, stoppingAfter: guided)
        let step = try XCTUnwrap(viewModel.step)
        viewModel.revealClue()

        let done = try XCTUnwrap(step.task.positions.first)
        viewModel.toggleExcluded(atRow: done.row, column: done.column)

        XCTAssertTrue(viewModel.nudgedPositions.isEmpty)
    }
}
