import SwiftUI

struct GameScreen: View {
    @ObservedObject var viewModel: GameViewModel
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("CatPuzzle")
                        .font(.largeTitle.bold())
                    Text(viewModel.level.id.capitalized)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Text("Tap to mark × · Double-tap to place a paw")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(viewModel.mistakeSummary)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("mistake-count")

                BoardView(
                    puzzle: viewModel.puzzle,
                    onToggleExcluded: viewModel.toggleExcluded,
                    onToggleCat: viewModel.toggleCat
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

                feedback

                HStack(spacing: 16) {
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        viewModel.undo()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canUndo)

                    Button("Restart", systemImage: "arrow.clockwise") {
                        viewModel.restart()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)

            if viewModel.isSolved {
                solvedOverlay
            } else if viewModel.isFailed {
                failedOverlay
            }
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let message = viewModel.feedbackMessage {
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36)
                .accessibilityIdentifier("game-feedback")
        } else {
            Text(" ")
                .frame(minHeight: 36)
                .accessibilityHidden(true)
        }
    }

    private var solvedOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Level Complete")
                .font(.title2.bold())
                .accessibilityIdentifier("level-complete-message")
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("continue-after-completion")
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 12)
    }

    private var failedOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
            Text("Game Over")
                .font(.title2.bold())
                .accessibilityIdentifier("game-over-message")
            Button("Restart") {
                viewModel.restart()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("restart-after-failure")
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 12)
    }
}
