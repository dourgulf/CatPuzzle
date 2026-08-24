import AVFoundation
import CatPuzzleCore
import Foundation

enum PuzzleSound: String, CaseIterable, Equatable, Sendable {
    case markExcluded
    case unmarkExcluded
    case markCat
    case unmarkCat

    var resourceName: String {
        switch self {
        case .markExcluded:
            "sfx_excluded_mark"
        case .unmarkExcluded:
            "sfx_excluded_unmark"
        case .markCat:
            "sfx_cat_mark"
        case .unmarkCat:
            "sfx_cat_unmark"
        }
    }

    static func forCommittedTransition(
        from previous: CellState,
        to next: CellState
    ) -> PuzzleSound? {
        switch (previous, next) {
        case (.empty, .excluded):
            .markExcluded
        case (.excluded, .empty):
            .unmarkExcluded
        case (_, .cat):
            .markCat
        case (.cat, .empty):
            .unmarkCat
        default:
            nil
        }
    }
}

protocol PuzzleSoundPlaying: AnyObject {
    func play(_ sound: PuzzleSound)
}

/// Plays short, original bundled WAV cues. Uses the ambient session so other
/// audio can keep playing and the hardware silent switch is respected.
final class PuzzleSoundPlayer: PuzzleSoundPlaying {
    static let shared = PuzzleSoundPlayer()

    private var players: [PuzzleSound: AVAudioPlayer] = [:]
    private var didConfigureSession = false

    init(bundle: Bundle = Bundle(for: PuzzleSoundPlayer.self)) {
        for sound in PuzzleSound.allCases {
            guard let url = Self.resourceURL(for: sound, in: bundle) else {
                continue
            }
            let player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            players[sound] = player
        }
    }

    func play(_ sound: PuzzleSound) {
        configureSessionIfNeeded()
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }

    static func resourceURL(
        for sound: PuzzleSound,
        in bundle: Bundle = Bundle(for: PuzzleSoundPlayer.self)
    ) -> URL? {
        bundle.url(
            forResource: sound.resourceName,
            withExtension: "wav",
            subdirectory: "Sounds"
        ) ?? bundle.url(
            forResource: sound.resourceName,
            withExtension: "wav"
        )
    }

    private func configureSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
