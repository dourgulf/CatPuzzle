import CatPuzzleCore
import SwiftUI

struct GameScreen: View {
    @ObservedObject var viewModel: GameViewModel
    let showsRegionIcons: Bool
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
                        showsRegionIcons: showsRegionIcons,
                        hint: viewModel.hint,
                        onTap: viewModel.handleCellTap,
                        onDragSetExcluded: viewModel.setExcludedDuringDrag,
                        onToggleCatAccessibility: viewModel.toggleCat
                    )
                    .frame(maxWidth: 430)
                    .aspectRatio(1, contentMode: .fit)

                    if let hint = viewModel.hint {
                        HintPanel(
                            description: HintDescription.text(for: hint),
                            onApply: viewModel.applyHint,
                            onCancel: viewModel.dismissHint
                        )
                    } else {
                        Text("Tap to mark ×  ·  Double-tap to place a paw")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(CatPuzzleTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    feedback

                    HStack(spacing: 12) {
                        Button {
                            viewModel.requestHint()
                        } label: {
                            Label("Hint", systemImage: "lightbulb.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonBorderShape(.roundedRectangle(radius: 16))
                        .buttonStyle(.bordered)
                        .disabled(viewModel.hint != nil)
                        .accessibilityIdentifier("request-hint")

                        if viewModel.allowsUndo {
                            Button {
                                viewModel.undo()
                            } label: {
                                Label(
                                    "Undo",
                                    systemImage: "arrow.uturn.backward"
                                )
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 50)
                            }
                            .buttonBorderShape(.roundedRectangle(radius: 16))
                            .buttonStyle(.borderedProminent)
                            .disabled(!viewModel.canUndo)
                        }
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
        .sensoryFeedback(.selection, trigger: viewModel.markerFeedbackSequence)
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
                Text(viewModel.mode == .exploration ? "EXPLORE" : "CHALLENGE")
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .foregroundStyle(CatPuzzleTheme.action)
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
        .padding(.trailing, 44)
    }

    private var ruleReminder: some View {
        HStack(spacing: 4) {
            RuleBadge(icon: "paintpalette.fill", text: "1 per region")
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

private struct HintPanel: View {
    let description: String
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Logical Hint", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(CatPuzzleTheme.action)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(CatPuzzleTheme.textSecondary)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("cancel-hint")
                Button("Apply", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("apply-hint")
            }
        }
        .padding(16)
        .background(
            CatPuzzleTheme.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CatPuzzleTheme.divider, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("logical-hint-panel")
    }
}

enum HintDescription {
    static func text(for hint: LogicalHint) -> String {
        switch hint.reason {
        case let .onlyCandidateInRow(row):
            "Row \(row + 1) has only one possible cell left. Place a cat there."
        case let .onlyCandidateInColumn(column):
            "Column \(column + 1) has only one possible cell left. Place a cat there."
        case let .onlyCandidateForRegion(regionID):
            "Region \(regionID + 1) has only one possible cell left. Place a cat there."
        case let .rowAlreadyHasCat(row):
            "Row \(row + 1) already has its cat. Exclude the highlighted cells."
        case let .columnAlreadyHasCat(column):
            "Column \(column + 1) already has its cat. Exclude the highlighted cells."
        case let .regionAlreadyHasCat(regionID):
            "Region \(regionID + 1) already has its cat. Exclude the highlighted cells."
        case .adjacentToConfirmedCat:
            "Cats cannot touch, including diagonally. Exclude the highlighted cells."
        case let .lockedSet(sources, targets):
            "The cats in \(constraintList(sources)) are locked into \(constraintList(targets)). Exclude the highlighted cells."
        case let .commonAttack(constraint, _):
            "Every possible cat in \(constraintName(constraint)) conflicts with the highlighted cell. Exclude it."
        case let .strongLinkCommonElimination(link):
            "One of the two cells in \(constraintName(link.constraint)) must contain a cat. The highlighted cell conflicts with both."
        case .contradictionFromAssumption:
            "That candidate leads to a contradiction, so exclude the highlighted cell."
        }
    }

    private static func constraintList(_ constraints: [ConstraintKind]) -> String {
        constraints.map(constraintName).joined(separator: " and ")
    }

    private static func constraintName(_ constraint: ConstraintKind) -> String {
        switch constraint {
        case let .row(row): "row \(row + 1)"
        case let .column(column): "column \(column + 1)"
        case let .region(regionID): "region \(regionID + 1)"
        }
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
