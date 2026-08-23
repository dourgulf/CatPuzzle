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

    init(levelID: String, states: [SavedCellState]) {
        self.levelID = levelID
        self.states = states
    }

    init(levelID: String, puzzle: Puzzle) {
        self.levelID = levelID
        states = puzzle.states.map(SavedCellState.init)
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

    static let empty = GameProgress(
        activeGame: nil,
        completedLevelIDs: []
    )
}
