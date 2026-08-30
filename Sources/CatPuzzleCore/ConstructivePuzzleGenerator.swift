public enum ConstructivePuzzleGenerator {
    public static func generate(
        request: ConstructiveGenerationRequest,
        isCancelled: () -> Bool = { false }
    ) -> Result<ConstructiveGeneratedPuzzle, GenerationFailure> {
        guard (8...10).contains(request.size),
              request.maxMistakes > 0,
              request.difficulty != .easy || request.profile == .dominantBackground else {
            return .failure(GenerationFailure(
                stage: .invalidRequest,
                seed: request.seed,
                message: "Supported sizes are 8...10; Easy requires dominantBackground.",
                work: emptyWork
            ))
        }

        var rng = SeededRandomNumberGenerator(seed: request.seed)
        var consumedSolutionRestarts = 0
        var consumedPartitionRestarts = 0
        var consumedMutations = 0
        var consumedLogicalEvaluations = 0
        var best: EvaluatedCandidate?
        var reachedCertification = false
        // Partition restarts are a global budget. Give each planted solution
        // enough local retries to absorb stochastic construction failures,
        // while still exploring more than one solution permutation.
        let partitionsPerSolution = max(
            1,
            (request.budget.partitionRestarts
                + max(1, request.budget.solutionRestarts) - 1)
                / max(1, request.budget.solutionRestarts)
        )

        generation: for _ in 0..<request.budget.solutionRestarts {
            guard consumedPartitionRestarts < request.budget.partitionRestarts,
                  consumedLogicalEvaluations < request.budget.logicalEvaluations else {
                break
            }
            if isCancelled() {
                return cancelledFailure(
                    request: request,
                    solutionRestarts: consumedSolutionRestarts,
                    partitionRestarts: consumedPartitionRestarts,
                    boundaryMutations: consumedMutations,
                    logicalEvaluations: consumedLogicalEvaluations
                )
            }
            consumedSolutionRestarts += 1
            let solutionSearch = SolutionPermutationGenerator.generate(
                size: request.size,
                rng: &rng,
                nodeBudget: 20_000,
                requiresHardBlueprint: request.difficulty == .hard
            )
            guard let solution = solutionSearch.solution else { continue }

            for _ in 0..<partitionsPerSolution {
                guard consumedPartitionRestarts < request.budget.partitionRestarts,
                      consumedLogicalEvaluations < request.budget.logicalEvaluations else {
                    break generation
                }
                if isCancelled() {
                    return cancelledFailure(
                        request: request,
                        solutionRestarts: consumedSolutionRestarts,
                        partitionRestarts: consumedPartitionRestarts,
                        boundaryMutations: consumedMutations,
                        logicalEvaluations: consumedLogicalEvaluations
                    )
                }
                consumedPartitionRestarts += 1
                guard let partition = RegionPartition.build(
                    size: request.size,
                    solution: solution,
                    difficulty: request.difficulty,
                    profile: request.profile,
                    rng: &rng
                ) else {
                    continue
                }

                var beam: [EvaluatedCandidate] = []
                let partitionCount = max(1, request.budget.partitionRestarts)
                let mutationAllowance = max(
                    1,
                    request.budget.boundaryMutations / partitionCount
                )
                let partitionMutationLimit = min(
                    request.budget.boundaryMutations,
                    consumedMutations + mutationAllowance
                )
                if consumedLogicalEvaluations < request.budget.logicalEvaluations {
                    consumedLogicalEvaluations += 1
                    let candidate = evaluate(
                        partition: partition,
                        request: request,
                        restart: consumedPartitionRestarts
                    )
                    beam = [candidate]
                    best = preferred(best, candidate)
                }

                while !beam.isEmpty,
                      consumedMutations < partitionMutationLimit,
                      consumedLogicalEvaluations < request.budget.logicalEvaluations {
                    if isCancelled() {
                        return cancelledFailure(
                            request: request,
                            solutionRestarts: consumedSolutionRestarts,
                            partitionRestarts: consumedPartitionRestarts,
                            boundaryMutations: consumedMutations,
                            logicalEvaluations: consumedLogicalEvaluations
                        )
                    }
                    if let final = beam.first(where: {
                        $0.coverage.isSatisfied && $0.geometryMatchesProfile
                    }) {
                        reachedCertification = true
                        let certification = PuzzleSolver.solve(
                            level: final.level,
                            budget: PuzzleSolverBudget(
                                maxVisitedNodes: request.budget.exactSolverNodes
                            )
                        )
                        if case let .unique(foundSolution) = certification.result,
                           foundSolution == solution {
                            return .success(ConstructiveGeneratedPuzzle(
                                level: final.level,
                                solution: solution,
                                logicalReport: final.logicalResult.report,
                                exactSolverReport: certification,
                                difficulty: request.difficulty,
                                profile: request.profile,
                                blueprintCoverage: final.coverage,
                                geometry: final.geometry,
                                seed: request.seed,
                                work: GenerationWork(
                                    solutionRestarts: consumedSolutionRestarts,
                                    partitionRestarts: consumedPartitionRestarts,
                                    boundaryMutations: consumedMutations,
                                    logicalEvaluations: consumedLogicalEvaluations
                                )
                            ))
                        }
                        break
                    }

                    var next: [EvaluatedCandidate] = beam
                    for candidate in beam {
                        let moves = candidate.partition.boundaryMoves()
                            .shuffled(using: &rng)
                        let perCandidateLimit = max(
                            1,
                            min(12, partitionMutationLimit - consumedMutations)
                        )
                        for move in moves.prefix(perCandidateLimit) {
                            guard consumedMutations < partitionMutationLimit,
                                  consumedLogicalEvaluations < request.budget.logicalEvaluations else {
                                break
                            }
                            consumedMutations += 1
                            guard let mutated = candidate.partition.applying(move) else {
                                continue
                            }
                            let geometry = RegionGeometryAnalyzer.analyze(mutated)
                            guard RegionGeometryAnalyzer.matches(
                                geometry,
                                size: request.size,
                                difficulty: request.difficulty,
                                profile: request.profile
                            ) else {
                                continue
                            }
                            consumedLogicalEvaluations += 1
                            let evaluated = evaluate(
                                partition: mutated,
                                request: request,
                                restart: consumedPartitionRestarts,
                                geometry: geometry
                            )
                            next.append(evaluated)
                            best = preferred(best, evaluated)
                        }
                    }

                    beam = selectBeam(
                        next,
                        width: request.budget.beamWidth
                    )
                }

                if let final = beam.first(where: {
                    $0.coverage.isSatisfied && $0.geometryMatchesProfile
                }) {
                    reachedCertification = true
                    let certification = PuzzleSolver.solve(
                        level: final.level,
                        budget: PuzzleSolverBudget(
                            maxVisitedNodes: request.budget.exactSolverNodes
                        )
                    )
                    if case let .unique(foundSolution) = certification.result,
                       foundSolution == solution {
                        return .success(ConstructiveGeneratedPuzzle(
                            level: final.level,
                            solution: solution,
                            logicalReport: final.logicalResult.report,
                            exactSolverReport: certification,
                            difficulty: request.difficulty,
                            profile: request.profile,
                            blueprintCoverage: final.coverage,
                            geometry: final.geometry,
                            seed: request.seed,
                            work: GenerationWork(
                                solutionRestarts: consumedSolutionRestarts,
                                partitionRestarts: consumedPartitionRestarts,
                                boundaryMutations: consumedMutations,
                                logicalEvaluations: consumedLogicalEvaluations
                            )
                        ))
                    }
                }
            }
        }

        let work = GenerationWork(
            solutionRestarts: consumedSolutionRestarts,
            partitionRestarts: consumedPartitionRestarts,
            boundaryMutations: consumedMutations,
            logicalEvaluations: consumedLogicalEvaluations
        )
        return .failure(GenerationFailure(
            stage: reachedCertification ? .certification : .logicalSearch,
            seed: request.seed,
            message: reachedCertification
                ? "A logical candidate was found, but uniqueness was not certified within the budget."
                : "No candidate satisfied the requested deduction blueprint within the budget.",
            work: work,
            bestLogicalReport: best?.logicalResult.report,
            bestGeometry: best?.geometry
        ))
    }

    private static let emptyWork = GenerationWork(
        solutionRestarts: 0,
        partitionRestarts: 0,
        boundaryMutations: 0,
        logicalEvaluations: 0
    )

    private static func cancelledFailure(
        request: ConstructiveGenerationRequest,
        solutionRestarts: Int,
        partitionRestarts: Int,
        boundaryMutations: Int,
        logicalEvaluations: Int
    ) -> Result<ConstructiveGeneratedPuzzle, GenerationFailure> {
        .failure(GenerationFailure(
            stage: .cancelled,
            seed: request.seed,
            message: "Generation was cancelled.",
            work: GenerationWork(
                solutionRestarts: solutionRestarts,
                partitionRestarts: partitionRestarts,
                boundaryMutations: boundaryMutations,
                logicalEvaluations: logicalEvaluations
            )
        ))
    }

    private static func evaluate(
        partition: RegionPartition,
        request: ConstructiveGenerationRequest,
        restart: Int,
        geometry suppliedGeometry: RegionGeometryMetrics? = nil
    ) -> EvaluatedCandidate {
        let level = LevelDefinition(
            id: "constructive-v1-\(request.seed)-\(restart)",
            size: request.size,
            catCount: request.size,
            maxMistakes: request.maxMistakes,
            regionIDs: partition.regionIDs
        )
        let logicalResult = LogicalPuzzleSolver.solve(
            level: level,
            mode: .logicOnly
        )
        let coverage = DeductionBlueprint.evaluate(
            difficulty: request.difficulty,
            result: logicalResult
        )
        let geometry = suppliedGeometry ?? RegionGeometryAnalyzer.analyze(partition)
        return EvaluatedCandidate(
            partition: partition,
            level: level,
            logicalResult: logicalResult,
            coverage: coverage,
            geometry: geometry,
            geometryMatchesProfile: RegionGeometryAnalyzer.matches(
                geometry,
                size: request.size,
                difficulty: request.difficulty,
                profile: request.profile
            ),
            profile: request.profile
        )
    }

    private static func preferred(
        _ current: EvaluatedCandidate?,
        _ candidate: EvaluatedCandidate
    ) -> EvaluatedCandidate {
        guard let current else { return candidate }
        return candidate.isPreferred(over: current) ? candidate : current
    }

    private static func selectBeam(
        _ candidates: [EvaluatedCandidate],
        width: Int
    ) -> [EvaluatedCandidate] {
        var unique: [[Int]: EvaluatedCandidate] = [:]
        for candidate in candidates {
            let hash = candidate.partition.canonicalHash
            if let existing = unique[hash], !candidate.isPreferred(over: existing) {
                continue
            }
            unique[hash] = candidate
        }
        return unique.values.sorted {
            if $0.isPreferred(over: $1) { return true }
            if $1.isPreferred(over: $0) { return false }
            return $0.partition.canonicalHash.lexicographicallyPrecedes(
                $1.partition.canonicalHash
            )
        }.prefix(width).map { $0 }
    }
}

