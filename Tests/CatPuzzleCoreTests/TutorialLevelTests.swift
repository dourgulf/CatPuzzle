import XCTest
@testable import CatPuzzleCore

/// The tutorial's promise is not "this board is solvable" — it is that one
/// board teaches all three rules in an order a beginner can follow, and that
/// every step it points at is a move the player can actually see on the
/// board in front of them. `TutorialScript` derives the steps rather than
/// listing them, so what is pinned down here is the derivation.
final class TutorialLevelTests: XCTestCase {
    private var tutorial: TutorialLevel { TutorialLevels.basics }
    private var level: LevelDefinition { tutorial.level }
    private var steps: [TutorialStep] { tutorial.script.steps }
    private var solution: Set<CellPosition> { Set(tutorial.fixture.solution) }

    // MARK: - The board

    func testTheTutorialIsASingleSixBySixBoardWithNoGivenCats() throws {
        XCTAssertEqual(TutorialLevels.all.count, 1)
        XCTAssertNoThrow(try LevelValidator.validate(level))
        XCTAssertEqual(level.size, 6)
        XCTAssertEqual(level.catCount, 6)
        XCTAssertTrue(
            level.givenPositions.isEmpty,
            "a tutorial that opens with cats already on it asks the player to "
                + "accept a move nobody made"
        )
    }

    /// With no givens to lean on, the board's own Region layout has to carry
    /// the uniqueness — so unlike a board built around pre-placed cats, this
    /// one can be certified by the shipped solver.
    func testTheTutorialBoardHasExactlyOneSolutionAndItIsTheShippedOne() {
        let report = PuzzleSolver.solve(level: level)

        guard case let .unique(found) = report.result else {
            return XCTFail("expected a unique solution, got \(report.result)")
        }
        XCTAssertEqual(Set(found), solution)
    }

    /// A tutorial that needed locked sets or strong links would be teaching
    /// something it never explained. Every move must fall to the plain
    /// one-cell-left reasoning the three rule badges describe.
    func testTheTutorialBoardNeedsNothingBeyondTheThreeRules() {
        let result = LogicalPuzzleSolver.solve(level: level, mode: .logicOnly)
        let statistics = result.report.statistics

        XCTAssertTrue(result.isSolved)
        XCTAssertEqual(statistics.assumptionCount, 0)
        XCTAssertEqual(statistics.lockedPairCount, 0)
        XCTAssertEqual(statistics.lockedTripleCount, 0)
        XCTAssertEqual(statistics.higherOrderLockedSetCount, 0)
        XCTAssertEqual(statistics.commonAttackCount, 0)
        XCTAssertEqual(statistics.strongLinkDeductionCount, 0)
    }

    /// Losing a tutorial would strand a player who has not learned the rules
    /// yet, so the limit sits far beyond any plausible run of refusals.
    func testTheTutorialCannotRealisticallyBeFailed() {
        XCTAssertGreaterThanOrEqual(level.maxMistakes, 1_000)
    }

    // MARK: - The script exists and is legal

    func testTheShippedBoardProducesAScript() {
        XCTAssertFalse(
            tutorial.script.isEmpty,
            "the board no longer fits the curriculum, so the app would play "
                + "it as an ordinary level with no coaching at all"
        )
    }

    /// The single most important property: a step never asks for a move that
    /// is wrong. Cats go where the solution has them, and no cell the
    /// solution needs is ever marked out.
    func testNoStepAsksForAMoveThatContradictsTheSolution() {
        for (index, step) in steps.enumerated() {
            switch step.task {
            case let .placeCat(position):
                XCTAssertTrue(
                    solution.contains(position),
                    "step \(index + 1) places a cat at \(position), which is "
                        + "not in the solution"
                )
            case let .exclude(positions):
                for position in positions {
                    XCTAssertFalse(
                        solution.contains(position),
                        "step \(index + 1) marks out \(position), which the "
                            + "solution needs"
                    )
                }
            }
        }
    }

    /// Following the script has to finish the board. If it stopped short the
    /// player would be dropped mid-lesson onto a board they were never taught
    /// to read.
    func testFollowingEveryStepSolvesTheBoard() throws {
        var engine = try GameEngine(fixture: tutorial.fixture, mode: .challenge)

        for step in steps {
            switch step.task {
            case let .placeCat(position):
                try engine.setState(.cat, atRow: position.row, column: position.column)
            case let .exclude(positions):
                for position in positions {
                    try engine.setState(
                        .excluded,
                        atRow: position.row,
                        column: position.column
                    )
                }
            }
        }

        XCTAssertTrue(engine.state.isSolved)
        XCTAssertEqual(engine.state.mistakeCount, 0)
    }

