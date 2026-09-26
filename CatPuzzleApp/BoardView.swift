import CatPuzzleCore
import SwiftUI

enum BoardDragMode: Equatable {
    case exclude
    case clear
    case ignore

    init(startingFrom state: CellState) {
        switch state {
        case .empty:
            self = .exclude
        case .excluded:
            self = .clear
        case .cat:
            self = .ignore
        }
    }
}

enum CellHintEmphasis: Equatable {
    case normal
    case dimmed
    case result
}

extension BoardView {
    /// Every cell's bounding frame, always emitted regardless of masking or
    /// tutorial state, so any ancestor that reads this preference can resolve
    /// whichever cells it cares about into real `CGRect`s — the tutorial's
    /// spotlight cutouts and finger-guide targets among them. A plain level
    /// screen simply never reads it.
    struct CellFrameKey: PreferenceKey {
        static var defaultValue: [CellPosition: Anchor<CGRect>] = [:]
        static func reduce(
            value: inout [CellPosition: Anchor<CGRect>],
            nextValue: () -> [CellPosition: Anchor<CGRect>]
        ) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }
}

struct BoardLayout {
    let side: CGFloat
    let size: Int
    let padding: CGFloat
    let spacing: CGFloat

    var contentSide: CGFloat {
        side - padding * 2
    }

    var cellSide: CGFloat {
        let totalSpacing = spacing * CGFloat(size - 1)
        return (contentSide - totalSpacing) / CGFloat(size)
    }

    func position(at location: CGPoint) -> CellPosition? {
        let x = location.x - padding
        let y = location.y - padding
        guard x >= 0, y >= 0, x < contentSide, y < contentSide else {
            return nil
        }

        let stride = cellSide + spacing
        let column = Int(x / stride)
        let row = Int(y / stride)
        guard row < size, column < size else { return nil }

        let localX = x - CGFloat(column) * stride
        let localY = y - CGFloat(row) * stride
        guard localX <= cellSide, localY <= cellSide else { return nil }

        return CellPosition(row: row, column: column)
    }

    func positions(from start: CGPoint, to end: CGPoint) -> [CellPosition] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let sampleStep = max(cellSide / 3, 1)
        let sampleCount = max(Int(ceil(distance / sampleStep)), 1)
        var result: [CellPosition] = []
        var included: Set<CellPosition> = []

        for index in 0...sampleCount {
            let progress = CGFloat(index) / CGFloat(sampleCount)
            let location = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
            if let position = position(at: location),
               included.insert(position).inserted {
                result.append(position)
            }
        }

        return result
    }
}

struct BoardAppearance {
    enum Spacing {
        case fixed(CGFloat)
        case relativeToCell(CGFloat)
    }

    let padding: CGFloat
    let spacing: Spacing
    let cellCornerRadius: CGFloat
    let cornerRadius: CGFloat

    static let standard = BoardAppearance(padding: 8, spacing: .fixed(4), cellCornerRadius: 8, cornerRadius: 20)
    static let compact = BoardAppearance(padding: 2, spacing: .relativeToCell(0.08), cellCornerRadius: 4, cornerRadius: 6)

    func layout(side: CGFloat, size: Int, displayScale: CGFloat) -> BoardLayout {
        let gap: CGFloat
        switch spacing {
        case .fixed(let value):
            gap = value
        case .relativeToCell(let ratio):
            let cellSide = (side - padding * 2) / (CGFloat(size) + ratio * CGFloat(size - 1))
            gap = (cellSide * ratio * displayScale).rounded() / displayScale
        }
        return BoardLayout(side: side, size: size, padding: padding, spacing: gap)
    }
}

struct BoardView: View {
    @Environment(\.displayScale) private var displayScale
    @State private var previousDragLocation: CGPoint?
    @State private var dragVisitedPositions: Set<CellPosition> = []
    @State private var dragMode: BoardDragMode?

