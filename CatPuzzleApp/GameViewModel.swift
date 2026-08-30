import Combine
import CatPuzzleCore

enum CellTapResolution: Equatable {
    case pendingSingle(token: Int)
    case doubleTap
}

struct CellTapInterpreter {
    private var pendingTokens: [CellPosition: Int] = [:]
    private var nextToken = 0

    mutating func registerTap(at position: CellPosition) -> CellTapResolution {
        if pendingTokens.removeValue(forKey: position) != nil {
            return .doubleTap
        }

        nextToken &+= 1
        pendingTokens[position] = nextToken
        return .pendingSingle(token: nextToken)
    }

    mutating func commitSingle(
        at position: CellPosition,
        token: Int
    ) -> Bool {
        guard pendingTokens[position] == token else { return false }
        pendingTokens.removeValue(forKey: position)
        return true
    }

    mutating func cancelAll() {
        pendingTokens.removeAll()
    }
}

@MainActor
final class GameViewModel: ObservableObject {
    let level: LevelDefinition

    @Published private(set) var mode: GameplayMode
    var allowsUndo: Bool { mode.allowsUndo }

    @Published private(set) var puzzle: Puzzle
    @Published private(set) var canUndo: Bool
    @Published private(set) var isSolved: Bool
    @Published private(set) var isFailed: Bool
    @Published private(set) var mistakeCount: Int
    @Published private(set) var remainingMistakes: Int
    @Published private(set) var feedbackMessage: String?
    @Published private(set) var previewStates: [CellPosition: CellState] = [:]
    @Published private(set) var markerFeedbackSequence = 0
    @Published private(set) var hint: LogicalHint?

    var mistakeSummary: String {
        "Mistakes: \(mistakeCount) / \(level.maxMistakes)"
    }

    private var engine: GameEngine
    private var tapInterpreter = CellTapInterpreter()
    private var pendingTapTasks: [CellPosition: Task<Void, Never>] = [:]
    private var pendingPreviewSounds: [CellPosition: PuzzleSound] = [:]
    private let doubleTapInterval: Duration
    private let soundPlayer: any PuzzleSoundPlaying
    private let onGameStateChanged: (GameState) -> Void

    convenience init(
        level: LevelDefinition = BuiltInLevels.meadow,
        doubleTapInterval: Duration = .milliseconds(300),
        soundPlayer: any PuzzleSoundPlaying = PuzzleSoundPlayer.shared,
        onGameStateChanged: @escaping (GameState) -> Void = { _ in }
    ) throws {
        try self.init(
            engine: GameEngine(level: level),
            doubleTapInterval: doubleTapInterval,
            soundPlayer: soundPlayer,
            onGameStateChanged: onGameStateChanged
        )
    }

    init(
        engine: GameEngine,
        doubleTapInterval: Duration = .milliseconds(300),
        soundPlayer: any PuzzleSoundPlaying = PuzzleSoundPlayer.shared,
        onGameStateChanged: @escaping (GameState) -> Void = { _ in }
    ) {
        self.engine = engine
        self.level = engine.state.level
        self.doubleTapInterval = doubleTapInterval
        self.soundPlayer = soundPlayer
        self.onGameStateChanged = onGameStateChanged
        mode = engine.state.mode
        puzzle = engine.state.puzzle
        canUndo = engine.canUndo
        isSolved = engine.state.isSolved
        isFailed = engine.state.isFailed
        mistakeCount = engine.state.mistakeCount
        remainingMistakes = engine.state.remainingMistakes
        feedbackMessage = nil
    }

    func displayState(atRow row: Int, column: Int) -> CellState? {
        let position = CellPosition(row: row, column: column)
        return previewStates[position]
            ?? puzzle.state(atRow: row, column: column)
    }

