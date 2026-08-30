import XCTest
@testable import CatPuzzleCore

final class PuzzleSolverTests: XCTestCase {
    func testEveryBuiltInLevelIsValidAndHasExpectedUniqueSolution() throws {
        for fixture in BuiltInLevels.fixtures {
            try LevelValidator.validate(fixture.level)
            XCTAssertEqual(
                PuzzleSolver.solve(level: fixture.level),
                .unique(fixture.solution),
                fixture.level.id
            )

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

    func testUnsolvableRegionLevelReturnsNone() throws {
        let level = makeLevel(
            id: "none",
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

    func testLevelWithSeveralSolutionsReturnsMultipleAndStopsAtLimit() {
        let level = makeLevel(
            id: "multiple",
            size: 6,
            regionIDs: (0..<6).map { row in
                Array(repeating: row, count: 6)
            }
        )

        XCTAssertEqual(PuzzleSolver.solve(level: level), .multiple)
        XCTAssertEqual(PuzzleSolver.solutions(for: level).count, 2)
        XCTAssertEqual(PuzzleSolver.solutions(for: level, limit: 1).count, 1)
    }

    func testSolverUsesRegionConstraintForDisconnectedRegions() {
        let level = makeLevel(
            id: "disconnected-regions",
            size: 4,
            regionIDs: [
                [3, 0, 0, 2],
                [0, 2, 3, 1],
                [2, 1, 0, 1],
                [1, 2, 3, 3],
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

    func testSolverDoesNotReadFixtureSolution() {
        let incorrectFixture = LevelFixture(
            level: BuiltInLevels.meadow,
            solution: [CellPosition(row: 0, column: 0)]
        )

        XCTAssertNotEqual(
            PuzzleSolver.solve(level: incorrectFixture.level),
            .unique(incorrectFixture.solution)
        )
    }

    private func makeLevel(
        id: String,
        size: Int,
        regionIDs: [[Int]]
    ) -> LevelDefinition {
        LevelDefinition(
            id: id,
            size: size,
            catCount: size,
            maxMistakes: 5,
            regionIDs: regionIDs
        )
    }
}
