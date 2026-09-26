import CatPuzzleCore
import SwiftUI

struct CellMarkerMetrics: Equatable {
    let excludedFontSize: CGFloat
    let catFontSize: CGFloat
    let catPadding: CGFloat

    init(cellSide: CGFloat) {
        excludedFontSize = min(40, cellSide * 0.72)
        catFontSize = min(23, cellSide * 0.42)
        catPadding = min(7, cellSide * 0.13)
    }
}

struct CellView: View {
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the nudge's pulse. Held here rather than animated from
    /// `isNudged` directly so the repeating animation starts and stops with
    /// the nudge instead of running forever once triggered.
    @State private var isPulsing = false

    let state: CellState
    let regionID: Int
    let row: Int
    let column: Int
    let cellSide: CGFloat
    let showsRegionIcon: Bool
    let isLocked: Bool
    let hintEmphasis: CellHintEmphasis
    /// Covered by a guided tutorial step, which leaves only the cells the
    /// step is about reachable.
    let isMasked: Bool
    /// Pulsing because the player has stalled on an unguided tutorial step.
    let isNudged: Bool
    let allowsInteraction: Bool
    let onTap: () -> Void
    let onToggleCatAccessibility: () -> Void

    private var markerMetrics: CellMarkerMetrics {
        CellMarkerMetrics(cellSide: cellSide)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CatPuzzleTheme.regionColor(for: regionID))

            if showsRegionIcon {
                Image(systemName: CatPuzzleTheme.regionSymbol(for: regionID))
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(
                        CatPuzzleTheme.markerColor(for: regionID).opacity(0.45)
                    )
                    .padding(6)
                    .accessibilityHidden(true)
            }

            marker
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(
                        CatPuzzleTheme.markerColor(for: regionID).opacity(0.55)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
                    .accessibilityHidden(true)
            }

            if hintEmphasis == .dimmed {
                Color.black.opacity(0.62)
                    .accessibilityHidden(true)
            } else if isMasked {
                Color.black.opacity(0.4)
                    .accessibilityHidden(true)
            }
        }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: state
            )
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        hintEmphasis == .result
                            ? CatPuzzleTheme.action
                            : .white.opacity(0.5),
                        lineWidth: hintEmphasis == .result ? 4 : 1
                    )
            }
            .overlay {
                if isNudged {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CatPuzzleTheme.action, lineWidth: 4)
                        .opacity(reduceMotion || isPulsing ? 1 : 0.2)
                        .animation(pulseAnimation, value: isPulsing)
                        .accessibilityHidden(true)
                }
            }
            .onAppear { isPulsing = isNudged && !reduceMotion }
            .onChange(of: isNudged) { _, nudged in
                isPulsing = nudged && !reduceMotion
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                L10n.format("Row %@, Column %@, %@", [String(row + 1), String(column + 1),
                    CatPuzzleTheme.regionName(for: regionID, includingShape: showsRegionIcon, locale: locale)], locale: locale)
                    + (isLocked ? L10n.text(", Given", locale: locale) : "")
            )
            .accessibilityValue(LocalizedStringKey(accessibilityValue))
            .accessibilityHint(LocalizedStringKey(accessibilityHintText))
            .accessibilityAddTraits(isLocked || isMasked ? [] : .isButton)
            .accessibilityIdentifier("cell-\(row)-\(column)")
            .accessibilityAction {
                if allowsInteraction, !isLocked {
                    onTap()
                }
            }
            .accessibilityAction(named: "Toggle cat") {
                if allowsInteraction, !isLocked {
                    onToggleCatAccessibility()
                }
            }
    }

    @ViewBuilder
    private var marker: some View {
        switch state {
        case .empty:
            Color.clear
        case .excluded:
            Text("×")
                .font(
                    .system(
                        size: markerMetrics.excludedFontSize,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white)
                .transition(.scale.combined(with: .opacity))
        case .cat:
            ZStack {
                Circle()
                    .fill(CatPuzzleTheme.surface.opacity(0.94))
                Image(systemName: "pawprint.fill")
                    .font(
                        .system(
                            size: markerMetrics.catFontSize,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(CatPuzzleTheme.textPrimary)
            }
            .padding(markerMetrics.catPadding)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .empty: "Empty"
        case .excluded: "Excluded"
        case .cat: "Cat"
        }
    }

    /// Reduce Motion gets a steady ring instead of a pulse: the point is to
    /// point, and that survives losing the animation.
    private var pulseAnimation: Animation? {
        reduceMotion
            ? nil
            : .easeInOut(duration: 0.65).repeatForever(autoreverses: true)
    }

    private var accessibilityHintText: String {
        if isLocked {
            "Fixed at the start of this level."
        } else if isMasked {
            "Not part of this tutorial step."
        } else if isNudged {
            "This is the cell the tutorial is waiting for."
        } else if allowsInteraction {
            "Activate to mark excluded."
        } else {
            "Hint preview. Use Apply or Cancel below the board."
        }
    }

}
