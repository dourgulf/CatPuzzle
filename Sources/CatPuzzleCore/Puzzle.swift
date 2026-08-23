public struct Puzzle: Equatable, Sendable {
    public enum ValidationError: Error, Equatable {
        case invalidSize
        case invalidRegionDimensions
        case invalidStateDimensions
        case invalidCellCoordinate
    }

    public let size: Int
    public let cells: [Cell]
    public private(set) var states: [CellState]

    public init(
        size: Int,
        regionIDs: [[Int]],
        states: [[CellState]]? = nil
    ) throws {
        guard size > 0 else {
            throw ValidationError.invalidSize
        }
        guard Self.hasDimensions(size, rows: regionIDs) else {
            throw ValidationError.invalidRegionDimensions
        }
        if let states, !Self.hasDimensions(size, rows: states) {
            throw ValidationError.invalidStateDimensions
        }

        self.size = size
        self.cells = regionIDs.enumerated().flatMap { row, regionRow in
            regionRow.enumerated().map { column, regionID in
                Cell(row: row, column: column, regionID: regionID)
            }
        }
        self.states = states?.flatMap { $0 }
            ?? Array(repeating: .empty, count: size * size)
    }

    public func contains(row: Int, column: Int) -> Bool {
        (0..<size).contains(row) && (0..<size).contains(column)
    }

    public func cell(atRow row: Int, column: Int) -> Cell? {
        guard contains(row: row, column: column) else { return nil }
        return cells[index(row: row, column: column)]
    }

    public func state(atRow row: Int, column: Int) -> CellState? {
        guard contains(row: row, column: column) else { return nil }
        return states[index(row: row, column: column)]
    }

    public mutating func setState(
        _ state: CellState,
        atRow row: Int,
        column: Int
    ) throws {
        guard contains(row: row, column: column) else {
            throw ValidationError.invalidCellCoordinate
        }
        states[index(row: row, column: column)] = state
    }

    private func index(row: Int, column: Int) -> Int {
        row * size + column
    }

    private static func hasDimensions<T>(_ size: Int, rows: [[T]]) -> Bool {
        rows.count == size && rows.allSatisfy { $0.count == size }
    }
}
