import SwiftUI

struct GameScreen: View {
    @ObservedObject var viewModel: GameViewModel
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    ruleReminder

                    BoardView(
                        puzzle: viewModel.puzzle,
                        previewStates: viewModel.previewStates,
                        onTap: viewModel.handleCellTap,
                        onDragSetExcluded: viewModel.setExcludedDuringDrag,
                        onToggleCatAccessibility: viewModel.toggleCat
                    )
                    .frame(maxWidth: 430)
                    .aspectRatio(1, contentMode: .fit)

                    Text("Tap to mark ×  ·  Double-tap to place a paw")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CatPuzzleTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    feedback

                    HStack(spacing: 12) {
                        Button {
                            viewModel.undo()
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 16))
                        .disabled(!viewModel.canUndo)

                        Button {
                            viewModel.restart()
                        } label: {
                            Label("Restart", systemImage: "arrow.clockwise")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 16))
                        .tint(CatPuzzleTheme.textPrimary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .scrollBounceBehavior(.basedOnSize)

            if viewModel.isSolved {
                overlayBackdrop(content: solvedOverlay)
            } else if viewModel.isFailed {
                overlayBackdrop(content: failedOverlay)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CATPUZZLE")
                    .font(.caption2.bold())
                    .tracking(1.5)
                    .foregroundStyle(CatPuzzleTheme.textSecondary)
                Text(viewModel.level.id.capitalized)
                    .font(.title2.bold())
            }

            Spacer()

            Label(viewModel.mistakeSummary, systemImage: "exclamationmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    viewModel.mistakeCount == 0
                        ? CatPuzzleTheme.textPrimary
                        : CatPuzzleTheme.warning
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    CatPuzzleTheme.surface,
                    in: Capsule(style: .continuous)
                )
                .accessibilityIdentifier("mistake-count")
        }
    }

    private var ruleReminder: some View {
        HStack(spacing: 4) {
            RuleBadge(icon: "paintpalette.fill", text: "1 per color")
            RuleBadge(icon: "rectangle.split.3x3.fill", text: "1 per row & column")
            RuleBadge(icon: "square.grid.3x3.fill", text: "No touching")
        }
        .padding(8)
        .background(
            CatPuzzleTheme.surface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CatPuzzleTheme.divider, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let message = viewModel.feedbackMessage {
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(CatPuzzleTheme.warning)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36)
                .accessibilityIdentifier("game-feedback")
        } else {
            Text(" ")
                .frame(minHeight: 36)
                .accessibilityHidden(true)
        }
    }

    private func overlayBackdrop<Content: View>(content: Content) -> some View {
        ZStack {
            CatPuzzleTheme.textPrimary.opacity(0.18)
                .ignoresSafeArea()
            content
        }
    }

    private var solvedOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(CatPuzzleTheme.action)
            Text("Level Complete")
                .font(.title.bold())
                .accessibilityIdentifier("level-complete-message")
            Text("Every rule is satisfied.")
                .font(.body)
                .foregroundStyle(CatPuzzleTheme.textSecondary)
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .accessibilityIdentifier("continue-after-completion")
        }
        .padding(28)
        .background(
            CatPuzzleTheme.surface,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: CatPuzzleTheme.textPrimary.opacity(0.16), radius: 20, y: 10)
    }

    private var failedOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(CatPuzzleTheme.warning)
            Text("Game Over")
                .font(.title.bold())
                .accessibilityIdentifier("game-over-message")
            Text("Restart for a fresh board.")
                .font(.body)
                .foregroundStyle(CatPuzzleTheme.textSecondary)
            Button("Restart") {
                viewModel.restart()
            }
            .buttonStyle(.borderedProminent)
            .tint(CatPuzzleTheme.warning)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .accessibilityIdentifier("restart-after-failure")
        }
        .padding(28)
        .background(
            CatPuzzleTheme.surface,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: CatPuzzleTheme.textPrimary.opacity(0.16), radius: 20, y: 10)
    }
}

private struct RuleBadge: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CatPuzzleTheme.action)
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(CatPuzzleTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
    }
}
