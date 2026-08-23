import CatPuzzleCore

struct LevelProgression {
    let levels: [LevelDefinition]

    func level(withID id: String) -> LevelDefinition? {
        levels.first { $0.id == id }
    }

    func nextUncompletedLevel(
        completedLevelIDs: Set<String>
    ) -> LevelDefinition? {
        levels.first { !completedLevelIDs.contains($0.id) }
    }
}
