import CatPuzzleCore
import SwiftUI

struct CellBorders: Equatable {
    let top: Bool
    let bottom: Bool
    let leading: Bool
    let trailing: Bool

    static func resolve(in puzzle: Puzzle, row: Int, column: Int) -> CellBorders {
        guard let cell = puzzle.cell(atRow: row, column: column) else {
            return CellBorders(
                top: false,
                bottom: false,
                leading: false,
                trailing: false
            )
        }

        return CellBorders(
            top: row == 0
                || puzzle.cell(atRow: row - 1, column: column)?.colorID != cell.colorID,
            bottom: row == puzzle.size - 1
                || puzzle.cell(atRow: row + 1, column: column)?.colorID != cell.colorID,
            leading: column == 0
                || puzzle.cell(atRow: row, column: column - 1)?.colorID != cell.colorID,
            trailing: column == puzzle.size - 1
                || puzzle.cell(atRow: row, column: column + 1)?.colorID != cell.colorID
        )
    }
}

struct BoardView: View {
    let puzzle: Puzzle
    let onToggleExcluded: (Int, Int) -> Void
    let onToggleCat: (Int, Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let cellSide = side / CGFloat(puzzle.size)

            VStack(spacing: 0) {
                ForEach(0..<puzzle.size, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<puzzle.size, id: \.self) { column in
                            CellView(
                                state: puzzle.state(atRow: row, column: column) ?? .empty,
                                colorID: puzzle.cell(
                                    atRow: row,
                                    column: column
                                )?.colorID ?? 0,
                                borders: CellBorders.resolve(
                                    in: puzzle,
                                    row: row,
                                    column: column
                                ),
                                row: row,
                                column: column,
                                onToggleExcluded: {
                                    onToggleExcluded(row, column)
                                },
                                onToggleCat: {
                                    onToggleCat(row, column)
                                }
                            )
                            .frame(width: cellSide, height: cellSide)
                        }
                    }
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)
        }
    }
}
