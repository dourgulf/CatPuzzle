import CatPuzzleCore
import SwiftUI

struct CellView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: CellState
    let regionID: Int
    let row: Int
    let column: Int
    let onTap: () -> Void
    let onToggleCatAccessibility: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CatPuzzleTheme.regionColor(for: regionID))

            Image(systemName: CatPuzzleTheme.regionSymbol(for: regionID))
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(
                    CatPuzzleTheme.markerColor(for: regionID).opacity(0.45)
                )
                .padding(6)
                .accessibilityHidden(true)

            marker
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: state
            )
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.5), lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Row \(row + 1), Column \(column + 1), "
                    + CatPuzzleTheme.regionName(for: regionID)
            )
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Activate to mark excluded.")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("cell-\(row)-\(column)")
            .accessibilityAction {
                onTap()
            }
            .accessibilityAction(named: "Toggle cat") {
                onToggleCatAccessibility()
            }
    }

    @ViewBuilder
    private var marker: some View {
        switch state {
        case .empty:
            Color.clear
        case .excluded:
            Text("×")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .transition(.scale.combined(with: .opacity))
        case .cat:
            ZStack {
                Circle()
                    .fill(CatPuzzleTheme.surface.opacity(0.94))
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(CatPuzzleTheme.textPrimary)
            }
            .padding(7)
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

}
