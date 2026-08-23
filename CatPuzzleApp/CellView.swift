import CatPuzzleCore
import SwiftUI

struct CellView: View {
    let state: CellState
    let colorID: Int
    let borders: CellBorders
    let row: Int
    let column: Int
    let onToggleExcluded: () -> Void
    let onToggleCat: () -> Void

    var body: some View {
        marker
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cellColor.opacity(0.22))
            .contentShape(Rectangle())
            .overlay {
                Rectangle()
                    .stroke(.secondary.opacity(0.35), lineWidth: 0.5)
            }
            .overlay {
                ColorBorderShape(borders: borders)
                    .stroke(
                        .primary,
                        style: StrokeStyle(lineWidth: 3, lineCap: .square)
                    )
            }
            .gesture(cellGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Row \(row + 1), Column \(column + 1)")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Tap to mark excluded. Double-tap to toggle a paw.")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("cell-\(row)-\(column)")
    }

    private var cellGesture: some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { value in
                switch value {
                case .first:
                    onToggleCat()
                case .second:
                    onToggleExcluded()
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
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
        case .cat:
            Image(systemName: "pawprint.fill")
                .font(.title2)
                .foregroundStyle(.orange)
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .empty: "Empty"
        case .excluded: "Excluded"
        case .cat: "Cat"
        }
    }

    private var cellColor: Color {
        let colors: [Color] = [
            .green, .blue, .orange, .purple, .pink, .cyan, .yellow, .mint,
        ]
        let index = Int(colorID.magnitude % UInt(colors.count))
        return colors[index]
    }
}

private struct ColorBorderShape: Shape {
    let borders: CellBorders

    func path(in rect: CGRect) -> Path {
        var path = Path()

        if borders.top {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        if borders.bottom {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        if borders.leading {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        if borders.trailing {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        return path
    }
}
