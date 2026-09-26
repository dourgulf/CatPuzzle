import CatPuzzleCore
import Foundation

/// How a level is introduced and labelled. Shipped levels are generated and
/// have slug ids, so nothing in a `LevelDefinition` is fit to show a player;
/// this is what the screens read instead.
struct LevelPresentation: Equatable {
    let title: String
    var levelNumber: Int? = nil
    /// The tutorial is the one level the screens treat differently: it is
    /// coached step by step, and it has no mistake counter to show. Which
    /// rule is on screen is a property of the current `TutorialStep`, not of
    /// the level, so it is not here.
    let isTutorial: Bool

    func localizedTitle(locale: Locale) -> String {
        if let levelNumber { return L10n.format("Level %@", [String(levelNumber)], locale: locale) }
        return L10n.text(title, locale: locale)
    }

    static let tutorial = LevelPresentation(title: "Tutorial", isTutorial: true)

    static func ladder(number: Int) -> LevelPresentation {
        LevelPresentation(title: "Level \(number)", levelNumber: number, isTutorial: false)
    }

    /// A board outside progression entirely — an imported screenshot or a
    /// generator candidate being play-tested.
    static func scratch(title: String) -> LevelPresentation {
        LevelPresentation(title: title, isTutorial: false)
    }
}

extension PuzzleRule {
    /// One line naming the rule, used as the headline of every tutorial step
    /// that turns on it.
    var headline: String {
        switch self {
        case .oneCatPerRowAndColumn: "One cat in every row and column"
        case .oneCatPerRegion: "One cat in every colored block"
        case .noTouchingCats: "Cats never sit next to each other"
        }
    }

    /// Matches the badge in `GameScreen`'s rule reminder, so the rule a step
    /// is teaching can be highlighted there.
    var badgeText: String {
        switch self {
        case .oneCatPerRowAndColumn: "1 per row & column"
        case .oneCatPerRegion: "1 per region"
        case .noTouchingCats: "No touching"
        }
    }
}
