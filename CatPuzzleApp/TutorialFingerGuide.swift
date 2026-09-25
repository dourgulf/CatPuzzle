import CatPuzzleCore
import SwiftUI

/// A one-shot demonstration of the gesture a guided step is asking for: a
/// double-tap pulse over a `.placeCat` cell, or a sequential single-tap pulse
/// over each cell of a multi-cell `.exclude`. Plays once whenever
/// `playbackID` changes — the caller passes `TutorialViewModel.stepNumber`,
/// so a fresh guided step always replays it from the start — and disappears
/// once it has walked every target cell. `.discovery` steps never construct
/// this view; they keep the existing stall-triggered nudge instead.
struct TutorialFingerGuide: View {
    let task: TutorialTask
    let cellFrames: [CellPosition: CGRect]
    let playbackID: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var targetIndex = 0
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 0

    private var targets: [CellPosition] { task.positions }

    private var isDoubleTap: Bool {
        if case .placeCat = task { return true }
        return false
    }

    private var currentFrame: CGRect? {
        guard targets.indices.contains(targetIndex) else { return nil }
        return cellFrames[targets[targetIndex]]
    }

    var body: some View {
        Group {
            if let frame = currentFrame {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: playbackID) {
            guard !reduceMotion else { return }
            await play()
        }
    }

    @MainActor
    private func play() async {
        opacity = 0
        for index in targets.indices {
            targetIndex = index
            guard currentFrame != nil else { continue }

            scale = 1.25
            withAnimation(.easeOut(duration: 0.2)) {
                opacity = 1
                scale = 1
            }
            if await sleep(.milliseconds(220)) { return }

            for _ in 0..<(isDoubleTap ? 2 : 1) {
                withAnimation(.easeInOut(duration: 0.11)) { scale = 0.78 }
                if await sleep(.milliseconds(120)) { return }
                withAnimation(.easeInOut(duration: 0.11)) { scale = 1 }
                if await sleep(.milliseconds(150)) { return }
            }

            if await sleep(.milliseconds(260)) { return }
            withAnimation(.easeIn(duration: 0.18)) { opacity = 0 }
            if await sleep(.milliseconds(200)) { return }
        }
    }

    /// Sleeps for `duration`, returning `true` if the surrounding `.task`
    /// was cancelled (a new step started) so the caller can stop mid-sequence
    /// instead of animating a demonstration nobody is looking at anymore.
    private func sleep(_ duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return false
        } catch {
            return true
        }
    }
}