    /// Every cell is spoken for exactly once: a step that re-marked a cell an
    /// earlier step already handled would be waiting for something the player
    /// cannot do.
    func testEveryCellIsAskedForExactlyOnce() {
        var seen: Set<CellPosition> = []
        for (index, step) in steps.enumerated() {
            for position in step.task.positions {
                XCTAssertTrue(
                    seen.insert(position).inserted,
                    "step \(index + 1) asks for \(position) again"
                )
            }
        }
        XCTAssertEqual(seen.count, level.size * level.size)
    }

    // MARK: - The curriculum

    /// The opening five steps are the lesson itself, in the order a beginner
    /// can follow: a Region small enough to need no deduction, the row and
    /// column that cat settles, all four corners around that same cat, and
    /// then the Region those exclusions leave with one open cell.
    func testTheLessonOpensWithOneRuleAtATimeInTeachingOrder() throws {
        XCTAssertGreaterThan(steps.count, 5)

        guard case let .regionIsASingleCell(regionID) = steps[0].lesson else {
            return XCTFail("step 1 is \(steps[0].lesson), not the one-cell Region")
        }
        XCTAssertEqual(
            level.regionIDs.flatMap { $0 }.filter { $0 == regionID }.count,
            1,
            "step 1 claims a Region is a single cell when it is not"
        )
        guard case let .placeCat(first) = steps[0].task else {
            return XCTFail("step 1 does not place a cat")
        }

        XCTAssertEqual(steps[1].lesson, .rowAlreadyHasItsCat(row: first.row))
        XCTAssertEqual(
            steps[2].lesson,
            .columnAlreadyHasItsCat(column: first.column)
        )

        XCTAssertEqual(steps[3].lesson, .catsNeverTouch(first))

        guard case .regionHasOneCellLeft = steps[4].lesson else {
            return XCTFail("step 5 is \(steps[4].lesson), not a Region running out")
        }
        guard case .placeCat = steps[4].task else {
            return XCTFail("step 5 does not place a cat")
        }
    }

    /// The player makes fourteen visible marks on one evolving board. The
    /// fourth step must add exactly the four diagonal corners left open after
    /// the row and column have already covered the straight neighbours.
    func testFirstCatRowColumnAndFourCornersAreMarkedIndividually() throws {
        guard case let .placeCat(cat) = steps[0].task else {
            return XCTFail("step 1 does not place a cat")
        }
        let row = Set(steps[1].task.positions)
        let column = Set(steps[2].task.positions)
        let corners = Set(steps[3].task.positions)

        XCTAssertEqual(
            row,
            Set((0..<level.size).filter { $0 != cat.column }.map {
                CellPosition(row: cat.row, column: $0)
            })
        )
        XCTAssertEqual(
            column,
            Set((0..<level.size).filter { $0 != cat.row }.map {
                CellPosition(row: $0, column: cat.column)
            })
        )
        XCTAssertEqual(
            corners,
            Set([-1, 1].flatMap { rowOffset in
                [-1, 1].map { columnOffset in
                    CellPosition(
                        row: cat.row + rowOffset,
                        column: cat.column + columnOffset
                    )
                }
            })
        )
        XCTAssertEqual(steps[3].spotlight.count, 9)
    }

    func testTheLessonCoversAllThreeRulesBeforeLeavingThePlayerToIt() {
        let taught = steps
            .prefix(while: { $0.coaching == .guided })
            .compactMap(\.lesson.rule)

        XCTAssertEqual(Set(taught), Set(PuzzleRule.allCases))
    }

    /// Coaching only ever falls away. A step that re-masked the board after
    /// handing it over would read as the tutorial taking it back.
    func testGuidedStepsAllComeBeforeDiscoverySteps() {
        let coaching = steps.map(\.coaching)
        let handover = coaching.firstIndex(of: .discovery) ?? coaching.count

        XCTAssertEqual(handover, 5, "the lesson is not five steps long")
        XCTAssertTrue(coaching.dropFirst(handover).allSatisfy { $0 == .discovery })
    }

