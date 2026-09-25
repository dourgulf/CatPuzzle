/// How much help one tutorial step gives.
public enum TutorialCoaching: Equatable, Sendable {
    /// The board is masked down to the step's `spotlight` and only the cells
    /// the step asks for stay tappable, so the move cannot be got wrong.
    case guided
    /// The whole board stays live and nothing is pointed at. The player is
    /// left to find the move; the app only nudges once they have had time to
    /// look.
    case discovery
}

/// The move a step is waiting for. A step is finished the moment the board
/// reads this way — in whatever order, and however the player got there.
public enum TutorialTask: Equatable, Sendable {
    case placeCat(CellPosition)
    case exclude([CellPosition])

    public var positions: [CellPosition] {
        switch self {
        case let .placeCat(position): [position]
        case let .exclude(positions): positions
        }
    }
}

/// Why the step's move is the right one. This stays structured rather than
/// pre-rendered: the core carries no player-facing text, and naming a Region
/// needs the board's color settings, which live in the app layer.
public enum TutorialLesson: Equatable, Sendable {
    /// This Region is a single cell, so its cat has nowhere else to go. The
    /// board's opening move, and the one rule that needs no deduction first.
    case regionIsASingleCell(regionID: Int)
    case regionHasOneCellLeft(regionID: Int)
    case rowHasOneCellLeft(row: Int)
    case columnHasOneCellLeft(column: Int)
    case rowAlreadyHasItsCat(row: Int)
    case columnAlreadyHasItsCat(column: Int)
    case catsNeverTouch(CellPosition)
    /// Every cell the cats on the board rule out, for whatever reason — the
    /// step where the three rules are used together rather than one at a time.
    case everythingTheCatsRuleOut

    /// The rule this lesson is about, or nil where it is about all three.
    public var rule: PuzzleRule? {
        switch self {
        case .regionIsASingleCell, .regionHasOneCellLeft:
            .oneCatPerRegion
        case .rowHasOneCellLeft, .columnHasOneCellLeft,
             .rowAlreadyHasItsCat, .columnAlreadyHasItsCat:
            .oneCatPerRowAndColumn
        case .catsNeverTouch:
            .noTouchingCats
        case .everythingTheCatsRuleOut:
            nil
        }
    }
}

public struct TutorialStep: Equatable, Sendable {
    public let lesson: TutorialLesson
    public let task: TutorialTask
    public let coaching: TutorialCoaching
    /// The cells left lit while the rest of the board is masked: the whole
    /// row, column or Region the lesson is about, not just the answer, so the
    /// player sees the reasoning. Empty on a `.discovery` step, which masks
    /// nothing.
    public let spotlight: [CellPosition]

    public init(
        lesson: TutorialLesson,
        task: TutorialTask,
        coaching: TutorialCoaching,
        spotlight: [CellPosition]
    ) {
        self.lesson = lesson
        self.task = task
        self.coaching = coaching
        self.spotlight = spotlight
    }
}

/// The tutorial board's lesson, one move at a time.
///
/// The steps are **derived from the board**, not listed alongside it: a
/// curriculum of five hand-ordered openings (Region, row, column, Region,
/// no-touching) is resolved against the actual board, and everything after
/// that is the same loop the player will use for the rest of their life with
/// the game — place the cat some block, row or column has been narrowed down
/// to, then mark everything that cat rules out. So the board can be swapped
/// without rewriting the lesson, and a board that cannot teach in this order
/// produces no steps at all rather than a lesson that lies.
public struct TutorialScript: Equatable, Sendable {
    public let steps: [TutorialStep]

    public var isEmpty: Bool { steps.isEmpty }

    public init(steps: [TutorialStep]) {
        self.steps = steps
    }

