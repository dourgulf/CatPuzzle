import XCTest
@testable import CatPuzzleCore

final class ConstructivePuzzleGeneratorTests: XCTestCase {
    func testSolutionPermutationIsDeterministicAndLegalAtSupportedSizes() {
        for size in 8...10 {
            var firstRNG = SeededRandomNumberGenerator(seed: UInt64(size))
            var secondRNG = SeededRandomNumberGenerator(seed: UInt64(size))
            let first = SolutionPermutationGenerator.generate(
                size: size,
                rng: &firstRNG,
                nodeBudget: 20_000
            )
            let second = SolutionPermutationGenerator.generate(
                size: size,
                rng: &secondRNG,
                nodeBudget: 20_000
            )

            XCTAssertEqual(first.solution, second.solution)
            let solution = try! XCTUnwrap(first.solution)
            XCTAssertEqual(Set(solution.map(\.row)).count, size)
            XCTAssertEqual(Set(solution.map(\.column)).count, size)
            for pair in zip(solution, solution.dropFirst()) {
                XCTAssertGreaterThan(abs(pair.0.column - pair.1.column), 1)
            }
        }
    }

    func testPartitionOwnsConnectedRegionsAndKeepsPlantedCatsSeparate() throws {
        let (partition, solution) = try easyPartition(seed: 1)

        XCTAssertTrue(partition.allRegionsAreConnected)
        XCTAssertEqual(Set(partition.regionIDs.flatMap { $0 }).count, 8)
        for (regionID, cat) in solution.enumerated() {
            XCTAssertEqual(partition.regionIDs[cat.row][cat.column], regionID)
        }
    }

    func testBoundaryMovePreservesConnectivityAndPlantedCats() throws {
        let (partition, solution) = try easyPartition(seed: 1)
        let moved = try XCTUnwrap(partition.boundaryMoves().lazy.compactMap {
            partition.applying($0)
        }.first)

        XCTAssertTrue(moved.allRegionsAreConnected)
        for (regionID, cat) in solution.enumerated() {
            XCTAssertEqual(moved.regionIDs[cat.row][cat.column], regionID)
        }
    }

    func testDiagonalContactCountsAsConnectedRegionGeometry() {
        let partition = RegionPartition(
            size: 3,
            solutionByRegionID: [
                0: CellPosition(row: 0, column: 0),
                1: CellPosition(row: 0, column: 1),
            ],
            regionIDs: [
                [0, 1, 1],
                [1, 0, 1],
                [1, 1, 1],
            ],
            restrictedRowsByRegionID: [:]
        )

        XCTAssertTrue(partition.isConnected(regionID: 0))
        XCTAssertTrue(partition.isConnected(regionID: 1))
    }

    func testUnsupportedRequestFailsBeforeDoingWork() {
        let result = ConstructivePuzzleGenerator.generate(request: .init(
            size: 7,
            seed: 1,
            difficulty: .easy,
            profile: .dominantBackground
        ))

        guard case let .failure(failure) = result else {
            return XCTFail("Expected an invalid-request failure")
        }
        XCTAssertEqual(failure.stage, .invalidRequest)
        XCTAssertEqual(failure.work.logicalEvaluations, 0)
    }

    func testZeroBudgetReturnsStructuredFailure() {
        let result = ConstructivePuzzleGenerator.generate(request: .init(
            size: 8,
            seed: 1,
            difficulty: .easy,
            profile: .dominantBackground,
            budget: GenerationBudget(
                solutionRestarts: 0,
                partitionRestarts: 0,
                boundaryMutations: 0,
                logicalEvaluations: 0,
                exactSolverNodes: 0,
                beamWidth: 1
            )
        ))

        guard case let .failure(failure) = result else {
            return XCTFail("Expected a bounded failure")
        }
        XCTAssertEqual(failure.stage, .logicalSearch)
        XCTAssertEqual(failure.seed, 1)
    }

    func testPartitionRestartBudgetIsGlobalRatherThanMultipliedBySolutionRestarts() {
        let budget = GenerationBudget(
            solutionRestarts: 3,
            partitionRestarts: 4,
            boundaryMutations: 0,
            logicalEvaluations: 0,
            exactSolverNodes: 0,
            beamWidth: 1
        )
        let result = ConstructivePuzzleGenerator.generate(request: .init(
            size: 8,
            seed: 1,
            difficulty: .medium,
            profile: .balancedMosaic,
            budget: budget
        ))

        guard case let .failure(failure) = result else {
            return XCTFail("Expected the deliberately exhausted budget to fail")
        }
        XCTAssertLessThanOrEqual(
            failure.work.partitionRestarts,
            budget.partitionRestarts
        )
        XCTAssertLessThanOrEqual(
            failure.work.logicalEvaluations,
            budget.logicalEvaluations
        )
    }

