import XCTest
@testable import CatPuzzleCore

/// The later ladder is generated offline, so these assert its *shape* rather
/// than any individual board. The hand-authored opening has separate tests.
final class LevelLadderTests: XCTestCase {
    /// Board size for each 1-based slot of one cycle: one 8x8 opener, three
    /// 9x9, then six 10x10 ending on the tier bump.
    private let expectedSizes = [8, 9, 9, 9, 10, 10, 10, 10, 10, 10]

    private var cycles: [[LevelFixture]] {
        stride(
            from: 0,
            to: GeneratedLadderLevels.fixtures.count,
            by: GeneratedLadderLevels.levelsPerCycle
        ).map { start in
            Array(
                GeneratedLadderLevels.fixtures[
                    start..<start + GeneratedLadderLevels.levelsPerCycle
                ]
            )
        }
    }

    func testLadderIsWholeCyclesOfDistinctLevels() {
        XCTAssertEqual(GeneratedLadderLevels.levelsPerCycle, expectedSizes.count)
        XCTAssertFalse(GeneratedLadderLevels.fixtures.isEmpty)
        XCTAssertEqual(
            GeneratedLadderLevels.fixtures.count % GeneratedLadderLevels.levelsPerCycle,
            0
        )
        XCTAssertEqual(
            Set(GeneratedLadderLevels.fixtures.map(\.level.id)).count,
            GeneratedLadderLevels.fixtures.count
        )
        XCTAssertEqual(
            Set(GeneratedLadderLevels.fixtures.map(\.level.regionIDs)).count,
            GeneratedLadderLevels.fixtures.count,
            "two shipped levels share a Region layout"
        )
        // Two boards can differ in Region layout and still put the cats in the
        // same places, which reads as a repeat rather than a new puzzle.
        XCTAssertEqual(
            Set(GeneratedLadderLevels.fixtures.map { Set($0.solution) }).count,
            GeneratedLadderLevels.fixtures.count,
            "two shipped levels share a solution"
        )
    }

    func testEveryCycleClimbsTheSameBoardSizes() {
        for (cycleIndex, cycle) in cycles.enumerated() {
            XCTAssertEqual(
                cycle.map(\.level.size),
                expectedSizes,
                "cycle \(cycleIndex + 1)"
            )
        }
    }

    /// The player-facing promise: inside a cycle each level is at least as hard
    /// as the one before it, and the cycle ends on its hardest board.
    func testEveryCycleRisesInMeasuredDifficulty() {
        for (cycleIndex, cycle) in cycles.enumerated() {
            let scores = cycle.map { fixture in
                PuzzleDifficultyAnalyzer.analyze(
                    LogicalPuzzleSolver.solve(level: fixture.level, mode: .logicOnly).report
                ).score
            }

            for (slot, pair) in zip(scores, scores.dropFirst()).enumerated() {
                XCTAssertLessThanOrEqual(
                    pair.0,
                    pair.1,
                    "cycle \(cycleIndex + 1) drops in difficulty at slot \(slot + 2): \(scores)"
                )
            }
            XCTAssertEqual(
                scores.last,
                scores.max(),
                "cycle \(cycleIndex + 1) does not end on its hardest level: \(scores)"
            )
        }
    }

    /// Every cycle covers the same difficulty shape, so the same slot across
    /// cycles must land on comparable boards rather than drifting.
    func testMatchingSlotsAcrossCyclesUseTheSameBoardSize() {
        guard let reference = cycles.first else { return XCTFail("no cycles") }

        for cycle in cycles.dropFirst() {
            XCTAssertEqual(cycle.map(\.level.size), reference.map(\.level.size))
        }
    }
}
