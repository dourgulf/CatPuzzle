import Foundation

protocol GameProgressStore {
    func loadProgress() throws -> GameProgress
    func saveProgress(_ progress: GameProgress) throws
}

final class UserDefaultsGameProgressStore: GameProgressStore {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        key: String = "gameProgress"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func loadProgress() throws -> GameProgress {
        guard let data = defaults.data(forKey: key) else { return .empty }
        return try decoder.decode(GameProgress.self, from: data)
    }

    func saveProgress(_ progress: GameProgress) throws {
        defaults.set(try encoder.encode(progress), forKey: key)
    }
}
