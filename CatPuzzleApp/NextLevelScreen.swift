import SwiftUI

struct NextLevelScreen: View {
    @Environment(\.locale) private var locale
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
                Text(LocalizedStringKey(presentation.isTutorial ? "LEARN THE RULES" : "NEXT LEVEL"))
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(CatPuzzleTheme.textSecondary)
                Text(presentation.localizedTitle(locale: locale))
                    .font(.largeTitle.bold())

                if presentation.isTutorial {
                    Text("Three rules, one board")
                        .font(.headline)
                        .foregroundStyle(CatPuzzleTheme.action)
                    Text("Start with one cat. Mark its row, column, and corners, then find the rest.")
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
                Label(LocalizedStringKey(presentation.isTutorial ? "Start Tutorial" : "Start"), systemImage: "play.fill")
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
