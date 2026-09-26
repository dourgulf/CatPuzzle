import XCTest
@testable import CatPuzzle
import CatPuzzleCore

final class BoardViewTests: XCTestCase {
    func testRegionPresentationIsUniqueForLargestGeneratedBoard() {
        let regionIDs = Array(0..<10)

        XCTAssertEqual(
            Set(regionIDs.map(CatPuzzleTheme.regionSymbol)).count,
            regionIDs.count
        )
        // Regions are named by what the player can see, not by their ID.
        XCTAssertEqual(
            Set(regionIDs.map { CatPuzzleTheme.regionName(for: $0, includingShape: true) }).count,
            regionIDs.count
        )
        // Color alone must still tell all ten Regions apart when icons are off.
        XCTAssertEqual(
            Set(regionIDs.map { CatPuzzleTheme.regionDescription(for: $0, includingShape: false) }).count,
            regionIDs.count
        )
        XCTAssertEqual(
            CatPuzzleTheme.regionName(for: 0, includingShape: true),
            "pink circle Region"
        )
        XCTAssertFalse(
            regionIDs
                .map { CatPuzzleTheme.regionName(for: $0, includingShape: true) }
                .contains { $0.contains("Region 1") }
        )
    }

    /// Region icons off: the shape is not on screen, so copy must not name it.
    func testRegionIsNamedByColorAloneWhenIconsAreHidden() {
        XCTAssertEqual(
            CatPuzzleTheme.regionDescription(for: 3, includingShape: false),
            "blue"
        )
        XCTAssertEqual(
            CatPuzzleTheme.regionDescription(for: 3, includingShape: true),
            "blue diamond"
        )
        XCTAssertEqual(
            HintDescription.text(
                for: .starvedConstraint(.region(0)),
                showsRegionIcons: false
            ),
            "The pink block has no cell left for a cat, so one of your ✕ marks must be wrong. Undo to fix it."
        )
        XCTAssertTrue(
            HintDescription.text(
                for: .starvedConstraint(.region(0)),
                showsRegionIcons: true
            ).hasPrefix("The pink circle block")
        )
    }

    func testBoardLayoutMapsCellCentersAndRejectsGaps() {
        let layout = BoardLayout(side: 360, size: 6, padding: 8, spacing: 4)

        XCTAssertEqual(
            layout.position(at: CGPoint(x: 35, y: 35)),
            CellPosition(row: 0, column: 0)
        )
        XCTAssertNil(layout.position(at: CGPoint(x: 64, y: 35)))
        XCTAssertEqual(
            layout.position(at: CGPoint(x: 93, y: 35)),
            CellPosition(row: 0, column: 1)
        )
    }

    func testBoardLayoutSamplesEveryCellAlongFastDrag() {
        let layout = BoardLayout(side: 360, size: 6, padding: 8, spacing: 4)

        XCTAssertEqual(
            layout.positions(
                from: CGPoint(x: 35, y: 35),
                to: CGPoint(x: 325, y: 35)
            ),
            (0..<6).map { CellPosition(row: 0, column: $0) }
        )
    }

    func testAdaptiveSpacingKeepsCellsAndHitTargetsAlignedAcrossBoardSizes() {
        for width in [320.0, 393.0, 430.0] {
            for size in [6, 7, 8, 9, 10, 12] {
                for scale in [2.0, 3.0] {
                    let layout = BoardAppearance.compact.layout(side: width - 8, size: size, displayScale: scale)
                    XCTAssertEqual(layout.spacing, layout.cellSide * 0.08, accuracy: 0.6 / scale)
                    XCTAssertEqual(layout.spacing * scale, (layout.spacing * scale).rounded(), accuracy: 0.001)
                    XCTAssertEqual(
                        CGFloat(size) * layout.cellSide + CGFloat(size - 1) * layout.spacing,
                        layout.contentSide, accuracy: 0.001
                    )
                    let first = layout.padding + layout.cellSide / 2
                    let last = layout.padding + layout.contentSide - layout.cellSide / 2
                    XCTAssertEqual(layout.position(at: CGPoint(x: last, y: last)), CellPosition(row: size - 1, column: size - 1))
                    XCTAssertNil(layout.position(at: CGPoint(x: layout.padding + layout.cellSide + layout.spacing / 2, y: first)))
                    XCTAssertEqual(
                        layout.positions(from: CGPoint(x: first, y: first), to: CGPoint(x: last, y: first)),
                        (0..<size).map { CellPosition(row: 0, column: $0) }
                    )
                }
            }
        }
    }

    func testDragModeIsDeterminedByStartingCellState() {
        XCTAssertEqual(BoardDragMode(startingFrom: .empty), .exclude)
        XCTAssertEqual(BoardDragMode(startingFrom: .excluded), .clear)
        XCTAssertEqual(BoardDragMode(startingFrom: .cat), .ignore)
    }

    func testCellMarkersScaleDownWithSmallerGeneratedBoards() {
        let main = CellMarkerMetrics(cellSide: 55)
        let labEightByEight = CellMarkerMetrics(cellSide: 41)
        let labTenByTen = CellMarkerMetrics(cellSide: 32)

        XCTAssertEqual(main.excludedFontSize, 63.25, accuracy: 0.001)
        XCTAssertEqual(labEightByEight.excludedFontSize, 47.15, accuracy: 0.001)
        XCTAssertEqual(labTenByTen.excludedFontSize, 36.8, accuracy: 0.001)
        XCTAssertLessThan(labEightByEight.catFontSize, main.catFontSize)
        XCTAssertLessThan(labEightByEight.catPadding, main.catPadding)
    }

    @MainActor
    func testGeneratedCandidateCanLaunchInChallengeMode() throws {
        let generated = try generatedEasyPuzzle()
        let viewModel = try PlaytestGameFactory.makeViewModel(
            puzzle: generated,
            mode: .challenge
        )

        XCTAssertEqual(viewModel.mode, .challenge)
        XCTAssertFalse(viewModel.allowsUndo)

        let wrongPosition = try XCTUnwrap((0..<generated.level.size).lazy
            .flatMap { row in
                (0..<generated.level.size).map {
                    CellPosition(row: row, column: $0)
                }
            }
            .first { !generated.solution.contains($0) })
        viewModel.toggleCat(
            atRow: wrongPosition.row,
            column: wrongPosition.column
        )

        XCTAssertEqual(viewModel.mistakeCount, 1)
        XCTAssertEqual(
            viewModel.feedbackMessage,
            "That cat is not in the solution."
        )
    }

    @MainActor
    func testGeneratedCandidateCanLaunchInExplorationMode() throws {
        let viewModel = try PlaytestGameFactory.makeViewModel(
            puzzle: generatedEasyPuzzle(),
            mode: .exploration
        )

        XCTAssertEqual(viewModel.mode, .exploration)
        XCTAssertTrue(viewModel.allowsUndo)
    }

    private func generatedEasyPuzzle() throws -> ConstructiveGeneratedPuzzle {
        let result = ConstructivePuzzleGenerator.generate(request: .init(
            size: 8,
            seed: 1,
            difficulty: .easy,
            profile: .dominantBackground
        ))
        guard case let .success(puzzle) = result else {
            throw NSError(domain: "BoardViewTests", code: 1)
        }
        return puzzle
    }
}
