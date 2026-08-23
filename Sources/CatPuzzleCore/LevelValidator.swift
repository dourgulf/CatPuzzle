public enum LevelValidationError: Error, Equatable, Sendable {
    case invalidSize
    case invalidColorDimensions
    case invalidCatCount
    case invalidMaxMistakes
    case invalidColorCount
    case catCountMustEqualSize
}

public enum LevelValidator {
    public static func validate(_ level: LevelDefinition) throws {
        guard level.size > 0 else {
            throw LevelValidationError.invalidSize
        }
        guard level.colorIDs.count == level.size,
              level.colorIDs.allSatisfy({ $0.count == level.size }) else {
            throw LevelValidationError.invalidColorDimensions
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
        guard Set(level.colorIDs.flatMap { $0 }).count == level.catCount else {
            throw LevelValidationError.invalidColorCount
        }
    }
}
