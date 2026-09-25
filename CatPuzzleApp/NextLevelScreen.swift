import SwiftUI

struct NextLevelScreen: View {
    let presentation: LevelPresentation
    let boardSize: Int
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(CatPuzzleTheme.surface)
                    .frame(width: 116, height: 116)
                    .shadow(
                        color: CatPuzzleTheme.textPrimary.opacity(0.10),
                        radius: 18,
                        y: 8
                    )

                Image(systemName: presentation.isTutorial ? "graduationcap.fill" : "pawprint.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(CatPuzzleTheme.action)
            }

            VStack(spacing: 8) {
                Text(presentation.isTutorial ? "LEARN THE RULES" : "NEXT LEVEL")
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(CatPuzzleTheme.textSecondary)
                Text(presentation.title)
                    .font(.largeTitle.bold())

                if presentation.isTutorial {
                    Text("Three rules, one board")
                        .font(.headline)
                        .foregroundStyle(CatPuzzleTheme.action)
                    Text("I will walk you through the opening moves, then hand the board over to you.")
                        .font(.subheadline)
                        .foregroundStyle(CatPuzzleTheme.textSecondary)
                } else {
                    Text("A fresh \(boardSize)x\(boardSize) puzzle is ready for you.")
                        .font(.body)
                        .foregroundStyle(CatPuzzleTheme.textSecondary)
                }
            }
            .multilineTextAlignment(.center)

            Button(action: onStart) {
                Label(presentation.isTutorial ? "Let's go" : "Start", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .accessibilityIdentifier("start-next-level")
        }
        .frame(maxWidth: 420)
        .padding(32)
    }
}
