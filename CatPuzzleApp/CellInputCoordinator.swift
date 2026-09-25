import Foundation
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

/// Turns raw taps and drags into committed board edits. Shares the exact
/// single-tap/double-tap disambiguation and preview-flash timing every
/// board-editing screen must present identically, without owning any
/// engine/domain state itself — the owner supplies the puzzle's current
/// truth and performs the actual commit through `Environment`, so nothing
/// tutorial- or level-specific lives here. `GameViewModel` and
/// `TutorialViewModel` both compose this rather than each reimplementing it.
@MainActor
final class CellInputCoordinator {
    struct Environment {
        var currentState: (CellPosition) -> CellState?
        var isLocked: (CellPosition) -> Bool
        var isInteractable: (CellPosition) -> Bool
        /// Writes `state` to `position` through the owner's own engine call,
        /// exactly like `GameEngine.setState` — including error handling,
        /// undo history and any owner-specific bookkeeping (mistake counts,
        /// tutorial step advancement). `playSound` mirrors the committed
        /// transition sound, not the preview flash this coordinator already
        /// plays itself.
        var commit: (_ state: CellState, _ position: CellPosition, _ playSound: Bool) -> Void
    }

    private(set) var previewStates: [CellPosition: CellState] = [:]
    private var tapInterpreter = CellTapInterpreter()
    private var pendingTapTasks: [CellPosition: Task<Void, Never>] = [:]
    private var pendingPreviewSounds: [CellPosition: PuzzleSound] = [:]
    private let doubleTapInterval: Duration
    private let soundPlayer: any PuzzleSoundPlaying
    /// Fired whenever `previewStates` changes, so the owner can mirror it
    /// into its own `@Published` property for SwiftUI. Set via `configure`
    /// rather than `init`, since a closure capturing the owner's `self`
    /// cannot be built until after the owner has finished initializing —
    /// including assigning this coordinator to its own `input` property.
    private var onPreviewStatesChanged: () -> Void = {}
    /// Fired whenever a preview sound plays, so the owner can bump its own
    /// haptic-trigger counter the same way a committed sound does.
    private var onMarkerFeedback: () -> Void = {}

    init(doubleTapInterval: Duration, soundPlayer: any PuzzleSoundPlaying) {
        self.doubleTapInterval = doubleTapInterval
        self.soundPlayer = soundPlayer
    }

    /// Call once, right after the owner finishes its own `init`, to wire the
    /// callbacks back into `self`.
    func configure(
        onPreviewStatesChanged: @escaping () -> Void,
        onMarkerFeedback: @escaping () -> Void
    ) {
        self.onPreviewStatesChanged = onPreviewStatesChanged
        self.onMarkerFeedback = onMarkerFeedback
    }

    func handleTap(at position: CellPosition, environment: Environment) {
        guard !environment.isLocked(position) else { return }
        guard environment.isInteractable(position) else { return }
        guard let currentState = environment.currentState(position) else { return }

        switch tapInterpreter.registerTap(at: position) {
        case let .pendingSingle(token):
            setPreview(excludedPreviewResult(for: currentState), at: position)
            if let sound = previewExcludedSound(for: currentState) {
                playPreviewSound(sound, at: position)
            }
            scheduleSingleTapCommit(at: position, token: token, environment: environment)
        case .doubleTap:
            pendingTapTasks.removeValue(forKey: position)?.cancel()
            removePreview(at: position)
            if let previewSound = pendingPreviewSounds.removeValue(forKey: position) {
                soundPlayer.stop(previewSound)
            }
            applyCatToggle(at: position, environment: environment)
        }
    }

    func toggleExcluded(at position: CellPosition, environment: Environment) {
        guard !environment.isLocked(position) else { return }
        guard environment.isInteractable(position) else { return }
        cancelAll()
        applyExcludedToggle(at: position, environment: environment, playSound: true)
    }

    func toggleCat(at position: CellPosition, environment: Environment) {
        guard !environment.isLocked(position) else { return }
        guard environment.isInteractable(position) else { return }
        cancelAll()
        applyCatToggle(at: position, environment: environment)
    }

    func setExcludedDuringDrag(
        _ excluded: Bool,
        at position: CellPosition,
        environment: Environment
    ) {
        guard environment.isInteractable(position) else { return }
        cancelAll()
        guard let currentState = environment.currentState(position),
              currentState != .cat,
              !environment.isLocked(position) else {
            return
        }
        environment.commit(excluded ? .excluded : .empty, position, true)
    }

    func cancelAll() {
        for task in pendingTapTasks.values {
            task.cancel()
        }
        pendingTapTasks.removeAll()
        if !previewStates.isEmpty {
            previewStates.removeAll()
            onPreviewStatesChanged()
        }
        for sound in pendingPreviewSounds.values {
            soundPlayer.stop(sound)
        }
        pendingPreviewSounds.removeAll()
        tapInterpreter.cancelAll()
    }

    private func applyExcludedToggle(
        at position: CellPosition,
        environment: Environment,
        playSound: Bool
    ) {
        guard let currentState = environment.currentState(position) else { return }
        switch currentState {
        case .empty:
            environment.commit(.excluded, position, playSound)
        case .excluded:
            environment.commit(.empty, position, playSound)
        case .cat:
            // A no-op write to the cell's own current state: `GameEngine`
            // treats it as a true no-op (no undo entry), but it still lets
            // the owner clear a stale feedback message the same way a real
            // edit would.
            environment.commit(.cat, position, false)
        }
    }

    private func applyCatToggle(at position: CellPosition, environment: Environment) {
        guard let currentState = environment.currentState(position) else { return }
        let nextState: CellState = currentState == .cat ? .empty : .cat
        environment.commit(nextState, position, true)
    }

    private func excludedPreviewResult(for state: CellState) -> CellState {
        switch state {
        case .empty: .excluded
        case .excluded: .empty
        case .cat: .cat
        }
    }

    private func previewExcludedSound(for state: CellState) -> PuzzleSound? {
        switch state {
        case .empty: .markExcluded
        case .excluded: .unmarkExcluded
        case .cat: nil
        }
    }

    private func scheduleSingleTapCommit(
        at position: CellPosition,
        token: Int,
        environment: Environment
    ) {
        let interval = doubleTapInterval
        pendingTapTasks[position] = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.commitSingleTap(at: position, token: token, environment: environment)
        }
    }

    private func commitSingleTap(
        at position: CellPosition,
        token: Int,
        environment: Environment
    ) {
        guard tapInterpreter.commitSingle(at: position, token: token) else {
            return
        }

        pendingTapTasks.removeValue(forKey: position)
        removePreview(at: position)
        let alreadyPlayedSound = pendingPreviewSounds.removeValue(forKey: position) != nil
        applyExcludedToggle(
            at: position,
            environment: environment,
            playSound: !alreadyPlayedSound
        )
    }

    private func setPreview(_ state: CellState, at position: CellPosition) {
        previewStates[position] = state
        onPreviewStatesChanged()
    }

    private func removePreview(at position: CellPosition) {
        guard previewStates.removeValue(forKey: position) != nil else { return }
        onPreviewStatesChanged()
    }

    private func playPreviewSound(_ sound: PuzzleSound, at position: CellPosition) {
        soundPlayer.play(sound)
        pendingPreviewSounds[position] = sound
        onMarkerFeedback()
    }
}
