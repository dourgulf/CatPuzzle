import CatPuzzleCore
import SwiftUI

struct GameScreen: View {
    @ObservedObject var viewModel: GameViewModel
    let presentation: LevelPresentation
    let showsRegionIcons: Bool
    let onBackToLevelStart: () -> Void
    let onOpenSettings: (() -> Void)?
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            ScrollView {
                GamePlayContent(
                    viewModel: viewModel, presentation: presentation,
                    showsRegionIcons: showsRegionIcons,
                    onBackToLevelStart: onBackToLevelStart,
                    onOpenSettings: onOpenSettings
                )
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
                .buttonStyle(GameActionButtonStyle(prominent: true))
                .accessibilityIdentifier("continue-after-completion")
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: 340)
        .background(
            CatPuzzleTheme.surface,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24).strokeBorder(CatPuzzleTheme.divider, lineWidth: 1)
        }
        .shadow(color: CatPuzzleTheme.textPrimary.opacity(0.10), radius: 16, y: 8)
        .padding(24)
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
            .buttonStyle(GameActionButtonStyle(prominent: true))
            .accessibilityIdentifier("restart-after-failure")
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: 340)
        .background(
            CatPuzzleTheme.surface,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24).strokeBorder(CatPuzzleTheme.divider, lineWidth: 1)
        }
        .shadow(color: CatPuzzleTheme.textPrimary.opacity(0.10), radius: 16, y: 8)
        .padding(24)
    }
}

/// Formal game content shared by the scrolling screen and visual render scenes.
struct GamePlayContent: View {
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: GameViewModel
    let presentation: LevelPresentation
    let showsRegionIcons: Bool
    let onBackToLevelStart: () -> Void
    let onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            header
                .padding(.horizontal, 12)
            GameStatusBar(
                regionIDs: viewModel.regionIDs,
                occupiedRegionIDs: viewModel.occupiedRegionIDs,
                remainingLives: viewModel.remainingMistakes,
                maxLives: viewModel.level.maxMistakes
            )
            .padding(.horizontal, 12)
            RuleInfoStrip()
                .padding(.horizontal, 12)

            BoardView(
                puzzle: viewModel.puzzle,
                previewStates: viewModel.previewStates,
                showsRegionIcons: showsRegionIcons,
                lockedPositions: viewModel.level.givenPositions,
                hint: viewModel.hint,
                appearance: .compact,
                onTap: viewModel.handleCellTap,
                onDragSetExcluded: viewModel.setExcludedDuringDrag,
                onToggleCatAccessibility: viewModel.toggleCat
            )
            .aspectRatio(1, contentMode: .fit)

