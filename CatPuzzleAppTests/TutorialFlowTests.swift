import CatPuzzleCore
import Foundation
import XCTest
@testable import CatPuzzle

/// The tutorial's contract at the app layer: it comes first, it is played once
/// ever, it cannot be lost or knocked off its script, and looping the ladder
/// never brings it back.
@MainActor
final class TutorialFlowTests: XCTestCase {
    private var tutorial: TutorialLevel { TutorialLevels.basics }
    private var tutorials: [TutorialLevel] { TutorialLevels.all }
    private var ladder: [LevelFixture] { SampleLevels.fixtures }

    private func makeSession(
        _ store: InMemoryGameProgressStore
    ) -> AppSession {
        AppSession(
            progressStore: store,
            fixtures: ladder,
            tutorials: tutorials
        )
    }

    /// Plays the tutorial the way the tutorial asks to be played. Toggling the
    /// solution's cats straight in would be blocked by the very masking this
    /// file is here to check.
    private func followScript(
        _ viewModel: TutorialViewModel?,
        stoppingAfter stepCount: Int = .max
    ) async {
        guard let viewModel else { return XCTFail("no game in progress") }
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


    private func solve(_ session: AppSession, _ fixture: LevelFixture) {
        for position in fixture.solution {
            session.gameViewModel?.toggleCat(
                atRow: position.row,
                column: position.column
            )
        }
    }

    // MARK: - Progression

    func testAFreshPlayerStartsOnTheTutorial() {
        let session = makeSession(InMemoryGameProgressStore())

        XCTAssertEqual(session.destination, .readyForNextLevel)
        XCTAssertEqual(session.nextLevel?.id, tutorial.level.id)
        XCTAssertEqual(session.nextPresentation, .tutorial)
    }

    func testTheTutorialComesBeforeAnyLadderLevel() async {
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()

        await followScript(session.tutorialViewModel)

        XCTAssertEqual(session.tutorialViewModel?.isSolved, true)
        session.continueAfterCompletion()
        XCTAssertEqual(session.nextLevel?.id, ladder.first?.level.id)
        XCTAssertEqual(session.nextPresentation, .ladder(number: 1))
    }

    func testAFinishedTutorialIsNeverOfferedAgain() {
        let store = InMemoryGameProgressStore(
            progress: GameProgress(
                activeGame: nil,
                completedLevelIDs: [],
                completedTutorialIDs: Set(tutorials.map(\.level.id))
            )
        )

        let session = makeSession(store)

        XCTAssertEqual(session.nextLevel?.id, ladder.first?.level.id)
        XCTAssertEqual(session.nextPresentation?.isTutorial, false)
    }

    /// The ladder wrap clears `completedLevelIDs`; the tutorial must not ride
    /// along with it, or every lap would start with the introduction again.
    func testLoopingTheLadderDoesNotBringTheTutorialBack() {
        let store = InMemoryGameProgressStore(
            progress: GameProgress(
                activeGame: nil,
                completedLevelIDs: Set(ladder.map(\.level.id)),
                completedTutorialIDs: Set(tutorials.map(\.level.id))
            )
        )

        let session = makeSession(store)

        XCTAssertEqual(session.nextLevel?.id, ladder.first?.level.id)
        XCTAssertEqual(session.nextPresentation, .ladder(number: 1))
        XCTAssertEqual(store.progress.completedLevelIDs, [])
        XCTAssertEqual(
            store.progress.completedTutorialIDs,
            Set(tutorials.map(\.level.id)),
            "the wrap cleared the tutorial along with the lap"
        )
    }

    func testCompletingTheTutorialIsRecordedApartFromLadderProgress() async {
        let store = InMemoryGameProgressStore()
        let session = makeSession(store)
        session.startNextLevel()

        await followScript(session.tutorialViewModel)

        XCTAssertEqual(store.progress.completedTutorialIDs, [tutorial.level.id])
        XCTAssertEqual(store.progress.completedLevelIDs, [])
    }

    // MARK: - The board stays on the script

    /// A wrong cat would leave every later step pointing at a deduction that
    /// is no longer on the board, so the tutorial is played in challenge mode,
    /// where such a cat is refused instead of landing.
    func testAWrongCatIsRefusedRatherThanLeftOnTheBoard() async {
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()
        let viewModel = session.tutorialViewModel

        // The one cell this step lets the player touch, with the wrong gesture
        // for the step after it: a single tap, which would mark it out.
        await followScript(viewModel, stoppingAfter: 1)
        let wrongCat = tutorial.script.steps[1].task.positions[0]
        viewModel?.toggleCat(atRow: wrongCat.row, column: wrongCat.column)

        XCTAssertEqual(
            viewModel?.puzzle.state(atRow: wrongCat.row, column: wrongCat.column),
            .empty
        )
        XCTAssertEqual(viewModel?.stepNumber, 2, "the step moved on anyway")
    }

    func testTheTutorialCannotBeFailedByMisplacingCats() {
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()

        for _ in 0..<30 {
            session.tutorialViewModel?.toggleCat(atRow: 5, column: 5)
        }

        XCTAssertEqual(session.tutorialViewModel?.isFailed, false)
    }

    /// Turning Challenge Mode off mid-tutorial must not knock the board off
    /// its script (the tutorial is always played in challenge mode
    /// internally), but the preference still has to stick for the level after.
    func testChangingModeDuringTheTutorialIsRememberedButNotApplied() {
        let store = InMemoryGameProgressStore()
        let session = makeSession(store)
        session.startNextLevel()

        session.setGameplayMode(.exploration)

        XCTAssertNotNil(
            session.tutorialViewModel,
            "the tutorial mode change should not replace the active tutorial"
        )
        XCTAssertEqual(store.progress.preferredMode, .exploration)
    }

    // MARK: - Coaching

    func testTheTutorialOpensMaskedDownToTheOneCellRegion() throws {
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()
        let viewModel = try XCTUnwrap(session.tutorialViewModel)
        let first = try XCTUnwrap(tutorial.script.steps.first)

        XCTAssertEqual(viewModel.step, first)
        XCTAssertEqual(viewModel.stepNumber, 1)
        XCTAssertEqual(viewModel.stepCount, tutorial.script.steps.count)
        XCTAssertEqual(viewModel.spotlight, Set(first.spotlight))
        XCTAssertEqual(
            viewModel.interactivePositions,
            Set(first.task.positions)
        )
    }

    func testAGuidedStepIgnoresEveryCellItHasMaskedOff() throws {
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()
        let viewModel = try XCTUnwrap(session.tutorialViewModel)
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
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()
        let viewModel = try XCTUnwrap(session.tutorialViewModel)

        await followScript(viewModel, stoppingAfter: 1)

        XCTAssertEqual(viewModel.stepNumber, 2)
        XCTAssertEqual(viewModel.step, tutorial.script.steps[1])
    }

    func testGuidedExclusionShowsEachMarkBeforeAdvancing() async throws {
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()
        let viewModel = try XCTUnwrap(session.tutorialViewModel)
        await followScript(viewModel, stoppingAfter: 1)

        let step = tutorial.script.steps[1]
        let first = try XCTUnwrap(step.task.positions.first)
        viewModel.toggleExcluded(atRow: first.row, column: first.column)

        XCTAssertEqual(viewModel.stepNumber, 2)
        XCTAssertEqual(step.remainingPositions(in: viewModel.puzzle).count, step.task.positions.count - 1)
        XCTAssertTrue(step.task.positions.dropFirst().allSatisfy {
            viewModel.puzzle.state(atRow: $0.row, column: $0.column) == .empty
        })

        for position in step.task.positions.dropFirst() {
            viewModel.toggleExcluded(atRow: position.row, column: position.column)
        }
        XCTAssertEqual(viewModel.stepNumber, 3)
        XCTAssertTrue(step.remainingPositions(in: viewModel.puzzle).isEmpty)
    }

    /// Clearing a mark walks the tutorial back: the current step is read off
    /// the board, not counted up, so it can never point at a deduction the
    /// board no longer supports. Once the lesson has been handed over there
    /// is nothing stopping a player from clearing an earlier mark, and the
    /// tutorial has to go back and ask for it again rather than wait forever
    /// on a step whose reason has gone.
    func testClearingAnEarlierMarkDuringDiscoveryReopensThatStep() async throws {
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()
        let viewModel = try XCTUnwrap(session.tutorialViewModel)
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
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()
        let viewModel = try XCTUnwrap(session.tutorialViewModel)
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

    func testRestartingTheLevelReturnsToTheFirstStep() async throws {
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()
        let viewModel = try XCTUnwrap(session.tutorialViewModel)
        await followScript(viewModel, stoppingAfter: 3)
        XCTAssertGreaterThan(viewModel.stepNumber, 1)

        session.restartCurrentGame()

        XCTAssertEqual(viewModel.stepNumber, 1)
        XCTAssertEqual(viewModel.step, tutorial.script.steps.first)
    }

    func testTheCoachingStopsOnceTheBoardIsFinished() async throws {
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()
        let viewModel = try XCTUnwrap(session.tutorialViewModel)

        await followScript(viewModel)

        XCTAssertTrue(viewModel.isSolved)
        XCTAssertNil(viewModel.step)
        XCTAssertTrue(viewModel.spotlight.isEmpty)
        XCTAssertNil(viewModel.interactivePositions)
    }

    /// Nothing says the player has to mark every × on their way. Once the
    /// last cat is down the board is finished and the coaching goes with it,
    /// rather than sitting there asking for marks that no longer matter.
    func testCoachingStopsEvenIfTheBoardIsFinishedWithMarksLeftUnmade() async throws {
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()
        let viewModel = try XCTUnwrap(session.tutorialViewModel)
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        await followScript(viewModel, stoppingAfter: guided)

        // Straight to the cats still missing, skipping every remaining
        // exclusion step.
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
        let session = makeSession(InMemoryGameProgressStore())
        session.startNextLevel()
        let viewModel = try XCTUnwrap(session.tutorialViewModel)

        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        await followScript(viewModel, stoppingAfter: guided)

        XCTAssertEqual(viewModel.step?.coaching, .discovery)
        XCTAssertTrue(viewModel.spotlight.isEmpty)
        XCTAssertNil(viewModel.interactivePositions)
    }

    func testExcludingAFutureCatIsRejectedDuringDiscovery() async throws {
        let viewModel = try makeCoachedViewModel()
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        await followScript(viewModel, stoppingAfter: guided)
        let futureCat = try XCTUnwrap(
            tutorial.script.steps.dropFirst(guided).compactMap { step -> CellPosition? in
                if case let .placeCat(position) = step.task { return position }
                return nil
            }.first
        )

        viewModel.toggleExcluded(atRow: futureCat.row, column: futureCat.column)

        XCTAssertEqual(
            viewModel.puzzle.state(atRow: futureCat.row, column: futureCat.column),
            .empty
        )
        XCTAssertEqual(viewModel.stepNumber, guided + 1)
        XCTAssertNotNil(viewModel.feedbackMessage)
    }

    // MARK: - Player-requested clue

    func testDiscoveryShowsOnlyOneCellAfterThePlayerRequestsAClue() async throws {
        let viewModel = try makeCoachedViewModel()
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        await followScript(viewModel, stoppingAfter: guided)
        let step = try XCTUnwrap(viewModel.step)

        XCTAssertTrue(viewModel.nudgedPositions.isEmpty)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(viewModel.nudgedPositions.isEmpty)

        viewModel.revealClue()

        XCTAssertEqual(
            viewModel.nudgedPositions,
            Set(step.remainingPositions(in: viewModel.puzzle).prefix(1))
        )
    }

    func testAGuidedStepCannotRevealAClue() throws {
        let viewModel = try makeCoachedViewModel()
        viewModel.revealClue()

        XCTAssertEqual(viewModel.step?.coaching, .guided)
        XCTAssertTrue(viewModel.nudgedPositions.isEmpty)
    }

    func testClueClearsWhenThePlayerAdvances() async throws {
        let viewModel = try makeCoachedViewModel()
        let guided = tutorial.script.steps.prefix { $0.coaching == .guided }.count
        await followScript(viewModel, stoppingAfter: guided)
        let step = try XCTUnwrap(viewModel.step)
        viewModel.revealClue()

        let done = try XCTUnwrap(step.task.positions.first)
        viewModel.toggleExcluded(atRow: done.row, column: done.column)

        XCTAssertTrue(viewModel.nudgedPositions.isEmpty)
        XCTAssertEqual(viewModel.step, step)
        for position in step.remainingPositions(in: viewModel.puzzle) {
            viewModel.toggleExcluded(atRow: position.row, column: position.column)
        }
        XCTAssertNotEqual(viewModel.step, step)
    }

    private func makeCoachedViewModel() throws -> TutorialViewModel {
        TutorialViewModel(
            engine: try GameEngine(fixture: tutorial.fixture, mode: .challenge),
            script: tutorial.script
        )
    }

    // MARK: - Resume

    func testAnInterruptedTutorialResumesOnTheStepItWasLeftOn() async throws {
        let store = InMemoryGameProgressStore()
        let session = makeSession(store)
        session.startNextLevel()
        await followScript(session.tutorialViewModel, stoppingAfter: 2)

        XCTAssertEqual(store.progress.activeGame?.levelID, tutorial.level.id)

        let resumed = makeSession(store)

        XCTAssertEqual(resumed.destination, .tutorial)
        XCTAssertEqual(resumed.tutorialViewModel?.level.id, tutorial.level.id)
        XCTAssertEqual(resumed.currentPresentation, .tutorial)
        XCTAssertEqual(resumed.tutorialViewModel?.stepNumber, 3)
    }

    /// A player who was already partway through the ladder before the tutorial
    /// existed should not be sent back to square one by the update.
    func testExistingProgressIsTreatedAsHavingFinishedTheTutorial() throws {
        let stored = GameProgress(
            activeGame: nil,
            completedLevelIDs: ["meadow"],
            completedTutorialIDs: []
        )
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(stored)
        ) as! [String: Any]
        json.removeValue(forKey: "completedTutorialIDs")
        let data = try JSONSerialization.data(withJSONObject: json)

        let migrated = try JSONDecoder().decode(GameProgress.self, from: data)

        XCTAssertEqual(
            migrated.completedTutorialIDs,
            Set(TutorialLevels.all.map(\.level.id))
        )
    }

    func testAFreshInstallStillSeesTheTutorial() throws {
        let json = try JSONSerialization.data(
            withJSONObject: ["completedLevelIDs": [String]()]
        )

        let decoded = try JSONDecoder().decode(GameProgress.self, from: json)

        XCTAssertEqual(decoded.completedTutorialIDs, [])
    }

    // MARK: - Debug reset

    /// The tutorial is played once ever, which in a debug build is exactly
    /// what makes it hard to work on. `resetTutorial` offers it again without
    /// throwing away the ladder progress alongside it.
    func testResettingTheTutorialOffersItAgainAndKeepsLadderProgress() {
        let store = InMemoryGameProgressStore(
            progress: GameProgress(
                activeGame: nil,
                completedLevelIDs: [ladder[0].level.id],
                completedTutorialIDs: Set(tutorials.map(\.level.id))
            )
        )
        let session = makeSession(store)
        XCTAssertEqual(session.nextPresentation?.isTutorial, false)

        session.resetTutorial()

        XCTAssertEqual(session.destination, .readyForNextLevel)
        XCTAssertEqual(session.nextLevel?.id, tutorial.level.id)
        XCTAssertEqual(session.nextPresentation, .tutorial)
        XCTAssertEqual(store.progress.completedTutorialIDs, [])
        XCTAssertEqual(
            store.progress.completedLevelIDs,
            [ladder[0].level.id],
            "resetting the tutorial threw away the ladder too"
        )
    }

    /// A saved game left behind would be resumed on the next launch, which
    /// routes straight past the tutorial the reset just re-offered.
    func testResettingTheTutorialDropsTheGameInProgress() async {
        let store = InMemoryGameProgressStore()
        let session = makeSession(store)
        session.startNextLevel()
        await followScript(session.tutorialViewModel, stoppingAfter: 2)
        XCTAssertNotNil(store.progress.activeGame)

        session.resetTutorial()

        XCTAssertNil(session.tutorialViewModel)
        XCTAssertNil(store.progress.activeGame)
        XCTAssertEqual(makeSession(store).nextLevel?.id, tutorial.level.id)
    }
}

private final class InMemoryGameProgressStore: GameProgressStore {
    var progress: GameProgress

    init(progress: GameProgress = .empty) {
        self.progress = progress
    }

    func loadProgress() throws -> GameProgress {
        progress
    }

    func saveProgress(_ progress: GameProgress) throws {
        self.progress = progress
    }
}
