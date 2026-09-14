/// A screenshot turned into something playable.
public struct ImportedScreenshotLevel: Equatable, Sendable {
    /// The level and its certified unique solution.
    public let fixture: LevelFixture
    /// The board as the screenshot left it: the marks that survived
    /// reconciliation against the solution, ready to hand to `GameEngine`.
    public let puzzle: Puzzle
    /// What was read off the screen, before reconciliation.
    public let board: TranscribedScreenshotBoard

    /// Cats in the screenshot that the certified solution says are wrong.
    /// Dropped rather than rejected: they are either a genuine mistake by
    /// whoever took the screenshot or a misread cell, and neither is a
    /// reason to refuse the import — but the player should be told.
    public let discardedCats: [CellPosition]
    /// ✕ marks that sit on a solution cell, dropped for the same reason.
    public let discardedExclusions: [CellPosition]

    public var level: LevelDefinition { fixture.level }
    public var isAlreadySolved: Bool {
        puzzle.states.count { $0 == .cat } == fixture.level.size
    }
    public var hasCorrections: Bool {
        !discardedCats.isEmpty || !discardedExclusions.isEmpty
    }
}

public enum ScreenshotImportError: Error, Equatable, Sendable {
    case transcription(ScreenshotTranscriptionError)
    /// The Region layout came back malformed — almost always a misread board.
    case invalidLevel(LevelValidationError)
    case noSolution
    case multipleSolutions
    /// The search ran out of budget before proving anything either way.
    case searchInconclusive
}

/// Builds a playable level from a screenshot of one.
///
/// The screenshot is the only input, so nothing about it can be trusted until
/// it is proved: the transcription is certified against `PuzzleSolver` and
/// only accepted if the Region layout has exactly one solution. The marks
/// drawn on the board are then reconciled against that solution, so the
/// imported game is always winnable from where it starts — a screenshot with
/// a wrong cat in it becomes a playable board, not a dead end.
public enum ScreenshotLevelImporter {
    /// Enough for the 12×12 ceiling the transcriber accepts, and small enough
    /// that a screenshot of something that merely looks like a board fails
    /// fast instead of hanging the import.
    public static let defaultBudget = PuzzleSolverBudget(maxVisitedNodes: 2_000_000)

    public static func makeLevel(
        from pixels: ScreenshotPixels,
        id: String = "screenshot",
        maxMistakes: Int = 5,
        budget: PuzzleSolverBudget = defaultBudget
    ) throws -> ImportedScreenshotLevel {
        let board: TranscribedScreenshotBoard
        do {
            board = try ScreenshotBoardTranscriber.transcribe(pixels)
        } catch let error as ScreenshotTranscriptionError {
            throw ScreenshotImportError.transcription(error)
        }
        return try makeLevel(
            from: board,
            id: id,
            maxMistakes: maxMistakes,
            budget: budget
        )
    }

    public static func makeLevel(
        from board: TranscribedScreenshotBoard,
        id: String = "screenshot",
        maxMistakes: Int = 5,
        budget: PuzzleSolverBudget = defaultBudget
    ) throws -> ImportedScreenshotLevel {
        let level = LevelDefinition(
            id: id,
            size: board.size,
            catCount: board.size,
            maxMistakes: maxMistakes,
            regionIDs: board.regionIDs
        )
        do {
            try LevelValidator.validate(level)
        } catch let error as LevelValidationError {
            throw ScreenshotImportError.invalidLevel(error)
        }

        let solution: [CellPosition]
        switch PuzzleSolver.solve(level: level, budget: budget).result {
        case let .unique(cats): solution = cats
        case .none: throw ScreenshotImportError.noSolution
        case .multiple: throw ScreenshotImportError.multipleSolutions
        case .inconclusive: throw ScreenshotImportError.searchInconclusive
        }

        let solutionCells = Set(solution)
        var states = [[CellState]](
            repeating: [CellState](repeating: .empty, count: board.size),
            count: board.size
        )
        var discardedCats: [CellPosition] = []
        var discardedExclusions: [CellPosition] = []

        for row in 0..<board.size {
            for column in 0..<board.size {
                let position = CellPosition(row: row, column: column)
                let isSolutionCell = solutionCells.contains(position)
                switch board.states[row][column] {
                case .cat where isSolutionCell:
                    states[row][column] = .cat
                case .cat:
                    discardedCats.append(position)
                case .excluded where isSolutionCell:
                    discardedExclusions.append(position)
                case .excluded:
                    states[row][column] = .excluded
                case .empty:
                    break
                }
            }
        }

        return ImportedScreenshotLevel(
            fixture: LevelFixture(level: level, solution: solution),
            puzzle: try Puzzle(
                size: board.size,
                regionIDs: board.regionIDs,
                states: states
            ),
            board: board,
            discardedCats: discardedCats,
            discardedExclusions: discardedExclusions
        )
    }
}
