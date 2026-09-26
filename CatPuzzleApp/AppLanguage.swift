import Foundation

/// Persist the user's choice, not the currently resolved system language.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Follow System"
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .system:
            Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferredLanguages).first ?? "en"
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        }
    }
}

/// Explicit locale for formatted model text; SwiftUI literals use the same
/// locale through the root environment. No process-wide language mutation.
enum L10n {
    static func text(_ key: String, locale: Locale) -> String {
        let identifier = locale.identifier.hasPrefix("zh") ? "zh-Hans" : "en"
        let bundle = Bundle.main.path(forResource: identifier, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: [String], locale: Locale) -> String {
        String(format: text(key, locale: locale), locale: locale, arguments: arguments)
    }
}
