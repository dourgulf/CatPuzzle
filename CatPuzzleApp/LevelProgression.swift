import CatPuzzleCore

struct LevelProgression {
    let levels: [LevelDefinition]

    func level(withID id: String) -> LevelDefinition? {
        levels.first { $0.id == id }
    }

    /// 1-based position of a level in the ladder, used for player-facing
    /// numbering. Levels are generated, so their ids are slugs rather than
    /// names worth showing.
    func position(ofLevelWithID id: String) -> Int? {
        levels.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    func nextUncompletedLevel(
        completedLevelIDs: Set<String>
    ) -> LevelDefinition? {
        levels.first { !completedLevelIDs.contains($0.id) }
    }

    /// The level to play next. The ladder is a loop: once every level is
    /// complete it starts over from the first one, and `didWrap` tells the
    /// caller that the completed set belongs to the finished lap and should be
    /// cleared. Returns `nil` only when there are no levels at all.
    func nextLevel(
        completedLevelIDs: Set<String>
    ) -> (level: LevelDefinition, didWrap: Bool)? {
        if let level = nextUncompletedLevel(completedLevelIDs: completedLevelIDs) {
            return (level, false)
        }
        guard let first = levels.first else { return nil }
        return (first, true)
    }
}
