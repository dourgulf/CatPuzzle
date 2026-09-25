import CatPuzzleCore
import SwiftUI

struct GameScreen: View {
    @ObservedObject var viewModel: GameViewModel
    let presentation: LevelPresentation
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
                        lockedPositions: viewModel.level.givenPositions,
                        hint: viewModel.hint,
                        onTap: viewModel.handleCellTap,
                        onDragSetExcluded: viewModel.setExcludedDuringDrag,
                        onToggleCatAccessibility: viewModel.toggleCat
                    )
                    .frame(maxWidth: 430)
                    .aspectRatio(1, contentMode: .fit)

                    if let hint = viewModel.hint {
                        HintPanel(
                            description: HintDescription.text(
                                for: hint,
                                showsRegionIcons: showsRegionIcons
                            ),
                            onApply: viewModel.applyHint,
                            onCancel: viewModel.dismissHint
                        )
                    } else {
                        Text(gestureReminder)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(CatPuzzleTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("gesture-reminder")
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
                Text(presentation.title)
                    .font(.title2.bold())
                Text(headerSubtitle)
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

    private var headerSubtitle: String {
        viewModel.mode == .exploration ? "EXPLORE" : "CHALLENGE"
    }

    private var gestureReminder: String {
        "Tap to mark ×  ·  Double-tap to place a paw"
    }

    @ViewBuilder
    private var ruleReminder: some View {
        HStack(spacing: 4) {
            RuleBadge(
                icon: "paintpalette.fill",
                text: PuzzleRule.oneCatPerRegion.badgeText
            )
            RuleBadge(
                icon: "rectangle.split.3x3.fill",
                text: PuzzleRule.oneCatPerRowAndColumn.badgeText
            )
            RuleBadge(
                icon: "square.grid.3x3.fill",
                text: PuzzleRule.noTouchingCats.badgeText
            )
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

    /// A broken board is explained here rather than in the hint panel: there
    /// is no step to preview, only something to undo.
    private var feedbackText: String? {
        if let diagnosis = viewModel.hintDiagnosis {
            return HintDescription.text(
                for: diagnosis,
                showsRegionIcons: showsRegionIcons
            )
        }
        return viewModel.feedbackMessage
    }

    @ViewBuilder
    private var feedback: some View {
        if let message = feedbackText {
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
    /// `showsRegionIcons` mirrors the board: with icons off a Region is named
    /// by color alone, since that is all the player can see.
    static func text(for hint: LogicalHint, showsRegionIcons: Bool) -> String {
        switch hint.reason {
        case let .onlyCandidateInRow(row):
            "Row \(row + 1) has only one possible cell left. Place a cat there."
        case let .onlyCandidateInColumn(column):
            "Column \(column + 1) has only one possible cell left. Place a cat there."
        case let .onlyCandidateForRegion(regionID):
            "The \(regionText(regionID, showsRegionIcons)) block has only one possible cell left. Place a cat there."
        case let .rowAlreadyHasCat(row):
            "Row \(row + 1) already has its cat. Exclude the highlighted cells."
        case let .columnAlreadyHasCat(column):
            "Column \(column + 1) already has its cat. Exclude the highlighted cells."
        case let .regionAlreadyHasCat(regionID):
            "The \(regionText(regionID, showsRegionIcons)) block already has its cat. Exclude the highlighted cells."
        case .adjacentToConfirmedCat:
            "Cats cannot touch, including diagonally. Exclude the highlighted cells."
        case let .lockedSet(sources, targets):
            "The cats in \(constraintList(sources, showsRegionIcons)) are locked into \(constraintList(targets, showsRegionIcons)). Exclude the highlighted cells."
        case let .commonAttack(constraint, candidates):
            "\(constraintName(constraint, showsRegionIcons).capitalizedFirst) has \(candidates.count) possible cells left, and the highlighted cell conflicts with every one of them. Exclude it."
        case let .strongLinkCommonElimination(link):
            "One of \(cellName(link.first)) and \(cellName(link.second)) must hold \(constraintName(link.constraint, showsRegionIcons))'s cat. The highlighted cell conflicts with both, so it can never be a cat."
        case let .contradictionFromAssumption(assumed, contradicting):
            if let contradicting {
                "Try a cat at \(cellName(assumed)): \(constraintName(contradicting, showsRegionIcons)) would then have nowhere left for its own cat. So it cannot be a cat — exclude it."
            } else {
                "Try a cat at \(cellName(assumed)): the board contradicts itself. So it cannot be a cat — exclude it."
            }
        }
    }

    static func text(
        for diagnosis: LogicalHintDiagnosis,
        showsRegionIcons: Bool
    ) -> String {
        switch diagnosis {
        case let .starvedConstraint(constraint):
            "\(constraintName(constraint, showsRegionIcons).capitalizedFirst) has no cell left for a cat, so one of your ✕ marks must be wrong. Undo to fix it."
        case let .clashingCats(first, second):
            "The cats at \(cellName(first)) and \(cellName(second)) cannot both be right. Undo to fix it."
        }
    }

    private static func cellName(_ position: CellPosition) -> String {
        "R\(position.row + 1)C\(position.column + 1)"
    }

    private static func constraintList(
        _ constraints: [ConstraintKind],
        _ showsRegionIcons: Bool
    ) -> String {
        constraints
            .map { constraintName($0, showsRegionIcons) }
            .joined(separator: " and ")
    }

    static func constraintName(
        _ constraint: ConstraintKind,
        _ showsRegionIcons: Bool
    ) -> String {
        switch constraint {
        case let .row(row): "row \(row + 1)"
        case let .column(column): "column \(column + 1)"
        case let .region(regionID):
            "the \(regionText(regionID, showsRegionIcons)) block"
        }
    }

    private static func regionText(_ regionID: Int, _ showsRegionIcons: Bool) -> String {
        CatPuzzleTheme.regionDescription(
            for: regionID,
            includingShape: showsRegionIcons
        )
    }
}

private extension String {
    /// "row 3" -> "Row 3", for a constraint name that starts a sentence.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
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
