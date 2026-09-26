import XCTest
@testable import CatPuzzleCore

final class OpeningLevelsTests: XCTestCase {
    func testOpeningComesBeforeTheExistingGeneratedLadder() {
        XCTAssertEqual(OpeningLevels.fixtures.count, 10)
        XCTAssertEqual(BuiltInLevels.levelsPerCycle, 10)
        XCTAssertEqual(
            OpeningLevels.fixtures.map(\.level.size),
            [6, 6, 6, 6, 7, 7, 7, 8, 8, 8]
        )
        XCTAssertEqual(
            Array(BuiltInLevels.fixtures.prefix(10)),
            OpeningLevels.fixtures
        )
        XCTAssertEqual(
            Array(BuiltInLevels.fixtures.dropFirst(10)),
            GeneratedLadderLevels.fixtures
        )
        XCTAssertEqual(
            Set(BuiltInLevels.fixtures.map(\.level.id)).count,
            BuiltInLevels.fixtures.count
        )
        XCTAssertEqual(
            Set(BuiltInLevels.fixtures.map(\.level.regionIDs)).count,
            BuiltInLevels.fixtures.count
        )
        XCTAssertEqual(
            Set(BuiltInLevels.fixtures.map { Set($0.solution) }).count,
            BuiltInLevels.fixtures.count
        )
    }

    func testEveryOpeningHasOneSolutionAndOnlyDirectRuleDeductions() throws {
        for fixture in OpeningLevels.fixtures {
            let level = fixture.level
            try LevelValidator.validate(level)
            XCTAssertEqual(
                PuzzleSolver.solve(level: level).result,
                .unique(fixture.solution),
                level.id
            )

            let result = LogicalPuzzleSolver.solve(level: level, mode: .logicOnly)
            XCTAssertTrue(result.isSolved, level.id)
            XCTAssertEqual(result.report.statistics.placedCats, level.catCount, level.id)
            XCTAssertEqual(result.report.statistics.assumptionCount, 0, level.id)
            XCTAssertTrue(result.report.events.allSatisfy { event in
                switch event.technique {
                case .single, .propagation:
                    return true
                case .lockedSet, .commonAttack, .strongLink, .contradictionElimination:
                    return false
                }
            }, level.id)

            let reasons = result.report.steps.map(\.reason)
            XCTAssertTrue(reasons.contains { reason in
                if case .onlyCandidateForRegion = reason { return true }
                return false
            }, level.id)
            XCTAssertTrue(reasons.contains { reason in
                if case .rowAlreadyHasCat = reason { return true }
                return false
            }, level.id)
            XCTAssertTrue(reasons.contains { reason in
                if case .columnAlreadyHasCat = reason { return true }
                return false
            }, level.id)
            XCTAssertTrue(reasons.contains { reason in
                if case .adjacentToConfirmedCat = reason { return true }
                return false
            }, level.id)
        }
    }

    func testOpeningColorBlocksAreConnected() {
        for fixture in OpeningLevels.fixtures {
            let regions = fixture.level.regionIDs
            let size = fixture.level.size

            for regionID in 0..<size {
                let cells = Set((0..<size).flatMap { row in
                    (0..<size).compactMap { column -> CellPosition? in
                        regions[row][column] == regionID
                            ? CellPosition(row: row, column: column)
                            : nil
                    }
                })
                guard let start = cells.first else {
                    return XCTFail("Missing block \(regionID) in \(fixture.level.id)")
                }

                var visited: Set<CellPosition> = []
                var pending = [start]
                while let current = pending.popLast() {
                    guard visited.insert(current).inserted else { continue }
                    pending.append(contentsOf: [
                        CellPosition(row: current.row - 1, column: current.column),
                        CellPosition(row: current.row + 1, column: current.column),
                        CellPosition(row: current.row, column: current.column - 1),
                        CellPosition(row: current.row, column: current.column + 1),
                    ].filter(cells.contains))
                }
                XCTAssertEqual(visited, cells, "\(fixture.level.id) block \(regionID)")
            }
        }
    }

    func testColumnRuleIsNeededBeforeTheLastCatInLevelsSevenAndEight() {
        let examples: [(index: Int, firstCats: [CellPosition], nextCat: CellPosition)] = [
            (
                6,
                [CellPosition(row: 0, column: 1), CellPosition(row: 1, column: 3),
                 CellPosition(row: 2, column: 5)],
                CellPosition(row: 3, column: 0)
            ),
            (
                7,
                [CellPosition(row: 0, column: 0), CellPosition(row: 1, column: 2),
                 CellPosition(row: 2, column: 4)],
                CellPosition(row: 3, column: 6)
            ),
        ]

        for example in examples {
            let level = OpeningLevels.fixtures[example.index].level
            let regionID = level.regionIDs[example.nextCat.row][example.nextCat.column]
            let regionCells = (0..<level.size).flatMap { row in
                (0..<level.size).compactMap { column -> CellPosition? in
                    level.regionIDs[row][column] == regionID
                        ? CellPosition(row: row, column: column)
                        : nil
                }
            }
            let availableWithoutColumns = regionCells.filter { cell in
                example.firstCats.allSatisfy { cat in
                    cat.row != cell.row
                        && !(abs(cat.row - cell.row) <= 1
                             && abs(cat.column - cell.column) <= 1)
                }
            }
            let availableWithColumns = availableWithoutColumns.filter { cell in
                example.firstCats.allSatisfy { $0.column != cell.column }
            }

            XCTAssertEqual(availableWithoutColumns.count, 2, level.id)
            XCTAssertEqual(availableWithColumns, [example.nextCat], level.id)
        }
    }
}
