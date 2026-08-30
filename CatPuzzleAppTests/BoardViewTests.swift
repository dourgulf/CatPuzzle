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
        XCTAssertEqual(
            regionIDs.map(CatPuzzleTheme.regionName),
            (1...10).map { "Region \($0)" }
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

    func testDragModeIsDeterminedByStartingCellState() {
        XCTAssertEqual(BoardDragMode(startingFrom: .empty), .exclude)
        XCTAssertEqual(BoardDragMode(startingFrom: .excluded), .clear)
        XCTAssertEqual(BoardDragMode(startingFrom: .cat), .ignore)
    }

    func testCellMarkersScaleDownWithSmallerGeneratedBoards() {
        let main = CellMarkerMetrics(cellSide: 55)
        let labEightByEight = CellMarkerMetrics(cellSide: 41)
        let labTenByTen = CellMarkerMetrics(cellSide: 32)

        XCTAssertEqual(main.excludedFontSize, 39.6, accuracy: 0.001)
        XCTAssertEqual(labEightByEight.excludedFontSize, 29.52, accuracy: 0.001)
        XCTAssertEqual(labTenByTen.excludedFontSize, 23.04, accuracy: 0.001)
        XCTAssertLessThan(labEightByEight.excludedFontSize, 41)
        XCTAssertLessThan(labTenByTen.excludedFontSize, 32)
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