    public static func build(for fixture: LevelFixture) -> TutorialScript {
        guard var board = Board(level: fixture.level) else {
            return TutorialScript(steps: [])
        }
        let solution = Set(fixture.solution)
        var steps: [TutorialStep] = []

        // 1. The one Region that is a single cell. Nothing has to be deduced
        //    to see it, which is why the board opens here.
        let singleCellRegions = board.regionIDs.filter {
            board.cells(inRegion: $0).count == 1
        }
        guard singleCellRegions.count == 1,
              let regionID = singleCellRegions.first,
              let first = board.cells(inRegion: regionID).first,
              solution.contains(first) else {
            return TutorialScript(steps: [])
        }
        steps.append(
            TutorialStep(
                lesson: .regionIsASingleCell(regionID: regionID),
                task: .placeCat(first),
                coaching: .guided,
                spotlight: board.cells(inRegion: regionID)
            )
        )
        board.placeCat(first)

        // 2 and 3. That cat settles its row and its column, one rule each.
        guard let rowStep = board.clearingStep(
            lesson: .rowAlreadyHasItsCat(row: first.row),
            spotlight: board.cells(inRow: first.row)
        ) else {
            return TutorialScript(steps: [])
        }
        steps.append(rowStep)
        board.exclude(rowStep.task.positions)

        guard let columnStep = board.clearingStep(
            lesson: .columnAlreadyHasItsCat(column: first.column),
            spotlight: board.cells(inColumn: first.column)
        ) else {
            return TutorialScript(steps: [])
        }
        steps.append(columnStep)
        board.exclude(columnStep.task.positions)

        // 4. Which has to leave exactly one Region with one cell left — and
        //    no other constraint forced at the same time, or the step would
        //    be pointing at one of several equally good moves.
        let forced = board.forcedPlacements()
        guard forced.count == 1,
              case let (.region(secondRegionID), second) = forced[0],
              solution.contains(second) else {
            return TutorialScript(steps: [])
        }
        steps.append(
            TutorialStep(
                lesson: .regionHasOneCellLeft(regionID: secondRegionID),
                task: .placeCat(second),
                coaching: .guided,
                spotlight: board.cells(inRegion: secondRegionID)
            )
        )
        board.placeCat(second)

        // 5. The third rule, on the cat the player just placed: a tutorial
        //    that showed it on a stale cat would be asking them to look
        //    somewhere they are not looking.
        guard let touchingStep = board.clearingStep(
            lesson: .catsNeverTouch(second),
            spotlight: board.block(around: second),
            minimumCells: 2,
            from: board.neighbors(of: second)
        ) else {
            return TutorialScript(steps: [])
        }
        steps.append(touchingStep)
        board.exclude(touchingStep.task.positions)

        // 6 onwards. The lesson is over; the loop the game is actually played
        // in begins, and the player is left to run it.
        while board.catCount < fixture.level.catCount {
            if let cleanup = board.cleanupStep() {
                steps.append(cleanup)
                board.exclude(cleanup.task.positions)
            }

            let forced = board.forcedPlacements()
            guard let (constraint, target) = forced.first,
                  solution.contains(target) else {
                return TutorialScript(steps: [])
            }
            steps.append(
                TutorialStep(
                    lesson: .forcedPlacement(in: constraint),
                    task: .placeCat(target),
                    coaching: .discovery,
                    spotlight: []
                )
            )
            board.placeCat(target)
        }

        guard board.placedCats == solution else {
            return TutorialScript(steps: [])
        }
        return TutorialScript(steps: steps)
    }
}

private extension TutorialLesson {
    static func forcedPlacement(in constraint: ConstraintKind) -> TutorialLesson {
        switch constraint {
        case let .row(row): .rowHasOneCellLeft(row: row)
        case let .column(column): .columnHasOneCellLeft(column: column)
        case let .region(regionID): .regionHasOneCellLeft(regionID: regionID)
        }
    }
}

/// The board as the script walks it: what the player would be looking at
/// after every step so far has been carried out.
private struct Board {
    let level: LevelDefinition
    private var states: [[CellState]]
    private var cats: [CellPosition] = []

    var size: Int { level.size }
    var catCount: Int { cats.count }
    var placedCats: Set<CellPosition> { Set(cats) }
    var regionIDs: [Int] { Array(0..<level.catCount) }

    init?(level: LevelDefinition) {
        guard (try? LevelValidator.validate(level)) != nil,
              level.givenPositions.isEmpty else {
            // A tutorial board with pre-placed cats would open by asking the
            // player to accept a move nobody made.
            return nil
        }
        self.level = level
        self.states = Array(
            repeating: Array(repeating: CellState.empty, count: level.size),
            count: level.size
        )
    }

    func regionID(of position: CellPosition) -> Int {
        level.regionIDs[position.row][position.column]
    }

