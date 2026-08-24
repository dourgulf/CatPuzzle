import SwiftUI

struct AllLevelsCompleteView: View {
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(CatPuzzleTheme.surface)
                    .frame(width: 132, height: 132)
                    .shadow(
                        color: CatPuzzleTheme.textPrimary.opacity(0.10),
                        radius: 18,
                        y: 8
                    )

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(CatPuzzleTheme.action)
            }

            VStack(spacing: 8) {
                Text("All Levels Complete")
                    .font(.largeTitle.bold())
                Text("Every cat has found its perfect place.")
                    .font(.body)
                    .foregroundStyle(CatPuzzleTheme.textSecondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(32)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("all-levels-complete")
    }
}
