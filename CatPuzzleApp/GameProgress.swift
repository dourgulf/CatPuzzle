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

    init(
        levelID: String,
        states: [SavedCellState],
        mistakeCount: Int = 0
    ) {
        self.levelID = levelID
        self.states = states
        self.mistakeCount = mistakeCount
    }

    init(levelID: String, puzzle: Puzzle, mistakeCount: Int) {
        self.levelID = levelID
        states = puzzle.states.map(SavedCellState.init)
        self.mistakeCount = mistakeCount
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
            colorIDs: level.colorIDs,
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

    static let empty = GameProgress(
        activeGame: nil,
        completedLevelIDs: []
    )
}
