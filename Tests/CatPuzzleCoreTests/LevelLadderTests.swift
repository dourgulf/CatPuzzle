import XCTest
@testable import CatPuzzleCore

/// The shipped ladder is generated offline, so these assert its *shape* — the
/// promise the player experience rests on — rather than any individual board.
/// Regenerating `BuiltInLevels` must keep every one of them true.
final class LevelLadderTests: XCTestCase {
    /// Board size for each 1-based slot of one cycle: one 8x8 opener, three
    /// 9x9, then six 10x10 ending on the tier bump.
    private let expectedSizes = [8, 9, 9, 9, 10, 10, 10, 10, 10, 10]

    private var cycles: [[LevelFixture]] {
        stride(
            from: 0,
            to: BuiltInLevels.fixtures.count,
            by: BuiltInLevels.levelsPerCycle
        ).map { start in
            Array(BuiltInLevels.fixtures[start..<start + BuiltInLevels.levelsPerCycle])
        }
    }

    func testLadderIsWholeCyclesOfDistinctLevels() {
        XCTAssertEqual(BuiltInLevels.levelsPerCycle, expectedSizes.count)
        XCTAssertFalse(BuiltInLevels.fixtures.isEmpty)
        XCTAssertEqual(BuiltInLevels.fixtures.count % BuiltInLevels.levelsPerCycle, 0)
        XCTAssertEqual(
            Set(BuiltInLevels.fixtures.map(\.level.id)).count,
            BuiltInLevels.fixtures.count
        )
        XCTAssertEqual(
            Set(BuiltInLevels.fixtures.map(\.level.regionIDs)).count,
            BuiltInLevels.fixtures.count,
            "two shipped levels share a Region layout"
        )
        // Two boards can differ in Region layout and still put the cats in the
        // same places, which reads as a repeat rather than a new puzzle.
        XCTAssertEqual(
            Set(BuiltInLevels.fixtures.map { Set($0.solution) }).count,
            BuiltInLevels.fixtures.count,
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
