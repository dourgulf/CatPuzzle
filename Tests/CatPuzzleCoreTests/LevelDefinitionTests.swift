import XCTest
@testable import CatPuzzleCore

final class LevelDefinitionTests: XCTestCase {
    func testBuiltInLevelsCreateEmptySixBySixPuzzles() throws {
        let levels = BuiltInLevels.all

        XCTAssertEqual(levels.count, 3)
        XCTAssertEqual(Set(levels.map(\.id)).count, 3)

        for level in levels {
            let puzzle = try level.makePuzzle()

            XCTAssertEqual(level.size, 6)
            XCTAssertEqual(level.regionIDs.count, 6)
            XCTAssertTrue(level.regionIDs.allSatisfy { $0.count == 6 })
            XCTAssertEqual(Set(level.regionIDs.flatMap { $0 }).count, 6)
            XCTAssertEqual(puzzle.size, 6)
            XCTAssertTrue(puzzle.states.allSatisfy { $0 == .empty })
        }
    }

    func testBuiltInLevelsAcceptKnownValidSolution() throws {
        let catPositions = [
            (0, 1), (1, 3), (2, 5), (3, 0), (4, 2), (5, 4),
        ]

        for level in BuiltInLevels.all {
            var puzzle = try level.makePuzzle()
            for (row, column) in catPositions {
                try puzzle.setState(.cat, atRow: row, column: column)
            }

            XCTAssertTrue(PuzzleValidator.isSolved(puzzle), level.id)
        }
    }
}
