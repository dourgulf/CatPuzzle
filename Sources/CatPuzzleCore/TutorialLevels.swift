/// One of the three rules a board is built from. The tutorial teaches all
/// three on a single board, one `TutorialStep` at a time.
public enum PuzzleRule: String, CaseIterable, Equatable, Sendable {
    case oneCatPerRowAndColumn
    case oneCatPerRegion
    case noTouchingCats
}

/// The single hand-authored board the game opens with, plus the scripted
/// lesson walked across it.
public struct TutorialLevel: Equatable, Sendable {
    public let fixture: LevelFixture
    /// The move-by-move lesson. Empty when the board does not fit the
    /// curriculum, which `TutorialLevelTests` rules out for the shipped
    /// board — the app then just plays it as an ordinary level.
    public let script: TutorialScript

    public init(fixture: LevelFixture) {
        self.fixture = fixture
        self.script = TutorialScript.build(for: fixture)
    }

    public var level: LevelDefinition { fixture.level }
}

/// The introduction, played once ever before the shipped ladder.
///
/// One board teaches all three rules, because the rules only become useful
/// where they meet: a Region runs out of room *because* a row was settled,
/// and the next Region runs out of room *because* a cat refused a neighbour.
/// Three separate boards could only show each rule working alone.
///
/// The board is chosen so the lesson falls out of it in the order a player
/// can follow, with no pre-placed cats to explain away:
///
/// | Step | Rule | Move |
/// | --- | --- | --- |
/// | 1 | Regions | The pink block is a single cell — the cat goes there |
/// | 2 | Rows | That row is settled, so the rest of it is out |
/// | 3 | Columns | And so is the rest of that column |
/// | 4 | Regions | Which leaves the green block exactly one cell |
/// | 5 | No touching | So the cells around that new cat are out |
/// | 6+ | All three | The player does it themselves, nudged only if stuck |
///
/// `TutorialScript` derives those steps from the board rather than listing
/// them, so the board and the lesson cannot drift apart.
public enum TutorialLevels {
    /// A tutorial is never meant to end in Game Over. The board is played in
    /// challenge mode so a wrong cat is refused instead of landing — which is
    /// what keeps the script's later steps true — and this limit sits far
    /// beyond any plausible run of refusals. The counter is hidden either way.
    private static let unreachableMistakeLimit = 9_999

    public static let basics = TutorialLevel(
        fixture: LevelFixture(
            level: LevelDefinition(
                id: "tutorial-basics",
                size: 6,
                catCount: 6,
                maxMistakes: unreachableMistakeLimit,
                regionIDs: [
                    [3, 3, 2, 2, 2, 2],
                    [3, 3, 2, 2, 2, 2],
                    [3, 0, 1, 1, 1, 1],
                    [3, 3, 4, 1, 4, 4],
                    [3, 5, 4, 4, 4, 4],
                    [5, 5, 5, 5, 5, 5],
                ]
            ),
            solution: [
                CellPosition(row: 0, column: 0),
                CellPosition(row: 1, column: 4),
                CellPosition(row: 2, column: 1),
                CellPosition(row: 3, column: 3),
                CellPosition(row: 4, column: 5),
                CellPosition(row: 5, column: 2),
            ]
        )
    )

    /// Kept a list so the app's progression, which offers tutorials before
    /// anything else and tracks them by id, does not have to special-case a
    /// count of one.
    public static let all = [basics]

    public static let fixtures = all.map(\.fixture)
}
