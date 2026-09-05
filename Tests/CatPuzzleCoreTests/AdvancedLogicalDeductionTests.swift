import XCTest
@testable import CatPuzzleCore

/// Regression coverage for the advanced deterministic deductions added on
/// top of the basic row/column/Region singles: generalized locked sets
/// (Hall sets, K=2/3, both directions across Row/Column/Region), common
/// attack, and strong-link common elimination.
final class AdvancedLogicalDeductionTests: XCTestCase {
    // MARK: - Locked pair (K = 2)

    /// Rows 2 and 3 have been reduced (by prior exclusions) so their only
    /// remaining candidates are Regions 2 and 3. That is a locked pair in
    /// the Row -> Region direction: rows {2, 3} must be filled entirely by
    /// Regions {2, 3}, so any other Region-2/Region-3 candidate elsewhere
    /// (here, in rows 0 and 1) can be excluded.
    func testLockedPairExcludesOtherRegionCandidatesWhenRowsAreConfinedToTwoRegions() throws {
        let level = LevelDefinition(
            id: "locked-pair-row-region",
            size: 4,
            catCount: 4,
            maxMistakes: 5,
            regionIDs: [
                [0, 1, 2, 3],
                [0, 1, 2, 3],
                [2, 3, 0, 1],
                [1, 0, 3, 2],
            ]
        )
        let puzzle = try puzzle(for: level, candidates: positions([
            (0, 0), (0, 1), (0, 2), (0, 3),
            (1, 0), (1, 1), (1, 2), (1, 3),
            (2, 0), (2, 1),
            (3, 2), (3, 3),
        ]))

        let result = LogicalPuzzleSolver.solve(level: level, puzzle: puzzle)

        let sources: [ConstraintKind] = [.row(2), .row(3)]
        let targets: [ConstraintKind] = [.region(2), .region(3)]
        XCTAssertTrue(result.report.steps.contains(
            LogicalStep(
                action: .exclude(CellPosition(row: 0, column: 2)),
                reason: .lockedSet(sources: sources, targets: targets)
            )
        ))
        XCTAssertTrue(result.report.steps.contains(
            LogicalStep(
                action: .exclude(CellPosition(row: 1, column: 3)),
                reason: .lockedSet(sources: sources, targets: targets)
            )
        ))
        XCTAssertEqual(result.report.statistics.lockedPairCount, 1)
        let event = try XCTUnwrap(result.report.events.first {
            $0.technique == .lockedSet(size: 2)
        })
        XCTAssertGreaterThan(event.steps.count, 1)
        XCTAssertTrue(event.steps.allSatisfy {
            if case .lockedSet = $0.reason { return true }
            return false
        })
    }

    /// Rows 0 and 1 only have candidates in columns 0 and 1: a locked pair
    /// in the Row -> Column direction. Columns {0, 1} must be filled by
    /// rows {0, 1}, so the other rows' candidates in those columns can be
    /// excluded.
    func testLockedPairExcludesOtherRowCandidatesWhenRowsAreConfinedToTwoColumns() throws {
        let level = rowRegionLevel(id: "locked-pair-row-column")
        let puzzle = try puzzle(for: level, candidates: positions([
            (0, 0), (0, 1),
            (1, 0), (1, 1),
            (2, 0), (2, 1), (2, 2), (2, 3),
            (3, 0), (3, 1), (3, 2), (3, 3),
        ]))

        let result = LogicalPuzzleSolver.solve(level: level, puzzle: puzzle)

        let sources: [ConstraintKind] = [.row(0), .row(1)]
        let targets: [ConstraintKind] = [.column(0), .column(1)]
        XCTAssertTrue(result.report.steps.contains(
            LogicalStep(
                action: .exclude(CellPosition(row: 2, column: 0)),
                reason: .lockedSet(sources: sources, targets: targets)
            )
        ))
        XCTAssertTrue(result.report.steps.contains(
            LogicalStep(
                action: .exclude(CellPosition(row: 3, column: 1)),
                reason: .lockedSet(sources: sources, targets: targets)
            )
        ))
        XCTAssertEqual(result.report.statistics.lockedPairCount, 1)
    }

    /// Columns 2 and 3 only have candidates of Regions 2 and 3: a locked
    /// pair in the Column -> Region direction, excluding those Regions'
    /// other candidates (here, in columns 0 and 1).
    func testLockedPairExcludesOtherRegionCandidatesWhenColumnsAreConfinedToTwoRegions() throws {
        let level = LevelDefinition(
            id: "locked-pair-column-region",
            size: 4,
            catCount: 4,
            maxMistakes: 5,
            regionIDs: (0..<4).map { row in (0..<4).map { column in (row + column) % 4 } }
        )
        let puzzle = try puzzle(for: level, candidates: positions([
            (0, 0), (0, 1), (0, 2), (0, 3),
            (1, 0), (1, 1), (1, 2),
            (2, 0), (2, 1),
            (3, 0), (3, 1), (3, 3),
        ]))

        let result = LogicalPuzzleSolver.solve(level: level, puzzle: puzzle)

        let sources: [ConstraintKind] = [.column(2), .column(3)]
        let targets: [ConstraintKind] = [.region(2), .region(3)]
        XCTAssertTrue(result.report.steps.contains(
            LogicalStep(
                action: .exclude(CellPosition(row: 1, column: 1)),
                reason: .lockedSet(sources: sources, targets: targets)
            )
        ))
        XCTAssertEqual(result.report.statistics.lockedPairCount, 1)
    }

