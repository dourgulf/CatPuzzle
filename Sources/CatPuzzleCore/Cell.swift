public struct Cell: Hashable, Sendable {
    public let row: Int
    public let column: Int
    public let colorID: Int

    public init(row: Int, column: Int, colorID: Int) {
        self.row = row
        self.column = column
        self.colorID = colorID
    }
}