            HStack(spacing: 12) {
                Button {
                    viewModel.requestHint()
                } label: {
                    Text("Hint")
                        .font(.headline)
                }
                .buttonStyle(GameActionButtonStyle())
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
                    }
                    .buttonStyle(GameActionButtonStyle())
                    .disabled(!viewModel.canUndo)
                }
            }
            .padding(.horizontal, 12)

            if let hint = viewModel.hint {
                HintPanel(
                    description: HintDescription.text(
                        for: hint,
                        showsRegionIcons: showsRegionIcons, locale: locale
                    ),
                    onApply: viewModel.applyHint,
                    onCancel: viewModel.dismissHint
                )
                .padding(.horizontal, 12)
            }

            feedback
                .padding(.horizontal, 12)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 3) {
                Text("CATPUZZLE")
                    .font(.caption2.bold())
                    .tracking(1.5)
                    .foregroundStyle(CatPuzzleTheme.textSecondary)
                Text(presentation.localizedTitle(locale: locale))
                    .font(.title2.bold())
            }
            .lineLimit(1)
            .padding(.horizontal, 52)

            HStack {
                headerButton("chevron.left", label: "Back to level start", identifier: "back-to-level-start", action: onBackToLevelStart)
                Spacer()
                if let onOpenSettings {
                    headerButton("gearshape.fill", label: "Settings", identifier: "open-settings", action: onOpenSettings)
                }
            }
        }
    }

    private func headerButton(_ symbol: String, label: LocalizedStringKey, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(CatPuzzleTheme.surface, in: Circle())
                .overlay {
                    Circle().strokeBorder(CatPuzzleTheme.divider, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(CatPuzzleTheme.textPrimary)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// A broken board is explained here rather than in the hint panel: there
    /// is no step to preview, only something to undo.
    private var feedbackText: String? {
        if let diagnosis = viewModel.hintDiagnosis {
            return HintDescription.text(
                for: diagnosis,
                showsRegionIcons: showsRegionIcons, locale: locale
            )
        }
        return viewModel.feedbackMessage
    }

    @ViewBuilder
    private var feedback: some View {
        if let message = feedbackText {
            Text(LocalizedStringKey(message))
                .font(.footnote.weight(.medium))
                .foregroundStyle(CatPuzzleTheme.warning)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36)
                .accessibilityIdentifier("game-feedback")
        }
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
                .foregroundStyle(CatPuzzleTheme.actionInk)
            Text(description)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(CatPuzzleTheme.textSecondary)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(GameActionButtonStyle())
                    .accessibilityIdentifier("cancel-hint")
                Button("Apply", action: onApply)
                    .buttonStyle(GameActionButtonStyle(prominent: true))
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

/// Shared by the formal game's toolbar, hint card and outcome cards.
struct GameActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(prominent ? CatPuzzleTheme.surface : CatPuzzleTheme.textPrimary)
            .background(
                prominent ? CatPuzzleTheme.actionInk : CatPuzzleTheme.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : CatPuzzleTheme.divider, lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

enum HintDescription {
    /// `showsRegionIcons` mirrors the board: with icons off a Region is named
    /// by color alone, since that is all the player can see.
    static func text(for hint: LogicalHint, showsRegionIcons: Bool, locale: Locale = Locale(identifier: "en")) -> String {
        switch hint.reason {
        case let .onlyCandidateInRow(row):
            L10n.format("Row %@ has only one possible cell left. Place a cat there.", [String(row + 1)], locale: locale)
        case let .onlyCandidateInColumn(column):
            L10n.format("Column %@ has only one possible cell left. Place a cat there.", [String(column + 1)], locale: locale)
        case let .onlyCandidateForRegion(regionID):
            L10n.format("The %@ block has only one possible cell left. Place a cat there.", [String(regionText(regionID, showsRegionIcons, locale: locale))], locale: locale)
        case let .rowAlreadyHasCat(row):
            L10n.format("Row %@ already has its cat. Exclude the highlighted cells.", [String(row + 1)], locale: locale)
        case let .columnAlreadyHasCat(column):
            L10n.format("Column %@ already has its cat. Exclude the highlighted cells.", [String(column + 1)], locale: locale)
        case let .regionAlreadyHasCat(regionID):
            L10n.format("The %@ block already has its cat. Exclude the highlighted cells.", [String(regionText(regionID, showsRegionIcons, locale: locale))], locale: locale)
        case .adjacentToConfirmedCat:
            L10n.text("Cats cannot touch, including diagonally. Exclude the highlighted cells.", locale: locale)
        case let .lockedSet(sources, targets):
            L10n.format("The cats in %@ are locked into %@. Exclude the highlighted cells.", [String(constraintList(sources, showsRegionIcons, locale: locale)), String(constraintList(targets, showsRegionIcons, locale: locale))], locale: locale)
        case let .commonAttack(constraint, candidates):
            L10n.format("%@ has %@ possible cells left, and the highlighted cell conflicts with every one of them. Exclude it.", [String(constraintName(constraint, showsRegionIcons, locale: locale).capitalizedFirst), String(candidates.count)], locale: locale)
        case let .strongLinkCommonElimination(link):
            L10n.format("One of %@ and %@ must hold %@'s cat. The highlighted cell conflicts with both, so it can never be a cat.", [String(cellName(link.first, locale: locale)), String(cellName(link.second, locale: locale)), String(constraintName(link.constraint, showsRegionIcons, locale: locale))], locale: locale)
        case let .contradictionFromAssumption(assumed, contradicting):
            if let contradicting {
                L10n.format("Try a cat at %@: %@ would then have nowhere left for its own cat. So it cannot be a cat — exclude it.", [String(cellName(assumed, locale: locale)), String(constraintName(contradicting, showsRegionIcons, locale: locale))], locale: locale)
            } else {
                L10n.format("Try a cat at %@: the board contradicts itself. So it cannot be a cat — exclude it.", [String(cellName(assumed, locale: locale))], locale: locale)
            }
        }
    }

    static func text(
        for diagnosis: LogicalHintDiagnosis,
        showsRegionIcons: Bool,
        locale: Locale = Locale(identifier: "en")
    ) -> String {
        switch diagnosis {
        case let .starvedConstraint(constraint):
            L10n.format("%@ has no cell left for a cat, so one of your ✕ marks must be wrong. Undo to fix it.", [String(constraintName(constraint, showsRegionIcons, locale: locale).capitalizedFirst)], locale: locale)
        case let .clashingCats(first, second):
            L10n.format("The cats at %@ and %@ cannot both be right. Undo to fix it.", [String(cellName(first, locale: locale)), String(cellName(second, locale: locale))], locale: locale)
        }
    }

    private static func cellName(_ position: CellPosition, locale: Locale) -> String {
        L10n.format("R%@C%@", [String(position.row + 1), String(position.column + 1)], locale: locale)
    }

    private static func constraintList(
        _ constraints: [ConstraintKind],
        _ showsRegionIcons: Bool,
        locale: Locale = Locale(identifier: "en")
    ) -> String {
        constraints
            .map { constraintName($0, showsRegionIcons, locale: locale) }
            .joined(separator: L10n.text(" and ", locale: locale))
    }

    static func constraintName(
        _ constraint: ConstraintKind,
        _ showsRegionIcons: Bool,
        locale: Locale = Locale(identifier: "en")
    ) -> String {
        switch constraint {
        case let .row(row): L10n.format("row %@", [String(row + 1)], locale: locale)
        case let .column(column): L10n.format("column %@", [String(column + 1)], locale: locale)
        case let .region(regionID):
            L10n.format("the %@ block", [String(regionText(regionID, showsRegionIcons, locale: locale))], locale: locale)
        }
    }

    private static func regionText(_ regionID: Int, _ showsRegionIcons: Bool, locale: Locale = Locale(identifier: "en")) -> String {
        CatPuzzleTheme.regionDescription(
            for: regionID,
            includingShape: showsRegionIcons, locale: locale
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
