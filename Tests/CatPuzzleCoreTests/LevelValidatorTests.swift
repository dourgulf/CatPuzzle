import XCTest
@testable import CatPuzzleCore

final class LevelValidatorTests: XCTestCase {
    func testRejectsInvalidSize() {
        let level = LevelDefinition(id: "invalid", size: 0, regionIDs: [])

        XCTAssertThrowsError(try LevelValidator.validate(level)) { error in
            XCTAssertEqual(error as? LevelValidationError, .invalidSize)
        }
    }

    func testRejectsInvalidDimensions() {
        let level = LevelDefinition(
            id: "invalid",
            size: 2,
            regionIDs: [[0, 0]]
        )

        XCTAssertThrowsError(try LevelValidator.validate(level)) { error in
            XCTAssertEqual(error as? LevelValidationError, .invalidDimensions)
        }
    }

    func testRejectsInvalidRegionCount() {
        let level = LevelDefinition(
            id: "invalid",
            size: 3,
            regionIDs: [
                [0, 0, 0],
                [0, 1, 1],
                [1, 1, 1],
            ]
        )

        XCTAssertThrowsError(try LevelValidator.validate(level)) { error in
            XCTAssertEqual(error as? LevelValidationError, .invalidRegionCount)
        }
    }

    func testRejectsDisconnectedRegion() {
        let level = LevelDefinition(
            id: "disconnected",
            size: 3,
            regionIDs: [
                [0, 0, 1],
                [2, 0, 1],
                [0, 2, 2],
            ]
        )

        XCTAssertThrowsError(try LevelValidator.validate(level)) { error in
            XCTAssertEqual(error as? LevelValidationError, .disconnectedRegion)
        }
    }

    func testAcceptsConnectedIrregularRegionsOfDifferentSizes() {
        let level = LevelDefinition(
            id: "irregular",
            size: 3,
            regionIDs: [
                [0, 0, 1],
                [0, 1, 1],
                [2, 2, 2],
            ]
        )

        XCTAssertNoThrow(try LevelValidator.validate(level))
    }
}
