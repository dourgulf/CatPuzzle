import CatPuzzleCore
import SwiftUI

struct RuleInfoStrip: View {
    static let rules: [PuzzleRule] = [
        .oneCatPerRegion,
        .oneCatPerRowAndColumn,
        .noTouchingCats,
    ]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            ForEach(Self.rules, id: \.self) { rule in
                HStack(spacing: 5) {
                    RuleInfoDiagram(
                        rule: rule,
                        filledColor: CatPuzzleTheme.textSecondary,
                        emptyColor: CatPuzzleTheme.divider
                    )
                        .frame(width: 32, height: 32)
                        .fixedSize()
                        .accessibilityHidden(true)
                    Text(LocalizedStringKey(rule.tipText))
                        .font(.caption2.weight(.medium))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
                        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? nil : 30)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(CatPuzzleTheme.textSecondary)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(CatPuzzleTheme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct RuleInfoCard: View {
    let rule: PuzzleRule
    let compact: Bool

    init(rule: PuzzleRule, compact: Bool = false) {
        self.rule = rule
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            RuleInfoDiagram(rule: rule)
                .frame(width: compact ? 26 : 32, height: compact ? 26 : 32)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(rule.tipText))
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color(red: 0.62, green: 0.34, blue: 0.31))
        .padding(.horizontal, compact ? 5 : 6)
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 48 : 64)
        .background(Color(red: 0.98, green: 0.95, blue: 0.92), in: RoundedRectangle(cornerRadius: compact ? 10 : 12))
        .accessibilityElement(children: .combine)
    }
}

extension PuzzleRule {
    var tipText: String {
        switch self {
        case .oneCatPerRegion: "One color, one cat"
        case .oneCatPerRowAndColumn: "One cat per row & column"
        case .noTouchingCats: "Cats cannot touch"
        }
    }
}

/// Miniature board examples use the same paw and × vocabulary as the board.
private struct RuleInfoDiagram: View {
    let rule: PuzzleRule
    var filledColor = Color(red: 0.70, green: 0.43, blue: 0.28)
    var emptyColor = Color(red: 0.87, green: 0.73, blue: 0.65)

    var body: some View {
        Grid(horizontalSpacing: 1.5, verticalSpacing: 1.5) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let isCat = row == (rule == .oneCatPerRowAndColumn ? 0 : 1) && column == 1
                        let isExcluded = excluded(row: row, column: column)
                        GeometryReader { geometry in
                            ZStack {
                                if isCat {
                                    CatMarkerView(fontSize: geometry.size.width * (0.60 / 0.84))
                                } else if isExcluded {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(filledColor)
                                        .overlay {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(emptyColor)
                                }
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height)
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
