import XCTest
@testable import CatPuzzleCore

final class LogicalHintEngineTests: XCTestCase {
    func testNextHintPlacesOnlyTheDirectlyDeducedCat() throws {
        let level = BuiltInLevels.meadow
        var puzzle = try level.makePuzzle()
        for column in 0..<level.size where column != 1 {
            try puzzle.setState(.excluded, atRow: 0, column: column)
        }

        let hint = try XCTUnwrap(
            LogicalHintEngine.nextHint(level: level, puzzle: puzzle).hint
        )

        XCTAssertEqual(
            hint,
            LogicalHint(
                actions: [.placeCat(CellPosition(row: 0, column: 1))],
                reason: .onlyCandidateInRow(row: 0)
            )
        )
    }

    func testHintFromConfirmedCatGroupsOneTrueExclusionReason() throws {
        let level = BuiltInLevels.meadow
        var puzzle = try level.makePuzzle()
        try puzzle.setState(.cat, atRow: 0, column: 1)

        let hint = try XCTUnwrap(
            LogicalHintEngine.nextHint(level: level, puzzle: puzzle).hint
        )

        XCTAssertEqual(hint.reason, .rowAlreadyHasCat(row: 0))
        XCTAssertFalse(hint.actions.isEmpty)
        XCTAssertTrue(hint.actions.allSatisfy {
            if case .exclude = $0 { return true }
            return false
        })
        XCTAssertTrue(hint.positions.allSatisfy { $0.row == 0 })
    }

    /// A level whose Regions duplicate its rows: no deterministic technique
    /// applies, and it has more than one solution.
    private func multiSolutionLevel() -> LevelDefinition {
        LevelDefinition(
            id: "hint-stuck",
            size: 4,
            catCount: 4,
            maxMistakes: 5,
            regionIDs: [
                [0, 0, 0, 0],
                [1, 1, 1, 1],
                [2, 2, 2, 2],
                [3, 3, 3, 3],
            ]
        )
    }

    func testStuckBoardDoesNotPeekAtACompleteSolution() throws {
        let level = multiSolutionLevel()

        let hint = try XCTUnwrap(
            LogicalHintEngine.nextHint(
                level: level,
                puzzle: try level.makePuzzle()
            ).hint
        )

        // The fallback may only refute a candidate, never reveal a cat: with
        // several solutions there is no cat it could legitimately place.
        XCTAssertTrue(hint.actions.allSatisfy { action in
            if case .exclude = action { return true }
            return false
        })
        guard case .contradictionFromAssumption = hint.reason else {
            return XCTFail("expected the depth-1 fallback, got \(hint.reason)")
        }
    }

    func testAssumptionFallbackNamesTheStarvedConstraint() throws {
        let level = multiSolutionLevel()

        let hint = try XCTUnwrap(
            LogicalHintEngine.nextHint(
                level: level,
                puzzle: try level.makePuzzle()
            ).hint
        )

        guard case let .contradictionFromAssumption(_, contradicting) = hint.reason else {
            return XCTFail("expected a contradiction reason")
        }
        XCTAssertNotNil(
            contradicting,
            "the hint text explains which constraint the assumption starved"
        )
    }

    func testDeterministicTechniqueWinsOverTheAssumptionFallback() throws {
        let level = BuiltInLevels.meadow
        var puzzle = try level.makePuzzle()
        for column in 0..<level.size where column != 1 {
            try puzzle.setState(.excluded, atRow: 0, column: column)
        }

        let hint = try XCTUnwrap(
            LogicalHintEngine.nextHint(level: level, puzzle: puzzle).hint
        )

        XCTAssertEqual(hint.reason, .onlyCandidateInRow(row: 0))
    }

    func testStarvedConstraintIsReportedInsteadOfSilence() throws {
        let level = BuiltInLevels.meadow
        var puzzle = try level.makePuzzle()
        // The player wrongly excludes an entire row.
        for column in 0..<level.size {
            try puzzle.setState(.excluded, atRow: 2, column: column)
        }

        let outcome = LogicalHintEngine.nextHint(level: level, puzzle: puzzle)

        XCTAssertEqual(outcome, .contradiction(.starvedConstraint(.row(2))))
        XCTAssertNil(outcome.hint)
    }