    func testCancellationStopsBeforeGeneratorConsumesWork() {
        let result = ConstructivePuzzleGenerator.generate(
            request: .init(
                size: 8,
                seed: 1,
                difficulty: .medium,
                profile: .balancedMosaic
            ),
            isCancelled: { true }
        )

        guard case let .failure(failure) = result else {
            return XCTFail("Expected cancellation to stop generation")
        }
        XCTAssertEqual(failure.stage, .cancelled)
        XCTAssertEqual(
            failure.work,
            GenerationWork(
                solutionRestarts: 0,
                partitionRestarts: 0,
                boundaryMutations: 0,
                logicalEvaluations: 0
            )
        )
    }

    func testFixedSeedEasyEightByEightIsConnectedLogicalAndUnique() throws {
        let request = ConstructiveGenerationRequest(
            size: 8,
            seed: 1,
            difficulty: .easy,
            profile: .dominantBackground
        )

        let first = ConstructivePuzzleGenerator.generate(request: request)
        let second = ConstructivePuzzleGenerator.generate(request: request)
        guard case let .success(generated) = first else {
            return XCTFail("Expected fixed-seed generation to succeed: \(first)")
        }

        XCTAssertEqual(first, second)
        XCTAssertEqual(generated.level.size, 8)
        XCTAssertEqual(generated.geometry.connectedRegionCount, 8)
        XCTAssertLessThanOrEqual(generated.geometry.largestRegionFraction, 0.45)
        XCTAssertTrue(generated.blueprintCoverage.isSatisfied)
        XCTAssertTrue(generated.logicalReport.statistics.assumptionCount == 0)
        XCTAssertEqual(generated.exactSolverReport.result, .unique(generated.solution))
    }

    func testFixedSeedMediumNineByNineOpensWithLockedSetAndIsUnique() {
        let request = ConstructiveGenerationRequest(
            size: 9,
            seed: 2,
            difficulty: .medium,
            profile: .dominantBackground
        )

        let result = ConstructivePuzzleGenerator.generate(request: request)
        guard case let .success(generated) = result else {
            return XCTFail("Expected fixed-seed generation to succeed: \(result)")
        }

        XCTAssertEqual(generated.level.size, 9)
        XCTAssertEqual(generated.geometry.connectedRegionCount, 9)
        XCTAssertTrue(generated.blueprintCoverage.isSatisfied)
        XCTAssertEqual(generated.logicalReport.events.first?.technique, .lockedSet(size: 2))
        XCTAssertEqual(generated.exactSolverReport.result, .unique(generated.solution))
    }

    func testFixedSeedBalancedMediumEightByEightHonorsBoundedWork() {
        let request = ConstructiveGenerationRequest(
            size: 8,
            seed: 1,
            difficulty: .medium,
            profile: .balancedMosaic
        )

        let result = ConstructivePuzzleGenerator.generate(request: request)
        switch result {
        case let .success(generated):
            XCTAssertEqual(generated.geometry.connectedRegionCount, 8)
            XCTAssertLessThanOrEqual(generated.geometry.largestRegionFraction, 0.28)
            XCTAssertTrue(generated.geometry.regionsWithHoles.isEmpty)
            XCTAssertTrue(generated.blueprintCoverage.isSatisfied)
            XCTAssertEqual(generated.exactSolverReport.result, .unique(generated.solution))
        case let .failure(failure):
            XCTAssertLessThanOrEqual(failure.work.partitionRestarts, 800)
            XCTAssertLessThanOrEqual(failure.work.boundaryMutations, 64)
            XCTAssertLessThanOrEqual(failure.work.logicalEvaluations, 64)
        }
    }

    func testFixedSeedHardTenByTenUsesLaterHardTechniqueAndIsUnique() {
        let request = ConstructiveGenerationRequest(
            size: 10,
            seed: 1,
            difficulty: .hard,
            profile: .dominantBackground
        )

        let result = ConstructivePuzzleGenerator.generate(request: request)
        guard case let .success(generated) = result else {
            return XCTFail("Expected fixed-seed generation to succeed: \(result)")
        }

        XCTAssertEqual(generated.level.size, 10)
        XCTAssertEqual(generated.geometry.connectedRegionCount, 10)
        XCTAssertTrue(generated.blueprintCoverage.isSatisfied)
        XCTAssertEqual(generated.logicalReport.events.first?.technique, .lockedSet(size: 2))
        XCTAssertTrue(generated.logicalReport.events.contains {
            $0.technique == .commonAttack || $0.technique == .strongLink
        })
        XCTAssertEqual(generated.exactSolverReport.result, .unique(generated.solution))
    }

    private func easyPartition(
        seed: UInt64
    ) throws -> (partition: RegionPartition, solution: [CellPosition]) {
        let result = ConstructivePuzzleGenerator.generate(request: .init(
            size: 8,
            seed: seed,
            difficulty: .easy,
            profile: .dominantBackground
        ))
        guard case let .success(generated) = result else {
            throw NSError(domain: "ConstructivePuzzleGeneratorTests", code: 1)
        }
        let seeds = Dictionary(uniqueKeysWithValues: generated.solution.enumerated().map {
            ($0.offset, $0.element)
        })
        return (
            RegionPartition(
                size: generated.level.size,
                solutionByRegionID: seeds,
                regionIDs: generated.level.regionIDs,
                restrictedRowsByRegionID: [:]
            ),
            generated.solution
        )
    }

}
