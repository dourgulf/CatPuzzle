import CatPuzzleCore
import XCTest
@testable import CatPuzzle

final class GameProgressTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CatPuzzleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testEmptyProgressCanBeSavedAndLoaded() throws {
        let store = UserDefaultsGameProgressStore(defaults: defaults)

        try store.saveProgress(.empty)

        XCTAssertEqual(try store.loadProgress(), .empty)
    }

    func testActiveGameAndCompletedLevelsRoundTrip() throws {
        let store = UserDefaultsGameProgressStore(defaults: defaults)
        let progress = GameProgress(
            activeGame: SavedGame(
                levelID: "river",
                states: [.cat, .excluded, .empty],
                mistakeCount: 3,
                mode: .challenge
            ),
            completedLevelIDs: ["meadow"],
            preferredMode: .exploration,
            showsRegionIcons: true
        )

        try store.saveProgress(progress)

        XCTAssertEqual(try store.loadProgress(), progress)
        XCTAssertEqual(
            try store.loadProgress().activeGame?.states,
            [.cat, .excluded, .empty]
        )
        XCTAssertEqual(
            try store.loadProgress().activeGame?.mistakeCount,
            3
        )
        XCTAssertEqual(
            try store.loadProgress().activeGame?.mode,
            .challenge
        )
        XCTAssertEqual(
            try store.loadProgress().preferredMode,
            .exploration
        )
        XCTAssertTrue(try store.loadProgress().showsRegionIcons)
    }

    func testLegacySavedGameWithoutModeDefaultsToExploration() throws {
        let json = """
        {
          "activeGame": {
            "levelID": "meadow",
            "states": ["empty"],
            "mistakeCount": 0
          },
          "completedLevelIDs": []
        }
        """
        defaults.set(Data(json.utf8), forKey: "gameProgress")

        let progress = try UserDefaultsGameProgressStore(
            defaults: defaults
        ).loadProgress()

        XCTAssertEqual(progress.activeGame?.mode, .exploration)
        XCTAssertEqual(progress.preferredMode, .exploration)
    }

    func testLegacyProgressWithoutActiveGameDefaultsToChallenge() throws {
        let json = """
        {
          "activeGame": null,
          "completedLevelIDs": []
        }
        """
        defaults.set(Data(json.utf8), forKey: "gameProgress")

        let progress = try UserDefaultsGameProgressStore(
            defaults: defaults
        ).loadProgress()

        XCTAssertEqual(progress.preferredMode, .challenge)
        XCTAssertFalse(progress.showsRegionIcons)
    }

    func testNextLevelIsMeadowWhenNothingIsCompleted() {
        let progression = LevelProgression(levels: BuiltInLevels.all)

        XCTAssertEqual(
            progression.nextUncompletedLevel(completedLevelIDs: [])?.id,
            "meadow"
        )
    }

    func testNextLevelIsRiverAfterMeadow() {
        let progression = LevelProgression(levels: BuiltInLevels.all)

        XCTAssertEqual(
            progression.nextUncompletedLevel(completedLevelIDs: ["meadow"])?.id,
            "river"
        )
    }

    func testNextLevelIsTerracesAfterMeadowAndRiver() {
        let progression = LevelProgression(levels: BuiltInLevels.all)

        XCTAssertEqual(
            progression.nextUncompletedLevel(
                completedLevelIDs: ["meadow", "river"]
            )?.id,
            "terraces"
        )
    }

    func testNextLevelIsNilWhenAllLevelsAreCompleted() {
        let progression = LevelProgression(levels: BuiltInLevels.all)

        XCTAssertNil(
            progression.nextUncompletedLevel(
                completedLevelIDs: ["meadow", "river", "terraces"]
            )
        )
    }
}
