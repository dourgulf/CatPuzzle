import CatPuzzleCore
import Foundation
import XCTest
@testable import CatPuzzle

@MainActor
final class AppSessionTests: XCTestCase {
    func testFirstLaunchOffersMeadow() {
        let store = InMemoryGameProgressStore()
        let session = AppSession(progressStore: store)

        XCTAssertEqual(session.destination, .readyForNextLevel)
        XCTAssertEqual(session.nextLevel?.id, "meadow")
        XCTAssertNil(session.gameViewModel)
    }

    func testActiveGameResumesItsLevelAndCellStatesWithoutUndo() {
        var states = emptySavedStates()
        states[index(row: 0, column: 0)] = .excluded
        states[index(row: 0, column: 1)] = .cat
        let store = InMemoryGameProgressStore(
            progress: GameProgress(
                activeGame: SavedGame(levelID: "meadow", states: states),
                completedLevelIDs: []
            )
        )

        let session = AppSession(progressStore: store)

        XCTAssertEqual(session.destination, .playing)
        XCTAssertEqual(session.gameViewModel?.level.id, "meadow")
        XCTAssertEqual(
            session.gameViewModel?.puzzle.state(atRow: 0, column: 0),
            .excluded
        )
        XCTAssertEqual(
            session.gameViewModel?.puzzle.state(atRow: 0, column: 1),
            .cat
        )
        XCTAssertEqual(session.gameViewModel?.canUndo, false)
    }

    func testStartingNextLevelCreatesAndSavesEmptyActiveGame() {
        let store = InMemoryGameProgressStore()
        let session = AppSession(progressStore: store)

        session.startNextLevel()

        XCTAssertEqual(session.destination, .playing)
        XCTAssertEqual(store.progress.activeGame?.levelID, "meadow")
        XCTAssertEqual(
            store.progress.activeGame?.states,
            emptySavedStates()
        )
    }

    func testCellChangeAutosavesUpdatedState() {
        let store = InMemoryGameProgressStore()
        let session = startedSession(store: store)

        session.gameViewModel?.toggleExcluded(atRow: 1, column: 2)

        XCTAssertEqual(
            store.progress.activeGame?.states[index(row: 1, column: 2)],
            .excluded
        )
    }

    func testCatPlacementAndClearBothAutosave() {
        let store = InMemoryGameProgressStore()
        let session = startedSession(store: store)

        session.gameViewModel?.toggleCat(atRow: 0, column: 1)
        XCTAssertEqual(
            store.progress.activeGame?.states[index(row: 0, column: 1)],
            .cat
        )

        session.gameViewModel?.toggleCat(atRow: 0, column: 1)
        XCTAssertEqual(
            store.progress.activeGame?.states[index(row: 0, column: 1)],
            .empty
        )
    }

    func testUndoAutosavesRestoredState() {
        let store = InMemoryGameProgressStore()
        let session = startedSession(store: store)
        session.gameViewModel?.toggleExcluded(atRow: 1, column: 2)

        session.gameViewModel?.undo()

        XCTAssertEqual(
            store.progress.activeGame?.states[index(row: 1, column: 2)],
            .empty
        )
    }

    func testRestartAfterResumeRestoresAndSavesEmptyLevel() {
        var states = emptySavedStates()
        states[index(row: 2, column: 2)] = .excluded
        let store = InMemoryGameProgressStore(
            progress: GameProgress(
                activeGame: SavedGame(levelID: "meadow", states: states),
                completedLevelIDs: []
            )
        )
        let session = AppSession(progressStore: store)

        session.gameViewModel?.restart()

        XCTAssertEqual(session.gameViewModel?.puzzle.states, emptyCellStates())
        XCTAssertEqual(store.progress.activeGame?.states, emptySavedStates())
        XCTAssertEqual(session.gameViewModel?.canUndo, false)
    }

    func testCompletingLevelClearsActiveGameAndRecordsCompletion() {
        let store = InMemoryGameProgressStore()
        let session = startedSession(store: store)

        solveMeadow(in: session)

        XCTAssertNil(store.progress.activeGame)
        XCTAssertEqual(store.progress.completedLevelIDs, ["meadow"])
        XCTAssertEqual(session.destination, .playing)
        XCTAssertEqual(session.gameViewModel?.isSolved, true)
    }

    func testContinueAfterCompletionOffersRiver() {
        let store = InMemoryGameProgressStore()
        let session = startedSession(store: store)
        solveMeadow(in: session)

        session.continueAfterCompletion()

        XCTAssertEqual(session.destination, .readyForNextLevel)
        XCTAssertEqual(session.nextLevel?.id, "river")
    }

    func testAllCompletedProgressShowsCompletionState() {
        let store = InMemoryGameProgressStore(
            progress: GameProgress(
                activeGame: nil,
                completedLevelIDs: ["meadow", "river", "terraces"]
            )
        )

        let session = AppSession(progressStore: store)

        XCTAssertEqual(session.destination, .allCompleted)
        XCTAssertNil(session.nextLevel)
    }

    func testUnknownActiveLevelIsDiscardedWhileCompletedLevelsRemain() {
        let store = InMemoryGameProgressStore(
            progress: GameProgress(
                activeGame: SavedGame(
                    levelID: "removed-level",
                    states: emptySavedStates()
                ),
                completedLevelIDs: ["meadow"]
            )
        )

        let session = AppSession(progressStore: store)

        XCTAssertEqual(session.destination, .readyForNextLevel)
        XCTAssertEqual(session.nextLevel?.id, "river")
        XCTAssertNil(store.progress.activeGame)
        XCTAssertEqual(store.progress.completedLevelIDs, ["meadow"])
    }

    func testActiveGameWithWrongStateCountIsDiscarded() {
        let store = InMemoryGameProgressStore(
            progress: GameProgress(
                activeGame: SavedGame(
                    levelID: "meadow",
                    states: [.excluded]
                ),
                completedLevelIDs: []
            )
        )

        let session = AppSession(progressStore: store)

        XCTAssertEqual(session.destination, .readyForNextLevel)
        XCTAssertEqual(session.nextLevel?.id, "meadow")
        XCTAssertNil(store.progress.activeGame)
    }

    func testCorruptStoredJSONFallsBackToFirstLevelWithoutCrashing() {
        let suiteName = "CatPuzzleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(Data("not-json".utf8), forKey: "gameProgress")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let session = AppSession(
            progressStore: UserDefaultsGameProgressStore(defaults: defaults)
        )

        XCTAssertEqual(session.destination, .readyForNextLevel)
        XCTAssertEqual(session.nextLevel?.id, "meadow")
    }

    private func startedSession(
        store: InMemoryGameProgressStore
    ) -> AppSession {
        let session = AppSession(progressStore: store)
        session.startNextLevel()
        return session
    }

    private func solveMeadow(in session: AppSession) {
        for position in BuiltInLevels.meadowFixture.solution {
            session.gameViewModel?.toggleCat(
                atRow: position.row,
                column: position.column
            )
        }
    }

    private func emptySavedStates() -> [SavedCellState] {
        Array(repeating: .empty, count: 36)
    }

    private func emptyCellStates() -> [CellState] {
        Array(repeating: .empty, count: 36)
    }

    private func index(row: Int, column: Int) -> Int {
        row * 6 + column
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
