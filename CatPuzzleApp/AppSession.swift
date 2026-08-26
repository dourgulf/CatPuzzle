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

    private let progressStore: any GameProgressStore
    private let progression: LevelProgression
    private var progress: GameProgress

    init(
        progressStore: any GameProgressStore,
        levels: [LevelDefinition] = BuiltInLevels.all
    ) {
        self.progressStore = progressStore
        self.progression = LevelProgression(levels: levels)

        do {
            progress = try progressStore.loadProgress()
        } catch {
            progress = .empty
            try? progressStore.saveProgress(progress)
        }

        let knownLevelIDs = Set(levels.map(\.id))
        progress.completedLevelIDs.formIntersection(knownLevelIDs)
        routeOnLaunch()
    }

    func startNextLevel() {
        guard let level = nextLevel,
              let engine = try? GameEngine(level: level) else { return }

        progress.activeGame = SavedGame(
            levelID: level.id,
            puzzle: engine.state.puzzle,
            mistakeCount: engine.state.mistakeCount
        )
        saveProgress()
        showGame(engine: engine)
        PuzzleSoundPlayer.shared.play(.levelStart)
    }

    func continueAfterCompletion() {
        guard gameViewModel?.isSolved == true else { return }
        showNextDestination()
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
            let puzzle = try savedGame.makePuzzle(for: level)
            let engine = try GameEngine(
                level: level,
                puzzle: puzzle,
                mistakeCount: savedGame.mistakeCount
            )

            if engine.state.isSolved {
                progress.completedLevelIDs.insert(level.id)
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

    private func showGame(engine: GameEngine) {
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

        if gameViewModel.isSolved {
            progress.completedLevelIDs.insert(gameViewModel.level.id)
            progress.activeGame = nil
        } else {
            progress.activeGame = SavedGame(
                levelID: gameViewModel.level.id,
                puzzle: state.puzzle,
                mistakeCount: state.mistakeCount
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