private struct EvaluatedCandidate {
    let partition: RegionPartition
    let level: LevelDefinition
    let logicalResult: LogicalSolveResult
    let coverage: BlueprintCoverage
    let geometry: RegionGeometryMetrics
    let geometryMatchesProfile: Bool
    let profile: RegionGeometryProfile

    func isPreferred(over other: EvaluatedCandidate) -> Bool {
        let lhs = rank
        let rhs = other.rank
        if lhs.invariant != rhs.invariant { return lhs.invariant > rhs.invariant }
        if lhs.outcome != rhs.outcome { return lhs.outcome > rhs.outcome }
        if lhs.coverage != rhs.coverage { return lhs.coverage > rhs.coverage }
        if lhs.confirmedCats != rhs.confirmedCats { return lhs.confirmedCats > rhs.confirmedCats }
        if lhs.candidateCount != rhs.candidateCount { return lhs.candidateCount < rhs.candidateCount }
        if lhs.geometryPenalty != rhs.geometryPenalty { return lhs.geometryPenalty < rhs.geometryPenalty }
        return false
    }

    private var rank: (
        invariant: Int,
        outcome: Int,
        coverage: Int,
        confirmedCats: Int,
        candidateCount: Int,
        geometryPenalty: Int
    ) {
        let outcome: Int
        switch logicalResult {
        case .solved: outcome = 2
        case .stuck: outcome = 1
        case .contradiction: outcome = 0
        }
        let confirmedCats = logicalResult.report.finalBoard.states.filter {
            $0 == .confirmedCat
        }.count
        let candidates = logicalResult.report.finalBoard.states.filter {
            $0 == .candidate
        }.count
        return (
            geometry.connectedRegionCount == partition.size ? 1 : 0,
            outcome,
            coverage.achievedStages,
            confirmedCats,
            candidates,
            geometryPenalty
        )
    }

    private var geometryPenalty: Int {
        let targetLargest = profile == .dominantBackground ? 0.42 : 0.18
        return Int(abs(geometry.largestRegionFraction - targetLargest) * 10_000)
            + geometry.regionsWithHoles.count * 1_000
            + geometry.narrowCorridorCellCount * 10
    }
}
