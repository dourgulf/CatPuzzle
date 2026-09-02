public enum LevelValidationError: Error, Equatable, Sendable {
    case invalidSize
    case invalidRegionDimensions
    case invalidCatCount
    case invalidMaxMistakes
    case invalidRegionCount
    case catCountMustEqualSize
    case invalidGivenStateDimensions
    case conflictingGivenCells
}

public enum LevelValidator {
    public static func validate(_ level: LevelDefinition) throws {
        guard level.size > 0 else {
            throw LevelValidationError.invalidSize
        }
        guard level.regionIDs.count == level.size,
              level.regionIDs.allSatisfy({ $0.count == level.size }) else {
            throw LevelValidationError.invalidRegionDimensions
        }
        guard level.catCount > 0 else {
            throw LevelValidationError.invalidCatCount
        }
        guard level.maxMistakes > 0 else {
            throw LevelValidationError.invalidMaxMistakes
        }
        guard level.catCount == level.size else {
            throw LevelValidationError.catCountMustEqualSize
        }
        guard Set(level.regionIDs.flatMap { $0 }).count == level.catCount else {
            throw LevelValidationError.invalidRegionCount
        }

        if let givenStates = level.givenStates {
            guard givenStates.count == level.size,
                  givenStates.allSatisfy({ $0.count == level.size }) else {
                throw LevelValidationError.invalidGivenStateDimensions
            }
            let puzzle = try level.makePuzzle()
            guard !PuzzleValidator.hasRowConflict(in: puzzle),
                  !PuzzleValidator.hasColumnConflict(in: puzzle),
                  !PuzzleValidator.hasRegionConflict(in: puzzle),
                  !PuzzleValidator.hasAdjacentCats(in: puzzle) else {
                throw LevelValidationError.conflictingGivenCells
            }
        }
    }
}
