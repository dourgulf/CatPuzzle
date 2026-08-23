import XCTest
@testable import CatPuzzleCore

final class PuzzleSolverTests: XCTestCase {
    func testMeadowHasExpectedUniqueSolution() {
        assertUniqueSolution(for: BuiltInLevels.meadowFixture)
    }

    func testRiverHasExpectedUniqueSolution() {
        assertUniqueSolution(for: BuiltInLevels.riverFixture)
    }

    func testTerracesHasExpectedUniqueSolution() {
        assertUniqueSolution(for: BuiltInLevels.terracesFixture)
    }

    func testUnsolvableLevelReturnsNone() throws {
        let level = LevelDefinition(
            id: "unsolvable",
            size: 4,
            regionIDs: [
                [1, 1, 2, 0],
                [1, 3, 2, 0],
                [1, 1, 1, 0],
                [1, 1, 1, 0],
            ]
        )

        try LevelValidator.validate(level)
        XCTAssertEqual(PuzzleSolver.solve(level: level), .none)
    }

    func testLevelWithSeveralSolutionsReturnsMultiple() {
        let level = LevelDefinition(
            id: "multiple",
            size: 6,
            regionIDs: (0..<6).map { row in
                Array(repeating: row, count: 6)
            }
        )

        XCTAssertEqual(PuzzleSolver.solve(level: level), .multiple)
    }

    func testSolutionsStopsAtRequestedLimit() {
        let level = LevelDefinition(
            id: "limited",
            size: 6,
            regionIDs: (0..<6).map { row in
                Array(repeating: row, count: 6)
            }
        )

        XCTAssertEqual(PuzzleSolver.solutions(for: level, limit: 1).count, 1)
        XCTAssertEqual(PuzzleSolver.solutions(for: level).count, 2)
    }

    func testSolverSupportsFourByFourLevel() {
        let level = LevelDefinition(
            id: "four-by-four",
            size: 4,
            regionIDs: [
                [0, 0, 0, 1],
                [0, 1, 1, 1],
                [2, 2, 2, 3],
                [2, 3, 3, 3],
            ]
        )

        XCTAssertEqual(
            PuzzleSolver.solve(level: level),
            .unique([
                CellPosition(row: 0, column: 1),
                CellPosition(row: 1, column: 3),
                CellPosition(row: 2, column: 0),
                CellPosition(row: 3, column: 2),
            ])
        )
    }

    func testSolverUsesLevelDataRatherThanFixtureSolution() {
        let incorrectFixture = LevelFixture(
            level: BuiltInLevels.meadow,
            solution: [CellPosition(row: 0, column: 0)]
        )

        XCTAssertNotEqual(
            PuzzleSolver.solve(level: incorrectFixture.level),
            .unique(incorrectFixture.solution)
        )
    }

    func testEveryBuiltInLevelIsValidAndUniquelySolvable() throws {
        for fixture in BuiltInLevels.fixtures {
            try LevelValidator.validate(fixture.level)
            assertUniqueSolution(for: fixture)

            var puzzle = try fixture.level.makePuzzle()
            for position in fixture.solution {
                try puzzle.setState(
                    .cat,
                    atRow: position.row,
                    column: position.column
                )
            }
            XCTAssertTrue(PuzzleValidator.isSolved(puzzle), fixture.level.id)
        }
    }

    private func assertUniqueSolution(
        for fixture: LevelFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            PuzzleSolver.solve(level: fixture.level),
            .unique(fixture.solution),
            fixture.level.id,
            file: file,
            line: line
        )
    }
}
