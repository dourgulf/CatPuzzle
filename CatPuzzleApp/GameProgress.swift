import CatPuzzleCore

enum SavedCellState: String, Codable, Equatable {
    case empty
    case excluded
    case cat

    init(_ state: CellState) {
        switch state {
        case .empty: self = .empty
        case .excluded: self = .excluded
        case .cat: self = .cat
        }
    }

    var cellState: CellState {
        switch self {
        case .empty: .empty
        case .excluded: .excluded
        case .cat: .cat
        }
    }
}

struct SavedGame: Codable, Equatable {
    let levelID: String
    let states: [SavedCellState]
    let mistakeCount: Int
    let mode: GameplayMode

    init(
        levelID: String,
        states: [SavedCellState],
        mistakeCount: Int = 0,
        mode: GameplayMode = .exploration
    ) {
        self.levelID = levelID
        self.states = states
        self.mistakeCount = mistakeCount
        self.mode = mode
    }

    init(
        levelID: String,
        puzzle: Puzzle,
        mistakeCount: Int,
        mode: GameplayMode
    ) {
        self.levelID = levelID
        states = puzzle.states.map(SavedCellState.init)
        self.mistakeCount = mistakeCount
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey {
        case levelID
        case states
        case mistakeCount
        case mode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        levelID = try container.decode(String.self, forKey: .levelID)
        states = try container.decode([SavedCellState].self, forKey: .states)
        mistakeCount = try container.decode(Int.self, forKey: .mistakeCount)
        mode = try container.decodeIfPresent(GameplayMode.self, forKey: .mode)
            ?? .exploration
    }

    func makePuzzle(for level: LevelDefinition) throws -> Puzzle {
        guard level.id == levelID else {
            throw SavedGameError.levelMismatch
        }
        guard states.count == level.size * level.size else {
            throw SavedGameError.invalidStateCount
        }

        let restoredStates = stride(from: 0, to: states.count, by: level.size)
            .map { startIndex in
                states[startIndex..<(startIndex + level.size)].map(\.cellState)
            }
        return try Puzzle(
            size: level.size,
            regionIDs: level.regionIDs,
            states: restoredStates
        )
    }
}

enum SavedGameError: Error, Equatable {
    case levelMismatch
    case invalidStateCount
}

struct GameProgress: Codable, Equatable {
    var activeGame: SavedGame?
    var completedLevelIDs: Set<String>
    /// Tutorial levels are played once, ever. Kept apart from
    /// `completedLevelIDs` because that set is cleared every time the ladder
    /// loops, and the tutorial must not come back with it.
    var completedTutorialIDs: Set<String>
    var preferredMode: GameplayMode
    var showsRegionIcons: Bool

    static let empty = GameProgress(
        activeGame: nil,
        completedLevelIDs: [],
        completedTutorialIDs: [],
        preferredMode: .challenge,
        showsRegionIcons: false
    )

    init(
        activeGame: SavedGame?,
        completedLevelIDs: Set<String>,
        completedTutorialIDs: Set<String> = [],
        preferredMode: GameplayMode = .challenge,
        showsRegionIcons: Bool = false
    ) {
        self.activeGame = activeGame
        self.completedLevelIDs = completedLevelIDs
        self.completedTutorialIDs = completedTutorialIDs
        self.preferredMode = preferredMode
        self.showsRegionIcons = showsRegionIcons
    }

    private enum CodingKeys: String, CodingKey {
        case activeGame
        case completedLevelIDs
        case completedTutorialIDs
        case preferredMode
        case showsRegionIcons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeGame = try container.decodeIfPresent(
            SavedGame.self,
            forKey: .activeGame
        )
        completedLevelIDs = try container.decode(
            Set<String>.self,
            forKey: .completedLevelIDs
        )
        // Absent for players whose progress predates the tutorial: they have
        // already been playing, so replaying the introduction would be noise.
        completedTutorialIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .completedTutorialIDs
        ) ?? (completedLevelIDs.isEmpty ? [] : Set(TutorialLevels.all.map(\.level.id)))
        preferredMode = try container.decodeIfPresent(
            GameplayMode.self,
            forKey: .preferredMode
        ) ?? activeGame?.mode ?? .challenge
        showsRegionIcons = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsRegionIcons
        ) ?? false
    }
}
