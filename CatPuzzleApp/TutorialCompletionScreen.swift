import SwiftUI

/// The tutorial's one and only celebration — no per-step micro-celebrations,
/// just this single graduation page once the whole script is finished.
struct TutorialCompletionScreen: View {
    let onContinue: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            TutorialTheme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(TutorialTheme.celebration)
                    .scaleEffect(hasAppeared ? 1 : 0.4)
                    .opacity(hasAppeared ? 1 : 0)

                VStack(spacing: 6) {
                    Text("Puzzle solved!")
                        .font(.largeTitle.bold())
                    Text("You used all three rules to find every cat.")
                        .font(.title3)
                        .foregroundStyle(TutorialTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("level-complete-message")

                HStack(spacing: 12) {
                    ruleBadge(icon: "paintpalette.fill", text: "One cat per\ncolored block")
                    ruleBadge(icon: "rectangle.split.3x3.fill", text: "One cat per\nrow & column")
                    ruleBadge(icon: "square.grid.3x3.fill", text: "Cats never\ntouch")
                }

                Button("Start Game", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .tint(TutorialTheme.accent)
                    .controlSize(.large)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .accessibilityIdentifier("continue-after-completion")
            }
            .padding(32)
        }
        .foregroundStyle(TutorialTheme.textPrimary)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
                hasAppeared = true
            }
            // No dedicated graduation sound yet — `testBundledSoundAssetsArePresent`
            // enforces every `PuzzleSound` case ships a real bundled `.wav`, so a
            // `tutorialGraduated` case lands once that asset exists, not before.
        }
    }

    private func ruleBadge(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TutorialTheme.accent)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(TutorialTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(8)
        .background(
            TutorialTheme.surface,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TutorialTheme.accent.opacity(0.6), lineWidth: 1.5)
        }
    }
}
