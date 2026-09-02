import XCTest
@testable import CatPuzzleCore

final class GameEngineTests: XCTestCase {
    func testEngineStartsWithEmptyGameState() throws {
        let engine = try GameEngine(level: BuiltInLevels.meadow)

        XCTAssertEqual(engine.state.level, BuiltInLevels.meadow)
        XCTAssertTrue(engine.state.puzzle.states.allSatisfy { $0 == .empty })
        XCTAssertEqual(engine.state.mistakeCount, 0)
        XCTAssertEqual(engine.state.remainingMistakes, 5)
        XCTAssertFalse(engine.state.isSolved)
        XCTAssertFalse(engine.state.isFailed)
        XCTAssertFalse(engine.canUndo)
    }

    func testEngineRejectsSemanticallyInvalidLevel() {
        let level = LevelDefinition(
            id: "invalid",
            size: 2,
            catCount: 2,
            maxMistakes: 0,
            regionIDs: [[0, 0], [1, 1]]
        )

        XCTAssertThrowsError(try GameEngine(level: level)) { error in
            XCTAssertEqual(
                error as? LevelValidationError,
                .invalidMaxMistakes
            )
        }
    }

    func testSetStateCanExcludeCellDirectly() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)

        try engine.setState(.excluded, atRow: 2, column: 3)

        XCTAssertEqual(engine.state.puzzle.state(atRow: 2, column: 3), .excluded)
        XCTAssertTrue(engine.canUndo)
    }

    func testSetStateCanPlaceLegalCatDirectly() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)

        try engine.setState(.cat, atRow: 2, column: 3)

        XCTAssertEqual(engine.state.puzzle.state(atRow: 2, column: 3), .cat)
        XCTAssertTrue(engine.canUndo)
    }

    func testExplorationAcceptsLegalCatOutsideUniqueSolutionAndAllowsUndo() throws {
        let fixture = BuiltInLevels.meadowFixture
        var engine = try GameEngine(
            fixture: fixture,
            mode: .exploration
        )

        try engine.setState(.cat, atRow: 0, column: 0)

        XCTAssertEqual(
            engine.state.puzzle.state(atRow: 0, column: 0),
            .cat
        )
        XCTAssertEqual(engine.state.mistakeCount, 0)
        XCTAssertTrue(engine.canUndo)
        XCTAssertTrue(engine.undo())
        XCTAssertEqual(
            engine.state.puzzle.state(atRow: 0, column: 0),
            .empty
        )
    }

    func testChallengeRejectsCatOutsideUniqueSolutionAndCountsMistake() throws {
        let fixture = BuiltInLevels.meadowFixture
        var engine = try GameEngine(
            fixture: fixture,
            mode: .challenge
        )

        XCTAssertThrowsError(
            try engine.setState(.cat, atRow: 0, column: 0)
        ) { error in
            XCTAssertEqual(
                error as? GameEngineError,
                .incorrectCatPlacement
            )
        }

        XCTAssertEqual(
            engine.state.puzzle.state(atRow: 0, column: 0),
            .empty
        )
        XCTAssertEqual(engine.state.mistakeCount, 1)
        XCTAssertFalse(engine.canUndo)
        XCTAssertFalse(engine.undo())
    }

    func testChallengeAcceptsSolutionCatButNeverCreatesUndoHistory() throws {
        let fixture = BuiltInLevels.meadowFixture
        let position = fixture.solution[0]
        var engine = try GameEngine(
            fixture: fixture,
            mode: .challenge
        )

        try engine.setState(
            .cat,
            atRow: position.row,
            column: position.column
        )
        try engine.setState(.excluded, atRow: 2, column: 2)

        XCTAssertEqual(
            engine.state.puzzle.state(
                atRow: position.row,
                column: position.column
            ),
            .cat
        )
        XCTAssertFalse(engine.canUndo)
        XCTAssertFalse(engine.undo())
    }

    func testChangingModeClearsHistoryAndAppliesNewPlacementPolicy() throws {
        let fixture = BuiltInLevels.meadowFixture
        var engine = try GameEngine(
            fixture: fixture,
            mode: .exploration
        )
        try engine.setState(.excluded, atRow: 2, column: 2)
        XCTAssertTrue(engine.canUndo)

        engine.setMode(.challenge)

        XCTAssertEqual(engine.state.mode, .challenge)
        XCTAssertFalse(engine.canUndo)
        XCTAssertThrowsError(
            try engine.setState(.cat, atRow: 0, column: 0)
        ) { error in
            XCTAssertEqual(
                error as? GameEngineError,
                .incorrectCatPlacement
            )
        }
        XCTAssertEqual(engine.state.mistakeCount, 1)

        engine.setMode(.exploration)
        XCTAssertFalse(engine.canUndo)
        try engine.setState(.cat, atRow: 0, column: 0)
        XCTAssertTrue(engine.canUndo)
    }

    func testSettingSameStateIsNoOpWithoutUndoHistory() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        try engine.setState(.excluded, atRow: 2, column: 3)
        let puzzleBeforeNoOp = engine.state.puzzle

        try engine.setState(.excluded, atRow: 2, column: 3)

        XCTAssertEqual(engine.state.puzzle, puzzleBeforeNoOp)
        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle.state(atRow: 2, column: 3), .empty)
        XCTAssertFalse(engine.canUndo)
    }

    func testToggleCyclesThroughAllCellStates() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)

        XCTAssertEqual(
            try engine.toggleCell(atRow: 0, column: 0),
            .excluded
        )
        XCTAssertEqual(try engine.toggleCell(atRow: 0, column: 0), .cat)
        XCTAssertEqual(try engine.toggleCell(atRow: 0, column: 0), .empty)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 0), .empty)
        XCTAssertTrue(engine.canUndo)
    }

    func testIllegalCatPlacementIsRejectedWithoutChangingState() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        try engine.setState(.cat, atRow: 0, column: 0)
        try engine.setState(.excluded, atRow: 0, column: 4)
        let puzzleBeforeFailure = engine.state.puzzle

        XCTAssertThrowsError(
            try engine.setState(.cat, atRow: 0, column: 4)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .illegalCatPlacement)
        }
        XCTAssertEqual(engine.state.puzzle, puzzleBeforeFailure)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 0), .cat)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 4), .excluded)
        XCTAssertEqual(engine.state.mistakeCount, 1)
        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 4), .empty)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 0), .cat)
        XCTAssertEqual(engine.state.mistakeCount, 1)
    }

    func testUndoRestoresSuccessfulMovesInReverseOrder() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        try engine.setState(.excluded, atRow: 0, column: 0)
        try engine.setState(.excluded, atRow: 1, column: 1)

        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle.state(atRow: 1, column: 1), .empty)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 0), .excluded)
        XCTAssertTrue(engine.canUndo)

        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 0), .empty)
        XCTAssertFalse(engine.canUndo)
        XCTAssertFalse(engine.undo())
    }

    func testRestartRestoresInitialStateAndClearsHistory() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        try engine.setState(.cat, atRow: 0, column: 0)
        try engine.setState(.excluded, atRow: 2, column: 2)

        engine.restart()

        XCTAssertTrue(engine.state.puzzle.states.allSatisfy { $0 == .empty })
        XCTAssertEqual(engine.state.mistakeCount, 0)
        XCTAssertFalse(engine.state.isSolved)
        XCTAssertFalse(engine.canUndo)
        XCTAssertFalse(engine.undo())
    }

    func testCompletingValidMovesUpdatesSolvedState() throws {
        let fixture = BuiltInLevels.meadowFixture
        var engine = try GameEngine(level: fixture.level)

        for position in fixture.solution {
            try engine.setState(
                .cat,
                atRow: position.row,
                column: position.column
            )
        }

        XCTAssertTrue(engine.state.isSolved)
    }

    func testInvalidCoordinateDoesNotCreateUndoHistory() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        try engine.setState(.excluded, atRow: 1, column: 1)
        let puzzleBeforeFailure = engine.state.puzzle

        XCTAssertThrowsError(
            try engine.setState(.excluded, atRow: -1, column: 0)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .invalidCell)
        }
        XCTAssertEqual(engine.state.puzzle, puzzleBeforeFailure)
        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.puzzle.state(atRow: 1, column: 1), .empty)
        XCTAssertFalse(engine.canUndo)
    }

    func testEngineRestoresValidPuzzleWithoutUndoHistory() throws {
        let level = BuiltInLevels.meadow
        var savedPuzzle = try level.makePuzzle()
        try savedPuzzle.setState(.excluded, atRow: 0, column: 0)
        try savedPuzzle.setState(.cat, atRow: 0, column: 1)

        let engine = try GameEngine(
            level: level,
            puzzle: savedPuzzle,
            mistakeCount: 2
        )

        XCTAssertEqual(engine.state.puzzle, savedPuzzle)
        XCTAssertEqual(engine.state.mistakeCount, 2)
        XCTAssertEqual(engine.state.remainingMistakes, 3)
        XCTAssertFalse(engine.canUndo)
    }

    func testIllegalPlacementsReachFailureWithoutChangingPuzzle() throws {
        var engine = try GameEngine(level: BuiltInLevels.meadow)
        try engine.setState(.cat, atRow: 0, column: 0)
        let puzzleBeforeMistakes = engine.state.puzzle

        for expectedCount in 1...BuiltInLevels.meadow.maxMistakes {
            XCTAssertThrowsError(
                try engine.setState(.cat, atRow: 0, column: 4)
            ) { error in
                XCTAssertEqual(
                    error as? GameEngineError,
                    .illegalCatPlacement
                )
            }
            XCTAssertEqual(engine.state.mistakeCount, expectedCount)
            XCTAssertEqual(engine.state.puzzle, puzzleBeforeMistakes)
        }

        XCTAssertTrue(engine.state.isFailed)
        XCTAssertEqual(engine.state.remainingMistakes, 0)
    }

    func testFailedGameRejectsOperationsUntilRestart() throws {
        let level = LevelDefinition(
            id: "one-mistake",
            size: 4,
            catCount: 4,
            maxMistakes: 1,
            regionIDs: [
                [0, 0, 0, 1],
                [0, 1, 1, 1],
                [2, 2, 2, 3],
                [2, 3, 3, 3],
            ]
        )
        var engine = try GameEngine(level: level)
        try engine.setState(.cat, atRow: 0, column: 0)
        XCTAssertThrowsError(
            try engine.setState(.cat, atRow: 0, column: 3)
        )

        XCTAssertThrowsError(
            try engine.setState(.excluded, atRow: 2, column: 2)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .gameAlreadyFailed)
        }
        XCTAssertFalse(engine.undo())

        engine.restart()

        XCTAssertFalse(engine.state.isFailed)
        XCTAssertEqual(engine.state.mistakeCount, 0)
        XCTAssertTrue(engine.state.puzzle.states.allSatisfy { $0 == .empty })
    }

    func testRestoredMistakeCountCanRestoreFailedGame() throws {
        let level = BuiltInLevels.meadow
        let puzzle = try level.makePuzzle()

        let engine = try GameEngine(
            level: level,
            puzzle: puzzle,
            mistakeCount: level.maxMistakes
        )

        XCTAssertTrue(engine.state.isFailed)
        XCTAssertFalse(engine.canUndo)
    }

    func testNegativeRestoredMistakeCountIsRejected() throws {
        let level = BuiltInLevels.meadow
        let puzzle = try level.makePuzzle()

        XCTAssertThrowsError(
            try GameEngine(level: level, puzzle: puzzle, mistakeCount: -1)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .invalidMistakeCount)
        }
    }

    func testRestartAfterRestoreUsesFreshEmptyLevel() throws {
        let level = BuiltInLevels.meadow
        var savedPuzzle = try level.makePuzzle()
        try savedPuzzle.setState(.excluded, atRow: 2, column: 2)
        var engine = try GameEngine(level: level, puzzle: savedPuzzle)

        engine.restart()

        XCTAssertTrue(engine.state.puzzle.states.allSatisfy { $0 == .empty })
        XCTAssertFalse(engine.canUndo)
    }

    func testEngineRejectsRestoredPuzzleFromDifferentLevel() throws {
        let riverPuzzle = try BuiltInLevels.river.makePuzzle()

        XCTAssertThrowsError(
            try GameEngine(level: BuiltInLevels.meadow, puzzle: riverPuzzle)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .puzzleDoesNotMatchLevel)
        }
    }

    func testEngineRejectsRestoredPuzzleWithRuleConflict() throws {
        let level = BuiltInLevels.meadow
        var savedPuzzle = try level.makePuzzle()
        try savedPuzzle.setState(.cat, atRow: 0, column: 0)
        try savedPuzzle.setState(.cat, atRow: 0, column: 4)

        XCTAssertThrowsError(
            try GameEngine(level: level, puzzle: savedPuzzle)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .invalidRestoredPuzzle)
        }
    }

    func testGivenCatIsPrefilledWhenEngineStarts() throws {
        let engine = try GameEngine(level: makeGivensLevel(givenCatAt: CellPosition(row: 0, column: 1)))

        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 1), .cat)
    }

    func testLockedCellRejectsSetStateWithoutMistakeOrUndoHistory() throws {
        var engine = try GameEngine(level: makeGivensLevel(givenCatAt: CellPosition(row: 0, column: 1)))

        XCTAssertThrowsError(
            try engine.setState(.empty, atRow: 0, column: 1)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .cellIsLocked)
        }
        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 1), .cat)
        XCTAssertEqual(engine.state.mistakeCount, 0)
        XCTAssertFalse(engine.canUndo)
    }

    func testToggleCellOnLockedCellThrows() throws {
        var engine = try GameEngine(level: makeGivensLevel(givenCatAt: CellPosition(row: 0, column: 1)))

        XCTAssertThrowsError(
            try engine.toggleCell(atRow: 0, column: 1)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .cellIsLocked)
        }
    }

    func testRestartRestoresGivenCells() throws {
        var engine = try GameEngine(level: makeGivensLevel(givenCatAt: CellPosition(row: 0, column: 1)))
        try engine.setState(.excluded, atRow: 3, column: 3)

        engine.restart()

        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 1), .cat)
        XCTAssertEqual(engine.state.puzzle.state(atRow: 3, column: 3), .empty)
    }

    func testFixtureAcceptsGivenCatThatMatchesSolution() throws {
        let fixture = LevelFixture(
            level: makeGivensLevel(givenCatAt: CellPosition(row: 0, column: 1)),
            solution: givensLevelSolution
        )

        let engine = try GameEngine(fixture: fixture, mode: .challenge)

        XCTAssertEqual(engine.state.puzzle.state(atRow: 0, column: 1), .cat)
    }

    func testFixtureRejectsGivenCatThatIsNotInSolution() {
        let fixture = LevelFixture(
            level: makeGivensLevel(givenCatAt: CellPosition(row: 0, column: 0)),
            solution: givensLevelSolution
        )

        XCTAssertThrowsError(
            try GameEngine(fixture: fixture, mode: .challenge)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .invalidSolution)
        }
    }

    func testFixtureRejectsGivenExcludedOnSolutionCell() {
        let fixture = LevelFixture(
            level: makeGivensLevel(givenExcludedAt: CellPosition(row: 0, column: 1)),
            solution: givensLevelSolution
        )

        XCTAssertThrowsError(
            try GameEngine(fixture: fixture, mode: .challenge)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .invalidGivenCells)
        }
    }

    func testEngineRejectsRestoredPuzzleThatContradictsGivens() throws {
        let level = makeGivensLevel(givenCatAt: CellPosition(row: 0, column: 1))
        var savedPuzzle = try level.makePuzzle()
        try savedPuzzle.setState(.empty, atRow: 0, column: 1)

        XCTAssertThrowsError(
            try GameEngine(level: level, puzzle: savedPuzzle)
        ) { error in
            XCTAssertEqual(error as? GameEngineError, .invalidRestoredPuzzle)
        }
    }

    private let givensLevelSolution = [
        CellPosition(row: 0, column: 1),
        CellPosition(row: 1, column: 3),
        CellPosition(row: 2, column: 0),
        CellPosition(row: 3, column: 2),
    ]

    private func makeGivensLevel(
        givenCatAt catPosition: CellPosition? = nil,
        givenExcludedAt excludedPosition: CellPosition? = nil
    ) -> LevelDefinition {
        var givenStates = Array(
            repeating: Array(repeating: CellState.empty, count: 4),
            count: 4
        )
        if let catPosition {
            givenStates[catPosition.row][catPosition.column] = .cat
        }
        if let excludedPosition {
            givenStates[excludedPosition.row][excludedPosition.column] = .excluded
        }
        return LevelDefinition(
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
            givenStates: givenStates
        )
    }
}
