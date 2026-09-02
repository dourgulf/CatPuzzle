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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: CellState
    let regionID: Int
    let row: Int
    let column: Int
    let cellSide: CGFloat
    let showsRegionIcon: Bool
    let isLocked: Bool
    let hintEmphasis: CellHintEmphasis
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Row \(row + 1), Column \(column + 1), "
                    + CatPuzzleTheme.regionName(for: regionID)
                    + (isLocked ? ", Given" : "")
            )
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(accessibilityHintText)
            .accessibilityAddTraits(isLocked ? [] : .isButton)
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

    private var accessibilityHintText: String {
        if isLocked {
            "Fixed at the start of this level."
        } else if allowsInteraction {
            "Activate to mark excluded."
        } else {
            "Hint preview. Use Apply or Cancel below the board."
        }
    }

}
