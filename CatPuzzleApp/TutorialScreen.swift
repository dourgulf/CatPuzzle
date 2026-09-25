import CatPuzzleCore
import SwiftUI

/// The tutorial's own screen: dark, full-bleed, spotlighted — visually
/// nothing like `GameScreen`, on purpose (see the tutorial-redesign plan and
/// `Docs/Tutorial.md`). A guided step darkens the whole screen but for its
/// spotlighted cells and plays a one-shot finger-guide animation over the
/// exact gesture it wants; a discovery step leaves the board live and falls
/// back to the existing stall-triggered nudge. Finishing the script hands off
/// to the single graduation page, `TutorialCompletionScreen`.
struct TutorialScreen: View {
    @ObservedObject var viewModel: TutorialViewModel
    let showsRegionIcons: Bool
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            TutorialTheme.background.ignoresSafeArea()

            if viewModel.isSolved {
                TutorialCompletionScreen(onContinue: onContinue)
                    .transition(.opacity)
            } else {
                content
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.isSolved)
        .sensoryFeedback(.selection, trigger: viewModel.markerFeedbackSequence)
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                boardWithSpotlight
                caption

                if let message = viewModel.feedbackMessage {
                    Text(message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CatPuzzleTheme.warning)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("game-feedback")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The scrim/finger-guide overlay is scoped to just the board's own
    /// bounds (not the whole scrollable screen) so the caption card below it
    /// — and the header above — are never painted over by the spotlight
    /// mask and stay readable regardless of what the current step spotlights.
    private var boardWithSpotlight: some View {
        board
            .overlayPreferenceValue(BoardView.CellFrameKey.self) { anchors in
                GeometryReader { proxy in
                    let cellFrames = anchors.mapValues { proxy[$0] }
                    ZStack {
                        if !viewModel.spotlight.isEmpty {
                            TutorialSpotlightMask(
                                holes: viewModel.spotlight.compactMap { cellFrames[$0] }
                            )
                            .fill(TutorialTheme.scrim, style: FillStyle(eoFill: true))
                            .allowsHitTesting(false)
                        }
                        if let step = viewModel.step, step.coaching == .guided {
                            TutorialFingerGuide(
                                task: step.task,
                                cellFrames: cellFrames,
                                playbackID: viewModel.stepNumber
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("CATPUZZLE")
                .font(.caption2.bold())
                .tracking(1.5)
                .foregroundStyle(TutorialTheme.textSecondary)
            Text("Tutorial")
                .font(.title2.bold())
                .foregroundStyle(TutorialTheme.textPrimary)
            if viewModel.step != nil {
                Text("STEP \(viewModel.stepNumber) / \(viewModel.stepCount)")
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .foregroundStyle(TutorialTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var board: some View {
        BoardView(
            puzzle: viewModel.puzzle,
            previewStates: viewModel.previewStates,
            showsRegionIcons: showsRegionIcons,
            lockedPositions: viewModel.level.givenPositions,
            hint: nil,
            maskedPositions: maskedPositions,
            nudgedPositions: viewModel.nudgedPositions,
            onTap: viewModel.handleCellTap,
            onDragSetExcluded: viewModel.setExcludedDuringDrag,
            onToggleCatAccessibility: viewModel.toggleCat
        )
        .frame(maxWidth: 430)
        .aspectRatio(1, contentMode: .fit)
    }

    /// VoiceOver has no scrim to look at, so a guided step's masking still has
    /// to reach `BoardView` itself — the same rule `TutorialViewModel.isMasked`
    /// already enforces for gesture handling.
    private var maskedPositions: Set<CellPosition> {
        let spotlight = viewModel.spotlight
        guard !spotlight.isEmpty else { return [] }
        return Set(viewModel.puzzle.cells.map {
            CellPosition(row: $0.row, column: $0.column)
        })
        .subtracting(spotlight)
    }

    @ViewBuilder
    private var caption: some View {
        if let step = viewModel.step {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.lesson.headline)
                    .font(.headline)
                    .foregroundStyle(TutorialTheme.accent)
                Text(
                    step.lesson.explanation(
                        coaching: step.coaching,
                        showsRegionIcons: showsRegionIcons
                    )
                )
                .font(.subheadline)
                .foregroundStyle(TutorialTheme.textSecondary)
                Text(step.actionHint)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(TutorialTheme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                TutorialTheme.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TutorialTheme.spotlightRing.opacity(0.14), lineWidth: 1)
            }
            .multilineTextAlignment(.leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tutorial-step-panel")
        }
    }
}