    /// A real board (Docs/demo 231, six deductions in) where a strong link and
    /// a common attack both apply. The strong link is the easier read -- two
    /// candidates rather than four -- and also removes more cells, so the hint
    /// must offer it even though `solve`'s frozen scan order looks at common
    /// attack first.
    func testHintPrefersTheStrongLinkOverACommonAttack() throws {
        let level = LevelDefinition(
            id: "hint-technique-order",
            size: 8,
            catCount: 8,
            maxMistakes: 5,
            regionIDs: [
                [0, 1, 1, 2, 2, 2, 2, 3],
                [0, 1, 0, 0, 2, 3, 2, 3],
                [0, 1, 0, 4, 2, 3, 2, 3],
                [0, 1, 0, 4, 3, 3, 2, 3],
                [0, 0, 0, 4, 4, 3, 3, 3],
                [0, 5, 4, 4, 4, 4, 3, 6],
                [0, 5, 5, 5, 3, 3, 3, 6],
                [5, 5, 5, 5, 3, 7, 3, 6],
            ]
        )
        var puzzle = try level.makePuzzle()
        try puzzle.setState(.cat, atRow: 7, column: 5)
        let excluded = [
            (0, 5), (0, 7), (1, 2), (1, 3), (1, 5), (1, 7), (2, 2), (2, 5),
            (2, 7), (3, 2), (3, 5), (3, 7), (4, 1), (4, 2), (4, 5), (4, 7),
            (5, 0), (5, 2), (5, 3), (5, 4), (5, 5), (5, 6), (6, 0), (6, 3),
            (6, 4), (6, 5), (6, 6), (7, 0), (7, 1), (7, 2), (7, 3), (7, 4),
            (7, 6), (7, 7),
        ]
        for (row, column) in excluded {
            try puzzle.setState(.excluded, atRow: row, column: column)
        }

        let hint = try XCTUnwrap(
            LogicalHintEngine.nextHint(level: level, puzzle: puzzle).hint
        )

        guard case let .strongLinkCommonElimination(link) = hint.reason else {
            return XCTFail("expected a strong link, got \(hint.reason)")
        }
        XCTAssertEqual(link.constraint, .region(3))
        XCTAssertEqual(
            Set(hint.positions),
            [
                CellPosition(row: 3, column: 6),
                CellPosition(row: 4, column: 3),
                CellPosition(row: 4, column: 4),
            ]
        )
    }

    func testHintsAloneSolveEveryBuiltInLevelWithoutMistakes() throws {
        for level in BuiltInLevels.all {
            var engine = try GameEngine(level: level)
            var applied = 0

            while !engine.state.isSolved {
                guard let hint = LogicalHintEngine.nextHint(
                    level: level,
                    puzzle: engine.state.puzzle
                ).hint else {
                    return XCTFail("\(level.id): ran out of hints after \(applied) steps")
                }
                try engine.applyHint(hint)
                applied += 1
                XCTAssertLessThan(applied, 500, "\(level.id): hint loop did not converge")
            }

            XCTAssertEqual(
                engine.state.mistakeCount,
                0,
                "\(level.id): a hint proposed an illegal placement"
            )
        }
    }

    func testApplyingMultiCellHintIsOneUndoStep() throws {
        let level = BuiltInLevels.meadow
        var startingPuzzle = try level.makePuzzle()
        try startingPuzzle.setState(.cat, atRow: 0, column: 1)
        let hint = try XCTUnwrap(
            LogicalHintEngine.nextHint(level: level, puzzle: startingPuzzle).hint
        )
        XCTAssertGreaterThan(hint.actions.count, 1)
        var engine = try GameEngine(level: level, puzzle: startingPuzzle)

        try engine.applyHint(hint)

        XCTAssertNotEqual(engine.state.puzzle, startingPuzzle)
        XCTAssertTrue(engine.canUndo)
        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle, startingPuzzle)
        XCTAssertFalse(engine.undo())
    }
}
