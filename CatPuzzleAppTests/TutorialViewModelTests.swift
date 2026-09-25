import CatPuzzleCore
import XCTest
@testable import CatPuzzle

/// `TutorialViewModel`'s own contract, tested by constructing it directly
/// rather than through `AppSession` — it owns its `GameEngine`/`TutorialCoach`
/// independently of `GameViewModel`, and this file is what proves the
/// relocated coaching logic (masking, step advance/reopen, nudging, restart,
/// challenge-mode refusal) still behaves exactly as it did when it lived on
/// `GameViewModel`. `AppSession`-level concerns (progression, resume, debug
/// reset) stay covered by `TutorialFlowTests.swift` through the routing this
/// view model is wired into separately.
@MainActor
final class TutorialViewModelTests: XCTestCase {
    private var tutorial: TutorialLevel { TutorialLevels.basics }

    private func makeViewModel(nudgeDelay: Duration = .milliseconds(40)) throws -> TutorialViewModel {
        TutorialViewModel(
            engine: try GameEngine(fixture: tutorial.fixture, mode: .challenge),
            script: tutorial.script,
            nudgeDelay: nudgeDelay
        )
    }

    /// Plays the tutorial the way the tutorial asks to be played. Toggling the
    /// solution's cats straight in would be blocked by the very masking this
    /// file is here to check.
    private func followScript(
        _ viewModel: TutorialViewModel,
        stoppingAfter stepCount: Int = .max
    ) {
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

    // MARK: - The board stays on the script

    /// A wrong cat would leave every later step pointing at a deduction that
    /// is no longer on the board, so the tutorial is played in challenge mode,
    /// where such a cat is refused instead of landing.
    func testAWrongCatIsRefusedRatherThanLeftOnTheBoard() throws {
        let viewModel = try makeViewModel()

        // The one cell this step lets the player touch, with the wrong gesture
        // for the step after it: a single tap, which would mark it out.
        followScript(viewModel, stoppingAfter: 1)
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

    func testMakingAStepsMoveAdvancesToTheNextStep() throws {
        let viewModel = try makeViewModel()

        followScript(viewModel, stoppingAfter: 1)

        XCTAssertEqual(viewModel.stepNumber, 2)
        XCTAssertEqual(viewModel.step, tutorial.script.steps[1])
    }

    /// Part-finishing a step is not finishing it: the tutorial keeps waiting
    /// on the cells that are still unmarked.
    func testAStepStaysCurrentUntilEveryOneOfItsCellsIsMarked() throws {
        let viewModel = try makeViewModel()
        followScript(viewModel, stoppingAfter: 1)

        let step = tutorial.script.steps[1]
        let first = try XCTUnwrap(step.task.positions.first)
        viewModel.toggleExcluded(atRow: first.row, column: first.column)

        XCTAssertEqual(viewModel.stepNumber, 2)
        XCTAssertEqual(
            step.remainingPositions(in: viewModel.puzzle).count,
            step.task.positions.count - 1
        )
    }

    /// Clearing a mark walks the tutorial back: the current step is read off
    /// the board, not counted up, so it can never point at a deduction the
    /// board no longer supports.
    func testClearingAnEarlierMarkDuringDiscoveryReopensThatStep() throws {
        let viewModel = try makeViewModel()
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        followScript(viewModel, stoppingAfter: guided)
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
    func testAGuidedStepWillNotLetAnEarlierMarkBeCleared() throws {
        let viewModel = try makeViewModel()
        followScript(viewModel, stoppingAfter: 2)
        XCTAssertEqual(viewModel.stepNumber, 3)

        let marked = try XCTUnwrap(tutorial.script.steps[1].task.positions.first)
        viewModel.toggleExcluded(atRow: marked.row, column: marked.column)

        XCTAssertEqual(
            viewModel.puzzle.state(atRow: marked.row, column: marked.column),
            .excluded
        )
        XCTAssertEqual(viewModel.stepNumber, 3)
    }

    func testRestartingReturnsToTheFirstStep() throws {
        let viewModel = try makeViewModel()
        followScript(viewModel, stoppingAfter: 3)
        XCTAssertGreaterThan(viewModel.stepNumber, 1)

        viewModel.restart()

        XCTAssertEqual(viewModel.stepNumber, 1)
        XCTAssertEqual(viewModel.step, tutorial.script.steps.first)
    }

    func testTheCoachingStopsOnceTheBoardIsFinished() throws {
        let viewModel = try makeViewModel()

        followScript(viewModel)

        XCTAssertTrue(viewModel.isSolved)
        XCTAssertNil(viewModel.step)
        XCTAssertTrue(viewModel.spotlight.isEmpty)
        XCTAssertNil(viewModel.interactivePositions)
    }

    /// Nothing says the player has to mark every × on their way. Once the
    /// last cat is down the board is finished and the coaching goes with it.
    func testCoachingStopsEvenIfTheBoardIsFinishedWithMarksLeftUnmade() throws {
        let viewModel = try makeViewModel()
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        followScript(viewModel, stoppingAfter: guided)

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
    func testDiscoveryStepsLeaveTheWholeBoardLive() throws {
        let viewModel = try makeViewModel()

        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        followScript(viewModel, stoppingAfter: guided)

        XCTAssertEqual(viewModel.step?.coaching, .discovery)
        XCTAssertTrue(viewModel.spotlight.isEmpty)
        XCTAssertNil(viewModel.interactivePositions)
    }

    // MARK: - Nudging

    /// A player left alone on an unguided step gets shown where to look, but
    /// only after they have had time to look for themselves.
    func testAnUnguidedStepPointsAtItsCellsOnlyAfterThePlayerHasStalled() async throws {
        let viewModel = try makeViewModel()
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        followScript(viewModel, stoppingAfter: guided)
        let step = try XCTUnwrap(viewModel.step)

        XCTAssertTrue(viewModel.nudgedPositions.isEmpty, "the nudge fired immediately")
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(viewModel.nudgedPositions, Set(step.task.positions))
    }

    /// A guided step is already pointing — with the whole board masked around
    /// it — so it never pulses on top of that.
    func testAGuidedStepNeverNudges() async throws {
        let viewModel = try makeViewModel()

        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(viewModel.step?.coaching, .guided)
        XCTAssertTrue(viewModel.nudgedPositions.isEmpty)
    }

    /// Once the player is moving again the nudge narrows to what is left,
    /// rather than going on flashing cells they have already dealt with.
    func testNudgingFollowsTheCellsStillLeftInTheStep() async throws {
        let viewModel = try makeViewModel()
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        followScript(viewModel, stoppingAfter: guided)
        let step = try XCTUnwrap(viewModel.step)
        try await Task.sleep(for: .milliseconds(120))

        let done = try XCTUnwrap(step.task.positions.first)
        viewModel.toggleExcluded(atRow: done.row, column: done.column)

        XCTAssertEqual(
            viewModel.nudgedPositions,
            Set(step.task.positions.dropFirst()),
            "a cell the player has already marked is still being pointed at"
        )
    }
}