    let puzzle: Puzzle
    let previewStates: [CellPosition: CellState]
    let showsRegionIcons: Bool
    let lockedPositions: Set<CellPosition>
    let hint: LogicalHint?
    var appearance: BoardAppearance = .standard
    /// Cells a guided tutorial step has masked off: dimmed and inert, so the
    /// player can only act on what the step is explaining. Empty on every
    /// ordinary level.
    var maskedPositions: Set<CellPosition> = []
    /// Cells pulsing to show a stuck player where to look.
    var nudgedPositions: Set<CellPosition> = []
    let onTap: (Int, Int) -> Void
    let onDragSetExcluded: (Bool, Int, Int) -> Void
    let onToggleCatAccessibility: (Int, Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let boardPadding = appearance.padding
            let layout = appearance.layout(
                side: side,
                size: puzzle.size,
                displayScale: displayScale
            )
            let spacing = layout.spacing

            VStack(spacing: spacing) {
                ForEach(0..<puzzle.size, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<puzzle.size, id: \.self) { column in
                            let position = CellPosition(
                                row: row,
                                column: column
                            )
                            let hintState = hintState(at: position)
                            CellView(
                                state: hintState ?? previewStates[position]
                                    ?? puzzle.state(
                                    atRow: row,
                                    column: column
                                ) ?? .empty,
                                regionID: puzzle.cell(
                                    atRow: row,
                                    column: column
                                )?.regionID ?? 0,
                                row: row,
                                column: column,
                                cellSide: layout.cellSide,
                                cornerRadius: appearance.cellCornerRadius,
                                showsRegionIcon: showsRegionIcons,
                                isLocked: lockedPositions.contains(position),
                                hintEmphasis: hintEmphasis(at: position),
                                isMasked: maskedPositions.contains(position),
                                isNudged: nudgedPositions.contains(position),
                                allowsInteraction: hint == nil
                                    && !maskedPositions.contains(position),
                                onTap: {
                                    onTap(row, column)
                                },
                                onToggleCatAccessibility: {
                                    onToggleCatAccessibility(row, column)
                                }
                            )
                            .frame(width: layout.cellSide, height: layout.cellSide)
                            .anchorPreference(
                                key: CellFrameKey.self,
                                value: .bounds
                            ) { anchor in
                                [position: anchor]
                            }
                        }
                    }
                }
            }
            .frame(
                width: layout.contentSide,
                height: layout.contentSide,
                alignment: .topLeading
            )
            .padding(boardPadding)
            .background(
                CatPuzzleTheme.surface,
                in: RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous)
                    .stroke(CatPuzzleTheme.divider, lineWidth: 1)
            }
            .shadow(
                color: CatPuzzleTheme.textPrimary.opacity(0.08),
                radius: 12,
                y: 6
            )
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(boardGesture(layout: layout))
            .allowsHitTesting(hint == nil)
        }
    }

    private func hintState(at position: CellPosition) -> CellState? {
        guard let action = hint?.actions.first(where: { action in
            switch action {
            case let .placeCat(target), let .exclude(target):
                target == position
            }
        }) else {
            return nil
        }
        switch action {
        case .placeCat:
            return .cat
        case .exclude:
            return .excluded
        }
    }

    private func hintEmphasis(at position: CellPosition) -> CellHintEmphasis {
        guard let hint else { return .normal }
        return hint.positions.contains(position) ? .result : .dimmed
    }

    private func boardGesture(layout: BoardLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let movement = hypot(
                    value.location.x - value.startLocation.x,
                    value.location.y - value.startLocation.y
                )
                guard previousDragLocation != nil || movement >= 8 else {
                    return
                }

                if dragMode == nil {
                    dragMode = mode(
                        at: value.startLocation,
                        layout: layout
                    )
                }

                markDragPositions(
                    layout.positions(
                        from: previousDragLocation ?? value.startLocation,
                        to: value.location
                    ),
                    mode: dragMode ?? .ignore
                )
                previousDragLocation = value.location
            }
            .onEnded { value in
                if let previousDragLocation {
                    markDragPositions(
                        layout.positions(
                            from: previousDragLocation,
                            to: value.location
                        ),
                        mode: dragMode ?? .ignore
                    )
                } else if let position = layout.position(at: value.startLocation),
                          !maskedPositions.contains(position) {
                    onTap(position.row, position.column)
                }

                previousDragLocation = nil
                dragVisitedPositions.removeAll()
                dragMode = nil
            }
    }

    private func mode(
        at location: CGPoint,
        layout: BoardLayout
    ) -> BoardDragMode {
        guard let position = layout.position(at: location),
              let state = puzzle.state(
                  atRow: position.row,
                  column: position.column
              ),
              !lockedPositions.contains(position),
              !maskedPositions.contains(position) else {
            return .ignore
        }
        return BoardDragMode(startingFrom: state)
    }

    private func markDragPositions(
        _ positions: [CellPosition],
        mode: BoardDragMode
    ) {
        for position in positions
        where dragVisitedPositions.insert(position).inserted {
            switch mode {
            case .exclude:
                onDragSetExcluded(true, position.row, position.column)
            case .clear:
                onDragSetExcluded(false, position.row, position.column)
            case .ignore:
                break
            }
        }
    }
}
