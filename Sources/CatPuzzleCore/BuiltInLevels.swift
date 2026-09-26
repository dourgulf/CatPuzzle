/// Ordinary game progression: ten hand-authored rule-practice boards, then
/// the generated difficulty ladder. The tutorial is played before these.
public enum BuiltInLevels {
    public static let fixtures = OpeningLevels.fixtures + GeneratedLadderLevels.fixtures
    public static let all = fixtures.map(\.level)
    /// Each opening or generated group contains ten levels.
    public static let levelsPerCycle = GeneratedLadderLevels.levelsPerCycle
}