    // MARK: - Locked triple (K = 3)

    /// Rows 0-2 only have candidates in columns 0-2: a locked triple in the
    /// Row -> Column direction, excluding rows 3-5's candidates in those
    /// same three columns.
    func testLockedTripleExcludesOtherRowCandidatesWhenRowsAreConfinedToThreeColumns() throws {
        let level = rowRegionLevel(id: "locked-triple-row-column", size: 6)
        let puzzle = try puzzle(for: level, candidates: positions([
            (0, 0), (0, 1), (0, 2),
            (1, 0), (1, 1), (1, 2),
            (2, 0), (2, 1), (2, 2),
            (3, 0), (3, 1), (3, 2), (3, 3), (3, 4), (3, 5),
            (4, 0), (4, 1), (4, 2), (4, 3), (4, 4), (4, 5),
            (5, 0), (5, 1), (5, 2), (5, 3), (5, 4), (5, 5),
        ]))

        let result = LogicalPuzzleSolver.solve(level: level, puzzle: puzzle)

        let sources: [ConstraintKind] = [.row(0), .row(1), .row(2)]
        let targets: [ConstraintKind] = [.column(0), .column(1), .column(2)]
        for row in 3...5 {
            for column in 0...2 {
                XCTAssertTrue(result.report.steps.contains(
                    LogicalStep(
                        action: .exclude(CellPosition(row: row, column: column)),
                        reason: .lockedSet(sources: sources, targets: targets)
                    )
                ), "expected (\(row), \(column)) to be excluded by the locked triple")
            }
        }
        XCTAssertEqual(result.report.statistics.lockedTripleCount, 1)
    }

    // MARK: - Common attack

    /// Row 1's three remaining candidates (0,0)/(1,1)/(1,2) all conflict
    /// with (2, 1) (two via 8-adjacency, one via the shared column), so
    /// whichever of them ends up being row 1's cat, (2, 1) can never be
    /// one too.
    func testCommonAttackExcludesCandidateConflictingWithEveryRemainingRowCandidate() throws {
        let level = rowRegionLevel(id: "common-attack")
        let puzzle = try puzzle(for: level, candidates: positions([
            (0, 0), (0, 3),
            (1, 0), (1, 1), (1, 2),
            (2, 1), (2, 3),
            (3, 2), (3, 3),
        ]))

        let result = LogicalPuzzleSolver.solve(level: level, puzzle: puzzle)

        XCTAssertTrue(result.report.steps.contains(
            LogicalStep(
                action: .exclude(CellPosition(row: 2, column: 1)),
                reason: .commonAttack(
                    constraint: .row(1),
                    candidatePositions: [
                        CellPosition(row: 1, column: 0),
                        CellPosition(row: 1, column: 1),
                        CellPosition(row: 1, column: 2),
                    ]
                )
            )
        ))
        XCTAssertEqual(result.report.statistics.commonAttackCount, 1)
    }

    // MARK: - Strong link

    /// Row 1 has exactly two remaining candidates, (1, 0) and (1, 2): a
    /// strong link. (0, 1) is 8-adjacent to both, so no matter which of
    /// the two ends up being row 1's cat, (0, 1) can never be a cat.
    func testStrongLinkExcludesCandidateConflictingWithBothLinkMembers() throws {
        let level = rowRegionLevel(id: "strong-link")
        let puzzle = try puzzle(for: level, candidates: positions([
            (0, 0), (0, 1), (0, 3),
            (1, 0), (1, 2),
            (2, 0), (2, 1), (2, 3),
            (3, 0), (3, 1), (3, 2),
        ]))

        let result = LogicalPuzzleSolver.solve(level: level, puzzle: puzzle)

        XCTAssertTrue(result.report.steps.contains(
            LogicalStep(
                action: .exclude(CellPosition(row: 0, column: 1)),
                reason: .strongLinkCommonElimination(link: StrongLink(
                    constraint: .row(1),
                    first: CellPosition(row: 1, column: 0),
                    second: CellPosition(row: 1, column: 2)
                ))
            )
        ))
        XCTAssertEqual(result.report.statistics.strongLinkDeductionCount, 1)
    }

    // MARK: - Determinism / no-op guard

