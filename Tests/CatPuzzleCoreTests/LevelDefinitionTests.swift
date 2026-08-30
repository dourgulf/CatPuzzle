import XCTest
@testable import CatPuzzleCore

final class LevelDefinitionTests: XCTestCase {
    func testBuiltInLevelsCreateEmptySixBySixPuzzles() throws {
        let fixtures = BuiltInLevels.fixtures

        XCTAssertEqual(fixtures.count, 3)
        XCTAssertEqual(Set(fixtures.map { $0.level.id }).count, 3)

        for fixture in fixtures {
            let level = fixture.level
            let puzzle = try level.makePuzzle()

            XCTAssertEqual(level.size, 6)
            XCTAssertEqual(level.catCount, 6)
            XCTAssertEqual(level.maxMistakes, 5)
            XCTAssertEqual(level.regionIDs.count, 6)
            XCTAssertTrue(level.regionIDs.allSatisfy { $0.count == 6 })
            XCTAssertEqual(Set(level.regionIDs.flatMap { $0 }).count, 6)
            XCTAssertEqual(puzzle.size, 6)
            XCTAssertTrue(puzzle.states.allSatisfy { $0 == .empty })
        }
    }

    func testBuiltInLevelsAcceptKnownValidSolution() throws {
        let fixtures = BuiltInLevels.fixtures
        let uniqueSolutions = Set(fixtures.map { Set($0.solution) })

        XCTAssertEqual(uniqueSolutions.count, fixtures.count)

        for fixture in fixtures {
            XCTAssertEqual(fixture.solution.count, fixture.level.size)
            XCTAssertEqual(Set(fixture.solution).count, fixture.level.size)
            var puzzle = try fixture.level.makePuzzle()
            for position in fixture.solution {
                try puzzle.setState(
                    .cat,
                    atRow: position.row,
                    column: position.column
                )
            }

            XCTAssertTrue(
                PuzzleValidator.isSolved(
                    puzzle,
                    catCount: fixture.level.catCount
                ),
                fixture.level.id
            )
        }
    }

    func testVariableSizeLevelCreatesMatchingPuzzle() throws {
        let level = LevelDefinition(
            id: "small",
            size: 4,
            catCount: 4,
            maxMistakes: 3,
            regionIDs: [
                [0, 0, 0, 1],
                [0, 1, 1, 1],
                [2, 2, 2, 3],
                [2, 3, 3, 3],
            ]
        )

        let puzzle = try level.makePuzzle()

        XCTAssertEqual(puzzle.size, 4)
        XCTAssertEqual(puzzle.cells.count, 16)
        XCTAssertEqual(puzzle.cell(atRow: 3, column: 3)?.regionID, 3)
    }
}
