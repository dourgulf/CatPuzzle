import CatPuzzleCore
import Combine

enum AppDestination: Equatable {
    case playing
    case readyForNextLevel
    case allCompleted
}

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var destination: AppDestination = .allCompleted
    @Published private(set) var gameViewModel: GameViewModel?
    @Published private(set) var nextLevel: LevelDefinition?
    @Published private(set) var gameplayMode: GameplayMode = .challenge
    @Published private(set) var showsRegionIcons = false

    private let progressStore: any GameProgressStore
    private let progression: LevelProgression
    private let fixturesByLevelID: [String: LevelFixture]
    private var progress: GameProgress

    init(
        progressStore: any GameProgressStore,
        fixtures: [LevelFixture] = BuiltInLevels.fixtures
    ) {
        self.progressStore = progressStore
        self.progression = LevelProgression(levels: fixtures.map(\.level))
        self.fixturesByLevelID = Dictionary(
            uniqueKeysWithValues: fixtures.map { ($0.level.id, $0) }
        )

        do {
            progress = try progressStore.loadProgress()
        } catch {
            progress = .empty
            try? progressStore.saveProgress(progress)
        }

        gameplayMode = progress.activeGame?.mode ?? progress.preferredMode
        progress.preferredMode = gameplayMode
        showsRegionIcons = progress.showsRegionIcons

        let knownLevelIDs = Set(fixtures.map(\.level.id))
        progress.completedLevelIDs.formIntersection(knownLevelIDs)
        routeOnLaunch()
    }

    func startNextLevel() {
        guard let level = nextLevel,
              let fixture = fixturesByLevelID[level.id],
              let engine = try? GameEngine(
                  fixture: fixture,
                  mode: gameplayMode
              ) else { return }

        progress.activeGame = SavedGame(
            levelID: level.id,
            puzzle: engine.state.puzzle,
            mistakeCount: engine.state.mistakeCount,
            mode: engine.state.mode
        )
        saveProgress()
        showGame(engine: engine)
        PuzzleSoundPlayer.shared.play(.levelStart)
    }

    func continueAfterCompletion() {
        guard gameViewModel?.isSolved == true else { return }
        showNextDestination()
    }

    func setGameplayMode(_ mode: GameplayMode) {
        guard gameplayMode != mode else { return }
        gameplayMode = mode
        progress.preferredMode = mode
        if let gameViewModel {
            gameViewModel.setMode(mode)
        } else {
            saveProgress()
        }
    }

    func setShowsRegionIcons(_ showsRegionIcons: Bool) {
        guard self.showsRegionIcons != showsRegionIcons else { return }
        self.showsRegionIcons = showsRegionIcons
        progress.showsRegionIcons = showsRegionIcons
        saveProgress()
    }

    func restartCurrentGame() {
        gameViewModel?.restart()
    }

    private func routeOnLaunch() {
        guard let savedGame = progress.activeGame else {
            showNextDestination()
            return
        }

        do {
            guard let level = progression.level(withID: savedGame.levelID) else {
                throw SavedGameError.levelMismatch
            }
            guard let fixture = fixturesByLevelID[level.id] else {
                throw SavedGameError.levelMismatch
            }
            let puzzle = try savedGame.makePuzzle(for: level)
            let engine = try GameEngine(
                fixture: fixture,
                puzzle: puzzle,
                mistakeCount: savedGame.mistakeCount,
                mode: savedGame.mode
            )

            if engine.state.isSolved {
                progress.completedLevelIDs.insert(level.id)
                progress.activeGame = nil
                saveProgress()
                showNextDestination()
            } else if Self.isBlank(savedGame) {
                // No real progress to resume (e.g. restarted, then closed
                // without touching the board again) — show the normal
                // "ready to start" screen instead of jumping straight into
                // an indistinguishable-from-fresh board.
                progress.activeGame = nil
                saveProgress()
                showNextDestination()
            } else {
                showGame(engine: engine)
            }
        } catch {
            progress.activeGame = nil
            saveProgress()
            showNextDestination()
        }
    }

    private static func isBlank(_ savedGame: SavedGame) -> Bool {
        savedGame.mistakeCount == 0
            && savedGame.states.allSatisfy { $0 == .empty }
    }

    private func showGame(engine: GameEngine) {
        gameplayMode = engine.state.mode
        progress.preferredMode = engine.state.mode
        gameViewModel = GameViewModel(
            engine: engine,
            soundPlayer: PuzzleSoundPlayer.shared,
            onGameStateChanged: { [weak self] state in
                self?.handleGameStateChanged(state)
            }
        )
        nextLevel = nil
        destination = .playing
    }

    private func handleGameStateChanged(_ state: GameState) {
        guard let gameViewModel else { return }

        gameplayMode = state.mode
        progress.preferredMode = state.mode

        if gameViewModel.isSolved {
            progress.completedLevelIDs.insert(gameViewModel.level.id)
            progress.activeGame = nil
        } else {
            progress.activeGame = SavedGame(
                levelID: gameViewModel.level.id,
                puzzle: state.puzzle,
                mistakeCount: state.mistakeCount,
                mode: state.mode
            )
        }
        saveProgress()
    }

    private func showNextDestination() {
        gameViewModel = nil
        nextLevel = progression.nextUncompletedLevel(
            completedLevelIDs: progress.completedLevelIDs
        )
        destination = nextLevel == nil ? .allCompleted : .readyForNextLevel
    }

    private func saveProgress() {
        try? progressStore.saveProgress(progress)
    }
}