    func testAdvancedDeductionsAreDeterministic() throws {
        let level = rowRegionLevel(id: "advanced-deterministic")
        let puzzle = try puzzle(for: level, candidates: positions([
            (0, 0), (0, 3),
            (1, 0), (1, 1), (1, 2),
            (2, 1), (2, 3),
            (3, 2), (3, 3),
        ]))

        let first = LogicalPuzzleSolver.solve(level: level, puzzle: puzzle)
        let second = LogicalPuzzleSolver.solve(level: level, puzzle: puzzle)

        XCTAssertEqual(first, second)
    }

    /// A locked set with no exclusions to make (no candidate outside the
    /// source union remains in the target constraints) must not be
    /// recorded as a deduction or counted in statistics.
    func testLockedSetWithNoNewExclusionsIsNotCounted() throws {
        // regionIDs[row] == row uniformly, so every (row, Region) locked-set
        // candidacy is a complete no-op: a Region's full candidate set is
        // always identical to its same-indexed row's candidate set.
        let level = rowRegionLevel(id: "no-op-locked-set")
        let result = LogicalPuzzleSolver.solve(level: level)

        XCTAssertFalse(result.report.steps.contains {
            if case .lockedSet = $0.reason { return true }
            return false
        })
        XCTAssertEqual(result.report.statistics.lockedPairCount, 0)
        XCTAssertEqual(result.report.statistics.lockedTripleCount, 0)
        XCTAssertFalse(result.report.events.contains {
            if case .lockedSet = $0.technique { return true }
            return false
        })
    }

    // MARK: - Helpers

    // MARK: - Higher-order locked set (K >= 4)

    /// Rows 0-3 are each confined to columns {0, 1, 2, 3} (a full 4x4 block),
    /// so no two of them share only two columns and no three share only three
    /// — there is no locked pair or triple, and no unit is down to two
    /// candidates (no strong link) or dominated by a common attacker. The only
    /// deterministic move is the size-4 locked set (rows {0,1,2,3} own columns
    /// {0,1,2,3}), which excludes every other candidate in those columns
    /// (rows 4-7). This exercises the higher-order tier in isolation.
    func testHigherOrderLockedSetExcludesWhenFourRowsAreConfinedToFourColumns() throws {
        let level = rowRegionLevel(id: "locked-set-4-row-column", size: 8)
        var block: [(Int, Int)] = []
        for row in 0...3 {
            for column in 0...3 { block.append((row, column)) }
        }
        for row in 4...7 {
            for column in 0...7 { block.append((row, column)) }
        }
        let puzzle = try puzzle(for: level, candidates: positions(block))

        let result = LogicalPuzzleSolver.solve(level: level, puzzle: puzzle)

        let sources: [ConstraintKind] = [.row(0), .row(1), .row(2), .row(3)]
        let targets: [ConstraintKind] = [.column(0), .column(1), .column(2), .column(3)]
        for row in 4...7 {
            for column in 0...3 {
                XCTAssertTrue(result.report.steps.contains(
                    LogicalStep(
                        action: .exclude(CellPosition(row: row, column: column)),
                        reason: .lockedSet(sources: sources, targets: targets)
                    )
                ), "expected (\(row), \(column)) to be excluded by the size-4 locked set")
            }
        }
        XCTAssertEqual(result.report.statistics.lockedPairCount, 0)
        XCTAssertEqual(result.report.statistics.lockedTripleCount, 0)
        XCTAssertGreaterThanOrEqual(result.report.statistics.higherOrderLockedSetCount, 1)
        XCTAssertTrue(result.report.events.contains { $0.technique == .lockedSet(size: 4) })
    }

    /// The higher-order tier is deliberately last-resort: a shipped level that
    /// solves with the standard toolkit must report zero, proving the new scan
    /// does not perturb the existing pair/triple/attack/link sequence.
    func testBuiltInLevelRecordsNoHigherOrderLockedSet() throws {
        for level in BuiltInLevels.all {
            let result = LogicalPuzzleSolver.solve(level: level)
            XCTAssertTrue(result.isSolved)
            XCTAssertEqual(result.report.statistics.higherOrderLockedSetCount, 0)
        }
    }

    private func rowRegionLevel(id: String, size: Int = 4) -> LevelDefinition {
        LevelDefinition(
            id: id,
            size: size,
            catCount: size,
            maxMistakes: 5,
            regionIDs: (0..<size).map { row in Array(repeating: row, count: size) }
        )
    }

    private func puzzle(
        for level: LevelDefinition,
        candidates: Set<CellPosition>
    ) throws -> Puzzle {
        let states = (0..<level.size).map { row in
            (0..<level.size).map { column in
                candidates.contains(CellPosition(row: row, column: column))
                    ? CellState.empty
                    : CellState.excluded
            }
        }
        return try Puzzle(size: level.size, regionIDs: level.regionIDs, states: states)
    }

    private func positions(_ values: [(Int, Int)]) -> Set<CellPosition> {
        Set(values.map { CellPosition(row: $0.0, column: $0.1) })
    }
}
