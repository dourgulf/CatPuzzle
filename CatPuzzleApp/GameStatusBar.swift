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
                        CatLifeIcon(isAvailable: index < remainingLives)
                            .frame(width: iconSize, height: iconSize)
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

/// A small, flat cat face shares the board markers' rounded silhouette.
private struct CatLifeIcon: View {
    let isAvailable: Bool

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                CatHeadShape()
                    .fill(isAvailable ? CatPuzzleTheme.lifeAccent : CatPuzzleTheme.divider)
                Path { path in
                    for x in [0.34, 0.66] {
                        path.addEllipse(in: CGRect(x: side * (x - 0.045), y: side * 0.49,
                                                   width: side * 0.09, height: side * 0.12))
                    }
                    path.move(to: CGPoint(x: side * 0.45, y: side * 0.69))
                    path.addLine(to: CGPoint(x: side * 0.55, y: side * 0.69))
                    path.addLine(to: CGPoint(x: side * 0.5, y: side * 0.75))
                    path.closeSubpath()
                }
                .fill(CatPuzzleTheme.textPrimary.opacity(isAvailable ? 1 : 0.35))
            }
            .frame(width: side, height: side)
        }
    }
}

private struct CatHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0.12, y: 0.43))
            path.addLine(to: CGPoint(x: 0.13, y: 0.08))
            path.addQuadCurve(to: CGPoint(x: 0.37, y: 0.28), control: CGPoint(x: 0.24, y: 0.12))
            path.addQuadCurve(to: CGPoint(x: 0.63, y: 0.28), control: CGPoint(x: 0.5, y: 0.23))
            path.addQuadCurve(to: CGPoint(x: 0.87, y: 0.08), control: CGPoint(x: 0.76, y: 0.12))
            path.addLine(to: CGPoint(x: 0.88, y: 0.43))
            path.addCurve(to: CGPoint(x: 0.5, y: 0.94), control1: CGPoint(x: 1.03, y: 0.75), control2: CGPoint(x: 0.82, y: 0.94))
            path.addCurve(to: CGPoint(x: 0.12, y: 0.43), control1: CGPoint(x: 0.18, y: 0.94), control2: CGPoint(x: -0.03, y: 0.75))
            path.closeSubpath()
        }
        .applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
        .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}