    func handleCellTap(atRow row: Int, column: Int) {
        guard let currentState = puzzle.state(atRow: row, column: column) else {
            feedbackMessage = "That cell is outside the board."
            return
        }

        let position = CellPosition(row: row, column: column)
        switch tapInterpreter.registerTap(at: position) {
        case let .pendingSingle(token):
            previewStates[position] = excludedToggleResult(for: currentState)
            if let sound = previewExcludedSound(for: currentState) {
                playMarkerFeedback(sound)
                pendingPreviewSounds[position] = sound
            }
            scheduleSingleTapCommit(at: position, token: token)
        case .doubleTap:
            pendingTapTasks.removeValue(forKey: position)?.cancel()
            previewStates.removeValue(forKey: position)
            if let previewSound = pendingPreviewSounds.removeValue(forKey: position) {
                soundPlayer.stop(previewSound)
            }
            applyCatToggle(atRow: row, column: column)
        }
    }

    func toggleExcluded(atRow row: Int, column: Int) {
        cancelPendingTaps()
        applyExcludedToggle(atRow: row, column: column)
    }

    func toggleCat(atRow row: Int, column: Int) {
        cancelPendingTaps()
        applyCatToggle(atRow: row, column: column)
    }

    func setExcludedDuringDrag(
        _ excluded: Bool,
        atRow row: Int,
        column: Int
    ) {
        cancelPendingTaps()
        guard let currentState = puzzle.state(atRow: row, column: column),
              currentState != .cat else {
            return
        }
        apply(excluded ? .excluded : .empty, atRow: row, column: column)
    }

    func undo() {
        cancelPendingTaps()
        hint = nil
        guard engine.undo() else { return }
        feedbackMessage = nil
        synchronizeFromEngine(notifyChange: true)
    }

    func restart() {
        cancelPendingTaps()
        hint = nil
        engine.restart()
        feedbackMessage = nil
        synchronizeFromEngine(notifyChange: true)
    }

    func setMode(_ mode: GameplayMode) {
        cancelPendingTaps()
        hint = nil
        engine.setMode(mode)
        feedbackMessage = nil
        synchronizeFromEngine(notifyChange: true)
    }

    func requestHint() {
        cancelPendingTaps()
        guard !isSolved, !isFailed else { return }
        hint = LogicalHintEngine.nextHint(level: level, puzzle: puzzle)
        feedbackMessage = hint == nil
            ? "No deterministic next step is available from this board."
            : nil
    }

    func dismissHint() {
        hint = nil
    }

    func applyHint() {
        guard let hint else { return }
        cancelPendingTaps()
        let previousPuzzle = engine.state.puzzle
        do {
            try engine.applyHint(hint)
            self.hint = nil
            feedbackMessage = nil
            synchronizeFromEngine(
                notifyChange: engine.state.puzzle != previousPuzzle
            )
            if isSolved || isFailed {
                cancelPendingTaps()
            }
        } catch {
            self.hint = nil
            feedbackMessage = "This hint can no longer be applied."
            synchronizeFromEngine(notifyChange: false)
        }
    }

    private func applyExcludedToggle(
        atRow row: Int,
        column: Int,
        playSound: Bool = true
    ) {
        guard let currentState = puzzle.state(atRow: row, column: column) else {
            feedbackMessage = "That cell is outside the board."
            return
        }

        switch currentState {
        case .empty:
            apply(.excluded, atRow: row, column: column, playSound: playSound)
        case .excluded:
            apply(.empty, atRow: row, column: column, playSound: playSound)
        case .cat:
            feedbackMessage = nil
        }
    }

    private func applyCatToggle(atRow row: Int, column: Int) {
        guard let currentState = puzzle.state(atRow: row, column: column) else {
            feedbackMessage = "That cell is outside the board."
            return
        }

        let nextState: CellState = currentState == .cat ? .empty : .cat
        apply(nextState, atRow: row, column: column)
    }

    private func excludedToggleResult(for state: CellState) -> CellState {
        switch state {
        case .empty:
            .excluded
        case .excluded:
            .empty
        case .cat:
            .cat
        }
    }

