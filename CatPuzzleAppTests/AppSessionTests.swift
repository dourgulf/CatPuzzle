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
        XCTAssertEqual(session.gameViewModel?.mistakeCount, 0)
    }

    func testBlankActiveGameShowsHomeInsteadOfResuming() {
        let store = InMemoryGameProgressStore(
            progress: GameProgress(
                activeGame: SavedGame(
                    levelID: "meadow",
                    states: emptySavedStates(),
                    mistakeCount: 0
                ),
                completedLevelIDs: []
            )
        )

        let session = AppSession(progressStore: store)

        XCTAssertEqual(session.destination, .readyForNextLevel)
        XCTAssertEqual(session.nextLevel?.id, "meadow")
        XCTAssertNil(session.gameViewModel)
        XCTAssertNil(store.progress.activeGame)
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
        XCTAssertEqual(store.progress.activeGame?.mistakeCount, 0)
        XCTAssertEqual(store.progress.activeGame?.mode, .challenge)
        XCTAssertEqual(session.gameViewModel?.mode, .challenge)
    }

    func testStartingExplorationPersistsModeAndRestoresIt() {
        let store = InMemoryGameProgressStore()
        let session = AppSession(progressStore: store)

        session.setGameplayMode(.exploration)
        session.startNextLevel()
        session.gameViewModel?.toggleExcluded(atRow: 1, column: 2)

        let restoredSession = AppSession(progressStore: store)

        XCTAssertEqual(store.progress.activeGame?.mode, .exploration)
        XCTAssertEqual(restoredSession.gameViewModel?.mode, .exploration)
        restoredSession.gameViewModel?.toggleExcluded(atRow: 2, column: 2)
        XCTAssertTrue(restoredSession.gameViewModel?.canUndo == true)
    }

    func testChallengeWrongCatAutosavesMistakeWithoutChangingCell() {
        let store = InMemoryGameProgressStore()
        let session = AppSession(progressStore: store)
        session.startNextLevel()

        session.gameViewModel?.toggleCat(atRow: 0, column: 0)

        XCTAssertEqual(store.progress.activeGame?.mistakeCount, 1)
        XCTAssertEqual(
            store.progress.activeGame?.states[index(row: 0, column: 0)],
            .empty
        )
        XCTAssertFalse(session.gameViewModel?.canUndo == true)
    }

    func testSettingsModeChangeUpdatesActiveGameAndPersistsPreference() {
        let store = InMemoryGameProgressStore()
        let session = AppSession(progressStore: store)
        session.startNextLevel()

        session.setGameplayMode(.exploration)
        session.gameViewModel?.toggleExcluded(atRow: 2, column: 2)

        XCTAssertEqual(session.gameplayMode, .exploration)
        XCTAssertEqual(session.gameViewModel?.mode, .exploration)
        XCTAssertTrue(session.gameViewModel?.canUndo == true)
        XCTAssertEqual(store.progress.preferredMode, .exploration)
        XCTAssertEqual(store.progress.activeGame?.mode, .exploration)
    }

    func testRegionIconsAreHiddenByDefaultAndPreferencePersists() {
        let store = InMemoryGameProgressStore()
        let session = AppSession(progressStore: store)

        XCTAssertFalse(session.showsRegionIcons)

        session.setShowsRegionIcons(true)
        let restoredSession = AppSession(progressStore: store)

        XCTAssertTrue(store.progress.showsRegionIcons)
        XCTAssertTrue(restoredSession.showsRegionIcons)
    }

    func testSettingsRestartClearsCurrentBoardAndMistakes() {
        let store = InMemoryGameProgressStore()
        let session = startedSession(store: store)
        session.gameViewModel?.toggleExcluded(atRow: 2, column: 2)

        session.restartCurrentGame()

        XCTAssertEqual(session.gameViewModel?.puzzle.states, emptyCellStates())
        XCTAssertEqual(store.progress.activeGame?.states, emptySavedStates())
        XCTAssertEqual(store.progress.activeGame?.mistakeCount, 0)
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
        XCTAssertEqual(session.gameViewModel?.mistakeCount, 0)
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

    func testNegativePersistedMistakeCountIsDiscarded() {
        let store = InMemoryGameProgressStore(
            progress: GameProgress(
                activeGame: SavedGame(
                    levelID: "meadow",
                    states: emptySavedStates(),
                    mistakeCount: -1
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

    func testIllegalPlacementAutosavesMistakeCount() {
        let store = InMemoryGameProgressStore()
        let session = startedSession(store: store)
        session.gameViewModel?.toggleCat(atRow: 0, column: 0)

        session.gameViewModel?.toggleCat(atRow: 0, column: 4)

        XCTAssertEqual(store.progress.activeGame?.mistakeCount, 1)
        XCTAssertEqual(
            store.progress.activeGame?.states[index(row: 0, column: 4)],
            .empty
        )
    }

    func testMistakeCountAndFailedStateRestoreAfterRelaunch() {
        let store = InMemoryGameProgressStore()
        let firstSession = startedSession(store: store)
        firstSession.gameViewModel?.toggleCat(atRow: 0, column: 0)
        for _ in 0..<BuiltInLevels.meadow.maxMistakes {
            firstSession.gameViewModel?.toggleCat(atRow: 0, column: 4)
        }

        let restoredSession = AppSession(progressStore: store)

        XCTAssertEqual(
            restoredSession.gameViewModel?.mistakeCount,
            BuiltInLevels.meadow.maxMistakes
        )
        XCTAssertEqual(restoredSession.gameViewModel?.isFailed, true)
        XCTAssertEqual(restoredSession.destination, .playing)
        XCTAssertNotNil(store.progress.activeGame)
        XCTAssertTrue(store.progress.completedLevelIDs.isEmpty)
    }

    func testRestartAfterFailureClearsPersistedMistakesAndBoard() {
        let store = InMemoryGameProgressStore()
        let session = startedSession(store: store)
        session.gameViewModel?.toggleCat(atRow: 0, column: 0)
        for _ in 0..<BuiltInLevels.meadow.maxMistakes {
            session.gameViewModel?.toggleCat(atRow: 0, column: 4)
        }

        session.gameViewModel?.restart()

        XCTAssertEqual(session.gameViewModel?.mistakeCount, 0)
        XCTAssertEqual(session.gameViewModel?.isFailed, false)
        XCTAssertEqual(store.progress.activeGame?.mistakeCount, 0)
        XCTAssertEqual(store.progress.activeGame?.states, emptySavedStates())
        XCTAssertTrue(store.progress.completedLevelIDs.isEmpty)
    }

    private func startedSession(
        store: InMemoryGameProgressStore
    ) -> AppSession {
        let session = AppSession(progressStore: store)
        session.setGameplayMode(.exploration)
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
