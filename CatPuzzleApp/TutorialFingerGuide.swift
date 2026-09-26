import CatPuzzleCore
import SwiftUI

/// Demonstrates taps and the first column’s continuous downward drag.
/// For other exclusions, the hand moves to each
/// remaining cell as the player marks the previous one and stays there until
/// they act. Placement repeats a double-tap pulse until the step changes. Discovery has no hand.
struct TutorialFingerGuide: View {
    let task: TutorialTask
    let target: CellPosition?
    let cellFrames: [CellPosition: CGRect]
    let playbackID: Int
    var dragEnd: CellPosition? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 0
    @State private var dragProgress: CGFloat = 0

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
                    .position(
                        x: frame.midX,
                        y: frame.midY + ((dragEnd.flatMap { cellFrames[$0] }?.midY ?? frame.midY) - frame.midY) * dragProgress
                    )
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
        dragProgress = 0
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

        if let dragEnd, dragEnd != target {
            // Removing this guide when dragging starts cancels the loop.
            while !Task.isCancelled {
                dragProgress = 0
                withAnimation(.easeOut(duration: 0.2)) { opacity = 1 }
                withAnimation(.easeInOut(duration: 0.15)) { scale = 0.78 }
                if await sleep(.milliseconds(350)) { return }
                withAnimation(.easeInOut(duration: 1.4)) { dragProgress = 1 }
                if await sleep(.milliseconds(1450)) { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    scale = 1
                    opacity = 0
                }
                if await sleep(.milliseconds(650)) { return }
            }
            return
        }

        repeat {
            for _ in 0..<(isDoubleTap ? 2 : 1) {
                withAnimation(.easeInOut(duration: 0.11)) { scale = 0.78 }
                if await sleep(.milliseconds(120)) { return }
                withAnimation(.easeInOut(duration: 0.11)) { scale = 1 }
                if await sleep(.milliseconds(150)) { return }
            }

            // Keep the hand visible between pairs; a successful placement
            // changes playbackID and cancels this task before the next pair.
            if isDoubleTap, await sleep(.milliseconds(850)) { return }
        } while isDoubleTap && !Task.isCancelled

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
