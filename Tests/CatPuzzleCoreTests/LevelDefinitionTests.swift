import XCTest
@testable import CatPuzzleCore

final class LevelDefinitionTests: XCTestCase {
    func testBuiltInLevelsCreateEmptySquarePuzzles() throws {
        let fixtures = BuiltInLevels.fixtures

        XCTAssertFalse(fixtures.isEmpty)
        XCTAssertEqual(Set(fixtures.map { $0.level.id }).count, fixtures.count)

        for fixture in fixtures {
            let level = fixture.level
            let puzzle = try level.makePuzzle()
            let size = level.size

            XCTAssertTrue((6...10).contains(size), level.id)
            XCTAssertEqual(level.catCount, size, level.id)
            XCTAssertEqual(level.maxMistakes, 3, level.id)
            XCTAssertEqual(level.regionIDs.count, size, level.id)
            XCTAssertTrue(level.regionIDs.allSatisfy { $0.count == size }, level.id)
            XCTAssertEqual(Set(level.regionIDs.flatMap { $0 }).count, size, level.id)
            XCTAssertEqual(puzzle.size, size, level.id)
            XCTAssertTrue(puzzle.states.allSatisfy { $0 == .empty }, level.id)
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

    func testGivenStatesPrefillPuzzleAndReportGivenPositions() throws {
        let level = LevelDefinition(
            id: "with-givens",
            size: 4,
            catCount: 4,
            maxMistakes: 3,
            regionIDs: [
                [0, 0, 0, 1],
                [0, 1, 1, 1],
                [2, 2, 2, 3],
                [2, 3, 3, 3],
            ],
            givenStates: [
                [.empty, .cat, .empty, .empty],
                [.empty, .empty, .empty, .empty],
                [.empty, .empty, .empty, .excluded],
                [.empty, .empty, .empty, .empty],
            ]
        )

        let puzzle = try level.makePuzzle()

        XCTAssertEqual(
            level.givenPositions,
            [CellPosition(row: 0, column: 1), CellPosition(row: 2, column: 3)]
        )
        XCTAssertEqual(puzzle.state(atRow: 0, column: 1), .cat)
        XCTAssertEqual(puzzle.state(atRow: 2, column: 3), .excluded)
        XCTAssertEqual(puzzle.state(atRow: 0, column: 0), .empty)
    }

    func testNoGivenStatesReportsEmptyGivenPositions() {
        XCTAssertEqual(SampleLevels.meadow.givenPositions, [])
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
