import SwiftUI

struct NextLevelScreen: View {
    let levelName: String
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

                Image(systemName: "pawprint.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(CatPuzzleTheme.action)
            }

            VStack(spacing: 8) {
                Text("NEXT LEVEL")
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(CatPuzzleTheme.textSecondary)
                Text(levelName)
                    .font(.largeTitle.bold())
                Text("A fresh puzzle is ready for you.")
                    .font(.body)
                    .foregroundStyle(CatPuzzleTheme.textSecondary)
            }
            .multilineTextAlignment(.center)

            Button(action: onStart) {
                Label("Start", systemImage: "play.fill")
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
