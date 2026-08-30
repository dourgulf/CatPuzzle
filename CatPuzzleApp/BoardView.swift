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

struct BoardView: View {
    @State private var previousDragLocation: CGPoint?
    @State private var dragVisitedPositions: Set<CellPosition> = []
    @State private var dragMode: BoardDragMode?

    let puzzle: Puzzle
    let previewStates: [CellPosition: CellState]
    let showsRegionIcons: Bool
    let hint: LogicalHint?
    let onTap: (Int, Int) -> Void
    let onDragSetExcluded: (Bool, Int, Int) -> Void
    let onToggleCatAccessibility: (Int, Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let boardPadding: CGFloat = 8
            let spacing: CGFloat = 4
            let layout = BoardLayout(
                side: side,
                size: puzzle.size,
                padding: boardPadding,
                spacing: spacing
            )

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
                                showsRegionIcon: showsRegionIcons,
                                hintEmphasis: hintEmphasis(at: position),
                                allowsInteraction: hint == nil,
                                onTap: {
                                    onTap(row, column)
                                },
                                onToggleCatAccessibility: {
                                    onToggleCatAccessibility(row, column)
                                }
                            )
                            .frame(width: layout.cellSide, height: layout.cellSide)
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
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                } else if let position = layout.position(at: value.startLocation) {
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
              ) else {
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