    func isEmpty(_ position: CellPosition) -> Bool {
        states[position.row][position.column] == .empty
    }

    /// True when some cat already on the board forbids a cat here, whether or
    /// not the player has marked the cell yet.
    func isRuledOut(_ position: CellPosition) -> Bool {
        cats.contains { cat in
            cat.row == position.row
                || cat.column == position.column
                || regionID(of: cat) == regionID(of: position)
                || (abs(cat.row - position.row) <= 1
                    && abs(cat.column - position.column) <= 1)
        }
    }

    func cells(inRow row: Int) -> [CellPosition] {
        (0..<size).map { CellPosition(row: row, column: $0) }
    }

    func cells(inColumn column: Int) -> [CellPosition] {
        (0..<size).map { CellPosition(row: $0, column: column) }
    }

    func cells(inRegion regionID: Int) -> [CellPosition] {
        allPositions.filter { self.regionID(of: $0) == regionID }
    }

    func neighbors(of position: CellPosition) -> [CellPosition] {
        block(around: position).filter { $0 != position }
    }

    /// The 3x3 the no-touching rule is about, clipped to the board.
    func block(around position: CellPosition) -> [CellPosition] {
        let rows = max(0, position.row - 1)...min(size - 1, position.row + 1)
        let columns = max(0, position.column - 1)...min(size - 1, position.column + 1)
        return rows.flatMap { row in
            columns.map { CellPosition(row: row, column: $0) }
        }
    }

    var allPositions: [CellPosition] {
        (0..<size).flatMap { row in
            (0..<size).map { CellPosition(row: row, column: $0) }
        }
    }

    /// Every row, column and Region still waiting for its cat that has been
    /// narrowed to a single unmarked cell — the deductions a player can make
    /// by looking, with no candidate bookkeeping of their own. Regions come
    /// first because a block is the smallest thing on the board and so the
    /// easiest place to notice one cell left.
    func forcedPlacements() -> [(ConstraintKind, CellPosition)] {
        var found: [(ConstraintKind, CellPosition)] = []
        for regionID in regionIDs {
            append(&found, .region(regionID), cells(inRegion: regionID))
        }
        for row in 0..<size {
            append(&found, .row(row), cells(inRow: row))
        }
        for column in 0..<size {
            append(&found, .column(column), cells(inColumn: column))
        }
        return found
    }

    private func append(
        _ found: inout [(ConstraintKind, CellPosition)],
        _ constraint: ConstraintKind,
        _ cells: [CellPosition]
    ) {
        guard !cells.contains(where: { states[$0.row][$0.column] == .cat }) else {
            return
        }
        let open = cells.filter(isEmpty)
        guard open.count == 1, let only = open.first else { return }
        found.append((constraint, only))
    }

    /// A step asking for every still-unmarked cell out of `candidates` that a
    /// cat already rules out, or nil when there is nothing left to mark.
    func clearingStep(
        lesson: TutorialLesson,
        spotlight: [CellPosition],
        minimumCells: Int = 1,
        from candidates: [CellPosition]? = nil
    ) -> TutorialStep? {
        let targets = (candidates ?? spotlight).filter(isEmpty)
        guard targets.count >= minimumCells else { return nil }
        return TutorialStep(
            lesson: lesson,
            task: .exclude(targets),
            coaching: .guided,
            spotlight: spotlight
        )
    }

    /// Everything on the board the cats rule out and the player has not
    /// marked yet, as one unguided step. This is what keeps the next
    /// `forcedPlacements()` honest: a cell left unmarked would still look
    /// open, and the script would point at a deduction the player cannot see.
    func cleanupStep() -> TutorialStep? {
        let targets = allPositions.filter { isEmpty($0) && isRuledOut($0) }
        guard !targets.isEmpty else { return nil }
        return TutorialStep(
            lesson: .everythingTheCatsRuleOut,
            task: .exclude(targets),
            coaching: .discovery,
            spotlight: []
        )
    }

    mutating func placeCat(_ position: CellPosition) {
        states[position.row][position.column] = .cat
        cats.append(position)
    }

    mutating func exclude(_ positions: [CellPosition]) {
        for position in positions {
            states[position.row][position.column] = .excluded
        }
    }
}
