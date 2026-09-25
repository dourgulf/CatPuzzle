import CatPuzzleCore
import Combine

enum AppDestination: Equatable {
    case tutorial
    case playing
    case readyForNextLevel
    case allCompleted
}

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var destination: AppDestination = .allCompleted
    @Published private(set) var gameViewModel: GameViewModel?
    @Published private(set) var tutorialViewModel: TutorialViewModel?
    @Published private(set) var nextLevel: LevelDefinition?
    /// How `nextLevel` is labelled. Generated levels have slug ids, not names
    /// to show.
    @Published private(set) var nextPresentation: LevelPresentation?
    /// The same, for the level currently being played.
    @Published private(set) var currentPresentation: LevelPresentation?
    @Published private(set) var gameplayMode: GameplayMode = .challenge
    @Published private(set) var showsRegionIcons = false

    private let progressStore: any GameProgressStore
    private let progression: LevelProgression
    private let tutorials: [TutorialLevel]
    private let fixturesByLevelID: [String: LevelFixture]
    /// The scripted lesson for each tutorial board. Only tutorials have one,
    /// which is what makes a level coached rather than merely labelled.
    private let scriptByLevelID: [String: TutorialScript]
    private let presentationByLevelID: [String: LevelPresentation]
    private var progress: GameProgress

    init(
        progressStore: any GameProgressStore,
        fixtures: [LevelFixture] = BuiltInLevels.fixtures,
        tutorials: [TutorialLevel] = TutorialLevels.all
    ) {
        self.progressStore = progressStore
        self.progression = LevelProgression(levels: fixtures.map(\.level))
        self.tutorials = tutorials

        let allFixtures = tutorials.map(\.fixture) + fixtures
        self.fixturesByLevelID = Dictionary(
            allFixtures.map { ($0.level.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        self.scriptByLevelID = Dictionary(
            tutorials.map { ($0.level.id, $0.script) },
            uniquingKeysWith: { first, _ in first }
        )

        var presentations: [String: LevelPresentation] = [:]
        for tutorial in tutorials {
            presentations[tutorial.level.id] = .tutorial
        }
        for (index, fixture) in fixtures.enumerated() {
            presentations[fixture.level.id] = .ladder(number: index + 1)
        }
        self.presentationByLevelID = presentations

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
        progress.completedTutorialIDs.formIntersection(Set(tutorials.map(\.level.id)))
        routeOnLaunch()
    }

    func startNextLevel() {
        guard let level = nextLevel,
              let fixture = fixturesByLevelID[level.id],
              let engine = try? GameEngine(
                  fixture: fixture,
                  mode: mode(forLevelWithID: level.id)
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
        guard gameViewModel?.isSolved == true || tutorialViewModel?.isSolved == true else { return }
        showNextDestination()
    }

    func setGameplayMode(_ mode: GameplayMode) {
        guard gameplayMode != mode else { return }
        gameplayMode = mode
        progress.preferredMode = mode
        // A tutorial stays on its own mode whatever the player prefers; the
        // choice is remembered and takes effect on the next real level.
        // `gameViewModel` is nil during the tutorial (it's driven by
        // `tutorialViewModel` instead), so this naturally falls through.
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
        tutorialViewModel?.restart()
    }

    #if DEBUG
    /// Debug builds only: forget that the tutorial was ever played so it can
    /// be replayed. Any level in progress is abandoned along with it — the
    /// tutorial is offered before anything else, and a saved game left behind
    /// would be resumed on the next launch and hide it again.
    func resetTutorial() {
        progress.completedTutorialIDs.removeAll()
        progress.activeGame = nil
        saveProgress()
        showNextDestination()
    }
    #endif

    private func routeOnLaunch() {
        guard let savedGame = progress.activeGame else {
            showNextDestination()
            return
        }

        do {
            // Looked up across tutorials and ladder alike: an interrupted
            // tutorial has to resume the same way any other level does.
            guard let fixture = fixturesByLevelID[savedGame.levelID] else {
                throw SavedGameError.levelMismatch
            }
            let level = fixture.level
            let puzzle = try savedGame.makePuzzle(for: level)
            let engine = try GameEngine(
                fixture: fixture,
                puzzle: puzzle,
                mistakeCount: savedGame.mistakeCount,
                mode: mode(forLevelWithID: level.id)
            )

            if engine.state.isSolved {
                markCompleted(level.id)
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
        let levelID = engine.state.level.id
        currentPresentation = presentationByLevelID[levelID]
        nextLevel = nil
        nextPresentation = nil

        if let script = scriptByLevelID[levelID], !script.isEmpty {
            gameViewModel = nil
            tutorialViewModel = TutorialViewModel(
                engine: engine,
                script: script,
                soundPlayer: PuzzleSoundPlayer.shared,
                onGameStateChanged: { [weak self] state in
                    self?.handleGameStateChanged(state)
                }
            )
            destination = .tutorial
        } else {
            gameplayMode = engine.state.mode
            progress.preferredMode = engine.state.mode
            tutorialViewModel = nil
            gameViewModel = GameViewModel(
                engine: engine,
                soundPlayer: PuzzleSoundPlayer.shared,
                onGameStateChanged: { [weak self] state in
                    self?.handleGameStateChanged(state)
                }
            )
            destination = .playing
        }
    }

    private func handleGameStateChanged(_ state: GameState) {
        let levelID = state.level.id
        if !isTutorial(levelID) {
            gameplayMode = state.mode
            progress.preferredMode = state.mode
        }

        if state.isSolved {
            markCompleted(levelID)
            progress.activeGame = nil
        } else {
            progress.activeGame = SavedGame(
                levelID: levelID,
                puzzle: state.puzzle,
                mistakeCount: state.mistakeCount,
                mode: state.mode
            )
        }
        saveProgress()
    }

    private func showNextDestination() {
        gameViewModel = nil
        tutorialViewModel = nil
        currentPresentation = nil

        // The tutorial comes first and is played once, ever — it is tracked
        // separately from `completedLevelIDs` so looping the ladder never
        // brings it back.
        if let tutorial = tutorials.first(where: {
            !progress.completedTutorialIDs.contains($0.level.id)
        }) {
            offer(level: tutorial.level)
            return
        }

        // The ladder loops: finishing the last level starts a fresh lap from
        // the first 8x8 rather than ending the game. `.allCompleted` is left
        // for the degenerate case of no levels at all.
        guard let next = progression.nextLevel(
            completedLevelIDs: progress.completedLevelIDs
        ) else {
            nextLevel = nil
            nextPresentation = nil
            destination = .allCompleted
            return
        }

        if next.didWrap {
            progress.completedLevelIDs.removeAll()
            saveProgress()
        }

        offer(level: next.level)
    }

    private func offer(level: LevelDefinition) {
        nextLevel = level
        nextPresentation = presentationByLevelID[level.id]
        destination = .readyForNextLevel
    }

    private func isTutorial(_ levelID: String) -> Bool {
        presentationByLevelID[levelID]?.isTutorial == true
    }

    /// A tutorial is always played in challenge mode, whatever the player
    /// prefers. Challenge mode refuses a cat that is not in the solution
    /// instead of letting it land, which is what keeps the board on the script
    /// — a wrong cat would leave every later step pointing at a deduction that
    /// is no longer there. It cannot be lost either way: the board's mistake
    /// limit is unreachable and `GameScreen` hides the counter.
    private func mode(forLevelWithID levelID: String) -> GameplayMode {
        isTutorial(levelID) ? .challenge : gameplayMode
    }

    private func markCompleted(_ levelID: String) {
        if isTutorial(levelID) {
            progress.completedTutorialIDs.insert(levelID)
        } else {
            progress.completedLevelIDs.insert(levelID)
        }
    }

    private func saveProgress() {
        try? progressStore.saveProgress(progress)
    }
}