    private func previewExcludedSound(for state: CellState) -> PuzzleSound? {
        switch state {
        case .empty:
            .markExcluded
        case .excluded:
            .unmarkExcluded
        case .cat:
            nil
        }
    }

    private func scheduleSingleTapCommit(
        at position: CellPosition,
        token: Int
    ) {
        let interval = doubleTapInterval
        pendingTapTasks[position] = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.commitSingleTap(at: position, token: token)
        }
    }

    private func commitSingleTap(at position: CellPosition, token: Int) {
        guard tapInterpreter.commitSingle(at: position, token: token) else {
            return
        }

        pendingTapTasks.removeValue(forKey: position)
        previewStates.removeValue(forKey: position)
        let alreadyPlayedSound = pendingPreviewSounds.removeValue(forKey: position) != nil
        applyExcludedToggle(
            atRow: position.row,
            column: position.column,
            playSound: !alreadyPlayedSound
        )
    }

    private func cancelPendingTaps() {
        for task in pendingTapTasks.values {
            task.cancel()
        }
        pendingTapTasks.removeAll()
        previewStates.removeAll()
        for sound in pendingPreviewSounds.values {
            soundPlayer.stop(sound)
        }
        pendingPreviewSounds.removeAll()
        tapInterpreter.cancelAll()
    }

    private func apply(
        _ state: CellState,
        atRow row: Int,
        column: Int,
        playSound: Bool = true
    ) {
        do {
            let previousPuzzle = engine.state.puzzle
            let previousCellState = previousPuzzle.state(atRow: row, column: column)
            try engine.setState(state, atRow: row, column: column)
            feedbackMessage = nil
            let puzzleChanged = engine.state.puzzle != previousPuzzle
            synchronizeFromEngine(notifyChange: puzzleChanged)
            if puzzleChanged, playSound {
                playCommittedTransitionSound(
                    from: previousCellState,
                    to: engine.state.puzzle.state(atRow: row, column: column)
                )
            }
            if isSolved || isFailed {
                cancelPendingTaps()
            }
        } catch GameEngineError.illegalCatPlacement {
            feedbackMessage = "That cat conflicts with another cat."
            synchronizeFromEngine(notifyChange: true)
            soundPlayer.play(isFailed ? .gameOver : .catPlacementFailed)
            if isFailed {
                cancelPendingTaps()
            }
        } catch GameEngineError.incorrectCatPlacement {
            feedbackMessage = "That cat is not in the solution."
            synchronizeFromEngine(notifyChange: true)
            soundPlayer.play(isFailed ? .gameOver : .catPlacementFailed)
            if isFailed {
                cancelPendingTaps()
            }
        } catch GameEngineError.gameAlreadyFailed {
            feedbackMessage = "Restart to try again."
        } catch GameEngineError.invalidCell {
            feedbackMessage = "That cell is outside the board."
        } catch {
            feedbackMessage = "Unable to update this cell."
        }
    }

    private func playCommittedTransitionSound(
        from previous: CellState?,
        to next: CellState?
    ) {
        guard let previous,
              let next,
              let sound = PuzzleSound.forCommittedTransition(
                from: previous,
                to: next
              ) else {
            return
        }
        playMarkerFeedback(sound)
    }

    private func playMarkerFeedback(_ sound: PuzzleSound) {
        soundPlayer.play(sound)
        markerFeedbackSequence &+= 1
    }

    private func synchronizeFromEngine(notifyChange: Bool) {
        mode = engine.state.mode
        puzzle = engine.state.puzzle
        canUndo = engine.canUndo
        isSolved = engine.state.isSolved
        isFailed = engine.state.isFailed
        mistakeCount = engine.state.mistakeCount
        remainingMistakes = engine.state.remainingMistakes
        if notifyChange {
            onGameStateChanged(engine.state)
        }
    }
}
