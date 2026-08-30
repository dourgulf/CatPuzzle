/// Identifies one of the puzzle's three "exactly one cat" constraints.
public enum ConstraintKind: Hashable, Sendable {
    case row(Int)
    case column(Int)
    case region(Int)
}

extension ConstraintKind: Comparable {
    public static func < (lhs: ConstraintKind, rhs: ConstraintKind) -> Bool {
        lhs.sortKey < rhs.sortKey
    }

    private var sortKey: (Int, Int) {
        switch self {
        case let .row(row):
            return (0, row)
        case let .column(column):
            return (1, column)
        case let .region(regionID):
            return (2, regionID)
        }
    }
}

/// A strong link: exactly one of `first`/`second` must be a cat because
/// they are the only two remaining candidates for `constraint`.
public struct StrongLink: Equatable, Hashable, Sendable {
    public let constraint: ConstraintKind
    public let first: CellPosition
    public let second: CellPosition

    public init(constraint: ConstraintKind, first: CellPosition, second: CellPosition) {
        self.constraint = constraint
        self.first = first
        self.second = second
    }
}

/// The family a `ConstraintKind` belongs to, independent of its index.
enum ConstraintFamily: CaseIterable {
    case row
    case column
    case region
}

/// An exactly-one constraint together with its currently open candidates.
/// Internal engine model — not part of the public solver API.
struct ExactlyOneConstraint: Equatable {
    let kind: ConstraintKind
    let candidates: [CellPosition]
}
