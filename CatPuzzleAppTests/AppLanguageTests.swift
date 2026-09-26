import CatPuzzleCore
import Foundation
import XCTest
@testable import CatPuzzle

@MainActor
final class AppLanguageTests: XCTestCase {
    func testSystemResolutionAndExplicitOverrides() {
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hans-CN", "en"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["en-US", "zh-Hans"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["fr-FR"]), "en")
        XCTAssertEqual(AppLanguage.english.resolvedIdentifier(preferredLanguages: ["zh-Hans"]), "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.resolvedIdentifier(preferredLanguages: ["en"]), "zh-Hans")
    }

    func testOldAndUnknownLanguagePreferencesKeepProgress() throws {
        let progress = GameProgress(activeGame: nil, completedLevelIDs: ["completed-level"])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(progress)) as? [String: Any])
        json.removeValue(forKey: "language")
        var restored = try JSONDecoder().decode(GameProgress.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.language, .system)
        XCTAssertEqual(restored.completedLevelIDs, progress.completedLevelIDs)
        json["language"] = "future-language"
        restored = try JSONDecoder().decode(GameProgress.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.language, .system)
        XCTAssertEqual(restored.completedLevelIDs, progress.completedLevelIDs)
    }

    func testLanguagePersistsWithoutRecreatingCurrentTutorial() throws {
        let suite = "CatPuzzle.language-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsGameProgressStore(defaults: defaults)
        let fixture = TutorialLevels.basics.fixture
        var engine = try GameEngine(fixture: fixture, mode: .challenge)
        let firstCat = try XCTUnwrap(TutorialLevels.basics.script.steps.first?.task.positions.first)
        try engine.setState(.cat, atRow: firstCat.row, column: firstCat.column)
        let saved = SavedGame(levelID: fixture.level.id, puzzle: engine.state.puzzle, mistakeCount: 0, mode: .challenge)
        try store.saveProgress(GameProgress(activeGame: saved, completedLevelIDs: []))
        let session = AppSession(progressStore: store)
        let tutorial = try XCTUnwrap(session.tutorialViewModel)
        for language in [AppLanguage.simplifiedChinese, .english, .system] {
            session.setLanguage(language)
            XCTAssertTrue(session.tutorialViewModel === tutorial)
            XCTAssertEqual(session.tutorialViewModel?.puzzle, engine.state.puzzle)
            XCTAssertEqual(try store.loadProgress().language, language)
            XCTAssertEqual(AppSession(progressStore: store).language, language)
        }
    }

    func testChineseResourcesAndFormattedTextCanSwitchBackToEnglish() {
        let chinese = Locale(identifier: "zh-Hans")
        let english = Locale(identifier: "en")
        XCTAssertEqual(L10n.text("Settings", locale: chinese), "设置")
        XCTAssertEqual(L10n.text("One color, one cat", locale: chinese), "每种颜色一只猫")
        XCTAssertEqual(L10n.text("Hold & drag down ↓", locale: chinese), "按住向下拖动 ↓")
        XCTAssertEqual(LevelPresentation.ladder(number: 12).localizedTitle(locale: chinese), "第 12 关")
        XCTAssertEqual(LevelPresentation.ladder(number: 12).localizedTitle(locale: english), "Level 12")
        XCTAssertEqual(L10n.text("Reset Progress", locale: chinese), "重置进度")
        XCTAssertEqual(L10n.text("Start at Level", locale: chinese), "从指定关卡开始")
        XCTAssertEqual(L10n.text("Reset Progress", locale: english), "Reset Progress")
        let resetMessage = "Restart at level %@? This clears the current board and marks the tutorial and earlier levels complete."
        XCTAssertTrue(L10n.format(resetMessage, ["12"], locale: chinese).contains("第 12 关"))
        XCTAssertTrue(L10n.format(resetMessage, ["12"], locale: english).contains("level 12"))
        XCTAssertEqual(HintDescription.constraintName(.row(2), false, locale: chinese), "第 3 行")
        XCTAssertEqual(L10n.text("Settings", locale: english), "Settings")
        XCTAssertTrue(ScreenshotImportCopy.message(for: ScreenshotTranscriptionError.unsupportedBoardSize(14), locale: chinese).contains("14×14"))
    }
}
