import XCTest
@testable import CatPuzzleCore

final class LevelValidatorTests: XCTestCase {
    func testRejectsInvalidSize() {
        let level = makeLevel(size: 0, catCount: 0, regionIDs: [])

        assertValidationError(.invalidSize, for: level)
    }

    func testRejectsInvalidRegionDimensions() {
        let level = makeLevel(
            size: 2,
            catCount: 2,
            regionIDs: [[0, 1]]
        )

        assertValidationError(.invalidRegionDimensions, for: level)
    }

    func testRejectsNonPositiveCatCount() {
        let level = makeLevel(
            size: 2,
            catCount: 0,
            regionIDs: [[0, 0], [1, 1]]
        )

        assertValidationError(.invalidCatCount, for: level)
    }

    func testRejectsNonPositiveMaxMistakes() {
        let level = makeLevel(
            size: 2,
            catCount: 2,
            maxMistakes: 0,
            regionIDs: [[0, 0], [1, 1]]
        )

        assertValidationError(.invalidMaxMistakes, for: level)
    }

    func testRejectsCatCountThatDoesNotMatchSize() {
        let level = makeLevel(
            size: 3,
            catCount: 2,
            regionIDs: [
                [0, 0, 0],
                [0, 1, 1],
                [1, 1, 1],
            ]
        )

        assertValidationError(.catCountMustEqualSize, for: level)
    }

    func testRejectsRegionCountThatDoesNotMatchCatCount() {
        let level = makeLevel(
            size: 3,
            catCount: 3,
            regionIDs: [
                [0, 0, 0],
                [0, 1, 1],
                [1, 1, 1],
            ]
        )

        assertValidationError(.invalidRegionCount, for: level)
    }

    func testAcceptsDisconnectedRegions() {
        let level = makeLevel(
            size: 3,
            catCount: 3,
            regionIDs: [
                [0, 1, 0],
                [2, 1, 2],
                [0, 1, 2],
            ]
        )

        XCTAssertNoThrow(try LevelValidator.validate(level))
    }

    private func makeLevel(
        size: Int,
        catCount: Int,
        maxMistakes: Int = 5,
        regionIDs: [[Int]]
    ) -> LevelDefinition {
        LevelDefinition(
            id: "test",
            size: size,
            catCount: catCount,
            maxMistakes: maxMistakes,
            regionIDs: regionIDs
        )
    }

    private func assertValidationError(
        _ expectedError: LevelValidationError,
        for level: LevelDefinition,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try LevelValidator.validate(level),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? LevelValidationError,
                expectedError,
                file: file,
                line: line
            )
        }
    }
}
