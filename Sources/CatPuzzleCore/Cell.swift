public struct Cell: Hashable, Sendable {
    public let row: Int
    public let column: Int
    public let regionID: Int

    public init(row: Int, column: Int, regionID: Int) {
        self.row = row
        self.column = column
        self.regionID = regionID
    }
}
