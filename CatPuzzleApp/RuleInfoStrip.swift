import CatPuzzleCore
import SwiftUI

struct RuleInfoStrip: View {
    static let rules: [PuzzleRule] = [
        .oneCatPerRegion,
        .oneCatPerRowAndColumn,
        .noTouchingCats,
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.rules, id: \.self) { rule in
                RuleInfoCard(rule: rule, compact: true)
                    .frame(maxWidth: .infinity)
            }
        }
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
