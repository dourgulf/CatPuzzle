import CatPuzzleCore
import SwiftUI

/// The tutorial's own screen: dark, full-bleed, spotlighted — visually
/// nothing like `GameScreen`, on purpose (see `Docs/Tutorial.md`). A guided
/// step spotlights the relevant cells and demonstrates one move. Discovery
/// leaves the board live and offers a clue on request.
struct TutorialScreen: View {
    @ObservedObject var viewModel: TutorialViewModel
    let showsRegionIcons: Bool
    let onContinue: () -> Void

    @Namespace private var ruleFlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var flashingRule: PuzzleRule?

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
        .animation(reduceMotion ? nil : .spring(duration: 0.65), value: viewModel.learnedRules)
        .task(id: "\(viewModel.activitySequence)-\(scenePhase)") {
            viewModel.clearIdleReminder()
            guard scenePhase == .active else { return }
            do {
                try await Task.sleep(for: .seconds(3))
                while !Task.isCancelled {
                    viewModel.showIdleReminder()
                    try await Task.sleep(for: .milliseconds(600))
                    viewModel.clearIdleReminder()
                    try await Task.sleep(for: .milliseconds(2400))
                }
            } catch { return }
        }

        .task(id: viewModel.stepNumber) {
            flashingRule = nil
            guard let rule = viewModel.activeRule,
                  viewModel.learnedRules.contains(rule), viewModel.stepNumber >= 5 else { return }
            do {
                try await Task.sleep(for: .milliseconds(700))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { flashingRule = rule }
                try await Task.sleep(for: .milliseconds(500))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { flashingRule = nil }
            } catch { flashingRule = nil }
        }
        .onDisappear { viewModel.clearIdleReminder() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                Color.clear.frame(height: 32).accessibilityHidden(true)
                ruleSlots
                boardWithSpotlight

                if let step = viewModel.step {
                    tip(for: step)
                        .frame(maxWidth: 300)
                        .frame(minHeight: 64, alignment: .top)
                        .allowsHitTesting(false)
                }

                if let message = viewModel.feedbackMessage {
                    Text(LocalizedStringKey(message))
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

    /// Visual coaching stays on the board; TIPS has its own space below it.
    private var boardWithSpotlight: some View {
        board
            .overlayPreferenceValue(BoardView.CellFrameKey.self) { anchors in
                GeometryReader { proxy in
                    let cellFrames = anchors.mapValues { proxy[$0] }
                    ZStack {
                        ForEach(viewModel.reminderPositions.sorted {
                            $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row
                        }, id: \.self) { position in
                            if let frame = cellFrames[position] {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(TutorialTheme.accent.opacity(0.25))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(TutorialTheme.accent, lineWidth: 3)
                                    }
                                    .frame(width: frame.width, height: frame.height)
                                    .position(x: frame.midX, y: frame.midY)
                            }
                        }
                        if !viewModel.spotlight.isEmpty {
                            TutorialSpotlightMask(
                                holes: viewModel.spotlight.compactMap { cellFrames[$0] }
                            )
                            .fill(TutorialTheme.scrim, style: FillStyle(eoFill: true))
                            .allowsHitTesting(false)
                        }
                        if let step = viewModel.step, viewModel.showsFingerGuide {
                            TutorialFingerGuide(
                                task: step.task,
                                target: viewModel.guidedTarget,
                                cellFrames: cellFrames,
                                playbackID: viewModel.guidancePlaybackID,
                                dragEnd: viewModel.guidedDragEnd
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
            }
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

    private var ruleSlots: some View {
        HStack(spacing: 8) {
            ForEach([PuzzleRule.oneCatPerRegion, .oneCatPerRowAndColumn, .noTouchingCats], id: \.self) { rule in
                ZStack {
                    Color.clear
                        .accessibilityHidden(true)
                    if viewModel.learnedRules.contains(rule) {
                        ruleCard(rule)
                            .matchedGeometryEffect(id: rule, in: ruleFlight)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(TutorialTheme.accent, lineWidth: flashingRule == rule ? 3 : 0)
                            }
                            .brightness(flashingRule == rule ? 0.18 : 0)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .accessibilityIdentifier("tutorial-rule-\(ruleNumber(rule))")
            }
        }
    }

    private func ruleNumber(_ rule: PuzzleRule) -> Int {
        switch rule {
        case .oneCatPerRegion: 1
        case .oneCatPerRowAndColumn: 2
        case .noTouchingCats: 3
        }
    }

    private func ruleCard(_ rule: PuzzleRule) -> some View {
        HStack(spacing: 5) {
            TutorialRuleDiagram(rule: rule)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(rule.tipText))
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color(red: 0.62, green: 0.34, blue: 0.31))
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(Color(red: 0.98, green: 0.95, blue: 0.92), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func tip(for step: TutorialStep) -> some View {
        if let rule = step.lesson.rule, !viewModel.learnedRules.contains(rule) {
            tipLabel(rule.tipText)
                .matchedGeometryEffect(id: rule, in: ruleFlight)
                .accessibilityHint(LocalizedStringKey(step.actionHint))
        } else {
            tipLabel(step.lesson.rule?.tipText ?? "Mark empty cells ×")
                .accessibilityHint(LocalizedStringKey(step.actionHint))
        }
    }

    private func tipLabel(_ text: String) -> some View {
        HStack(spacing: 7) {
            Text("TIPS")
                .font(.caption2.bold())
                .foregroundStyle(TutorialTheme.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(text))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TutorialTheme.accent)
                if viewModel.teachesColumnDrag {
                    Text("Hold & drag down ↓")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TutorialTheme.textPrimary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(TutorialTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(TutorialTheme.accent.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tutorial-tip")
    }
}

private extension PuzzleRule {
    var tipText: String {
        switch self {
        case .oneCatPerRegion: "One color, one cat"
        case .oneCatPerRowAndColumn: "One cat per row & column"
        case .noTouchingCats: "Cats cannot touch"
        }
    }
}

/// Miniature board examples: a single color, a filled row/column, and all
/// eight neighbours. These use the same paw and × vocabulary as the board.
private struct TutorialRuleDiagram: View {
    let rule: PuzzleRule

    var body: some View {
        Grid(horizontalSpacing: 1.5, verticalSpacing: 1.5) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let isCat = row == (rule == .oneCatPerRowAndColumn ? 0 : 1) && column == 1
                        let isExcluded = excluded(row: row, column: column)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isCat || isExcluded
                                  ? Color(red: 0.70, green: 0.43, blue: 0.28)
                                  : Color(red: 0.87, green: 0.73, blue: 0.65))
                            .overlay {
                                if isCat {
                                    Image(systemName: "pawprint.fill")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.white)
                                } else if isExcluded {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                }
            }
        }
    }

    private func excluded(row: Int, column: Int) -> Bool {
        switch rule {
        case .oneCatPerRegion: row == 0 || column == 0
        case .oneCatPerRowAndColumn: row == 0 || column == 1
        case .noTouchingCats: true
        }
    }
}
