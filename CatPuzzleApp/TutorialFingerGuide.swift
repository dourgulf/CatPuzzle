import CatPuzzleCore
import SwiftUI

/// Demonstrates the next guided move. For exclusions, the hand moves to each
/// remaining cell as the player marks the previous one and stays there until
/// they act. Placement shows a double-tap pulse once. Discovery has no hand.
struct TutorialFingerGuide: View {
    let task: TutorialTask
    let target: CellPosition?
    let cellFrames: [CellPosition: CGRect]
    let playbackID: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 0

    private var isDoubleTap: Bool {
        if case .placeCat = task { return true }
        return false
    }

    private var currentFrame: CGRect? {
        target.flatMap { cellFrames[$0] }
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
                    .animation(.easeInOut(duration: 0.22), value: target)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: playbackID) {
            await play()
        }
    }

    @MainActor
    private func play() async {
        guard currentFrame != nil else {
            opacity = 0
            return
        }
        if reduceMotion {
            opacity = 1
            scale = 1
            return
        }

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

        if isDoubleTap {
            if await sleep(.milliseconds(260)) { return }
            withAnimation(.easeIn(duration: 0.18)) { opacity = 0 }
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