    /// A guided step masks everything but its spotlight, so the spotlight has
    /// to be the whole row, column or block the lesson is about — showing only
    /// the answer would teach the player to wait for a highlight, not to look.
    func testGuidedStepsSpotlightTheWholeConstraintTheyAreAbout() {
        for (index, step) in steps.enumerated() where step.coaching == .guided {
            let spotlight = Set(step.spotlight)
            XCTAssertFalse(spotlight.isEmpty, "step \(index + 1) masks the whole board")
            XCTAssertTrue(
                Set(step.task.positions).isSubset(of: spotlight),
                "step \(index + 1) asks for a cell it has masked"
            )
            if case .regionIsASingleCell = step.lesson { continue }
            XCTAssertGreaterThan(
                spotlight.count,
                step.task.positions.count,
                "step \(index + 1) lights up nothing but the answer, which "
                    + "shows the move instead of the reason for it"
            )
        }
    }

    func testDiscoveryStepsMaskNothing() {
        for (index, step) in steps.enumerated() where step.coaching == .discovery {
            XCTAssertTrue(
                step.spotlight.isEmpty,
                "step \(index + 1) is meant to be unguided but masks the board"
            )
        }
    }

    /// After the hand-over the script is the loop the rest of the game is
    /// played in: find the cat some block, row or column has been narrowed
    /// down to, then mark everything that cat rules out.
    func testTheDiscoveryPhaseAlternatesFindingACatAndClearingUpAfterIt() {
        let discovery = steps.filter { $0.coaching == .discovery }

        XCTAssertFalse(discovery.isEmpty)
        for (index, step) in discovery.enumerated() {
            switch step.task {
            case .exclude:
                if index == 0 {
                    guard case .secondCatRulesOut = step.lesson else {
                        return XCTFail("first discovery step does not reinforce the second cat")
                    }
                } else {
                    XCTAssertEqual(step.lesson, .everythingTheCatsRuleOut)
                }
            case .placeCat:
                switch step.lesson {
                case .regionHasOneCellLeft, .rowHasOneCellLeft, .columnHasOneCellLeft:
                    continue
                default:
                    XCTFail("discovery step \(index + 1) places a cat for \(step.lesson)")
                }
            }
        }
    }

    func testSecondCatCleanupOrdersRowThenColumnThenNeighbors() throws {
        guard case let .placeCat(second) = steps[4].task else {
            return XCTFail("step 5 does not place the second cat")
        }
        let cleanup = steps[5]
        XCTAssertEqual(cleanup.lesson, .secondCatRulesOut(second))
        let phases = cleanup.task.positions.map { position in
            if position.row == second.row { return 0 }
            if position.column == second.column { return 1 }
            if abs(position.row - second.row) <= 1,
               abs(position.column - second.column) <= 1 { return 2 }
            return 3
        }

        XCTAssertEqual(phases, phases.sorted())
        XCTAssertTrue(phases.contains(0))
        XCTAssertTrue(phases.contains(1))
        XCTAssertTrue(phases.contains(2))
    }

    // MARK: - A board that cannot teach produces nothing

    /// The fallback matters: a board without a single-cell Region has no
    /// opening move a beginner can see, and the app has to fall back to
    /// playing it uncoached rather than pointing at an invented deduction.
    func testABoardWithoutAOneCellRegionProducesNoScript() {
        let stripes = LevelDefinition(
            id: "stripes",
            size: 6,
            catCount: 6,
            maxMistakes: 3,
            regionIDs: (0..<6).map { row in Array(repeating: row, count: 6) }
        )

        XCTAssertTrue(
            TutorialScript.build(
                for: LevelFixture(level: stripes, solution: [])
            ).isEmpty
        )
    }

    func testABoardWithGivenCatsProducesNoScript() {
        let level = LevelDefinition(
            id: self.level.id,
            size: self.level.size,
            catCount: self.level.catCount,
            maxMistakes: self.level.maxMistakes,
            regionIDs: self.level.regionIDs,
            givenStates: (0..<self.level.size).map { row in
                (0..<self.level.size).map { column in
                    CellPosition(row: row, column: column) == tutorial.fixture.solution[0]
                        ? .cat
                        : .empty
                }
            }
        )

        XCTAssertTrue(
            TutorialScript.build(
                for: LevelFixture(level: level, solution: tutorial.fixture.solution)
            ).isEmpty
        )
    }
}
