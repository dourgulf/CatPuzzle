import SwiftUI

struct GameStatusBar: View {
    @Environment(\.locale) private var locale

    let regionIDs: [Int]
    let occupiedRegionIDs: Set<Int>
    let remainingLives: Int
    let maxLives: Int

    var body: some View {
        GeometryReader { geometry in
            let iconSize = statusIconSize(availableWidth: geometry.size.width)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(regionIDs, id: \.self) { regionID in
                        let completed = occupiedRegionIDs.contains(regionID)
                        Image(systemName: completed ? "pawprint.fill" : "pawprint")
                            .font(.system(size: iconSize * 0.9, weight: .semibold))
                            .foregroundStyle(CatPuzzleTheme.regionColor(for: regionID))
                            .frame(width: iconSize, height: iconSize)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    CatPuzzleTheme.surface,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(CatPuzzleTheme.divider, lineWidth: 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.format("Completed colors: %@ of %@", [String(occupiedRegionIDs.count), String(regionIDs.count)], locale: locale))
                .accessibilityIdentifier("completion-status")

                HStack(spacing: 4) {
                    ForEach(0..<maxLives, id: \.self) { index in
                        Image("CatLifeFace")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: iconSize, height: iconSize)
                            .saturation(index < remainingLives ? 1 : 0)
                            .opacity(index < remainingLives ? 1 : 0.28)
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: 26)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    CatPuzzleTheme.surface,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(CatPuzzleTheme.divider, lineWidth: 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.format("Lives remaining: %@ of %@", [String(remainingLives), String(maxLives)], locale: locale))
                .accessibilityIdentifier("lives-status")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 40)
    }

    private func statusIconSize(availableWidth: CGFloat) -> CGFloat {
        let iconCount = max(1, regionIDs.count + maxLives)
        let gaps = max(0, regionIDs.count - 1) + max(0, maxLives - 1)
        return min(24, max(10, (availableWidth - 8 - 32 - CGFloat(gaps) * 4) / CGFloat(iconCount)))
    }
}
