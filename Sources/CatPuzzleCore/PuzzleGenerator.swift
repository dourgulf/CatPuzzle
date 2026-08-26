/// Research tool for producing candidate CatPuzzle levels: generate a
/// legal solution, color the board around it, and run the same
/// `PuzzleSolver` / `LogicalPuzzleSolver` / `PuzzleDifficultyAnalyzer`
/// pipeline a human designer would use to sanity-check a hand-built level.
///
/// This intentionally never touches `BuiltInLevels` — everything here is
/// output for offline playtesting, not a runtime level source.
public enum PuzzleGenerator {
    public static func generate(request: PuzzleGenerationRequest) -> PuzzleGenerationResult {
        generateWithDiagnostics(request: request).result
    }

    public static func generateBatch(request: PuzzleBatchGenerationRequest) -> PuzzleBatchGenerationResult {
        var seedStream = SeededRandomNumberGenerator(seed: request.startSeed)
        var generated: [GeneratedPuzzle] = []
        var totalAttempts = 0
        var rejections = PuzzleGenerationRejectionCounts()

        for _ in 0..<max(0, request.count) {
            let puzzleSeed = seedStream.next()
            let puzzleRequest = PuzzleGenerationRequest(
                size: request.size,
                seed: puzzleSeed,
                mode: request.mode,
                maxAttempts: request.maxAttemptsPerPuzzle,
                maxMistakes: request.maxMistakes,
                colorAssignmentStrategy: request.colorAssignmentStrategy
            )

            let diagnostics = generateWithDiagnostics(request: puzzleRequest)
            totalAttempts += diagnostics.attempts
            rejections += diagnostics.rejections
            if case let .generated(puzzle) = diagnostics.result {
                generated.append(puzzle)
            }
        }

        let statistics = PuzzleBatchStatistics(
            requestedCount: request.count,
            generatedCount: generated.count,
            totalAttempts: totalAttempts,
            rejectedInvalidLevel: rejections.invalidLevel,
            rejectedNoSolution: rejections.noSolution,
            rejectedMultipleSolutions: rejections.multipleSolutions,
            rejectedWrongUniqueSolution: rejections.wrongUniqueSolution,
            rejectedLogicalStuck: rejections.logicalStuck,
            rejectedNotChallenge: rejections.notChallenge
        )
        return PuzzleBatchGenerationResult(generated: generated, statistics: statistics)
    }

    // MARK: - Single-attempt pipeline

    private enum CandidateOutcome {
        case success(GeneratedPuzzle)
        case rejected(RejectionReason)
    }

    private enum RejectionReason {
        case invalidLevel
        case noSolution
        case multipleSolutions
        case wrongUniqueSolution
        case logicalStuck
        case notChallenge
    }

    private struct GenerationDiagnostics {
        let result: PuzzleGenerationResult
        let attempts: Int
        let rejections: PuzzleGenerationRejectionCounts
    }

    private static func generateWithDiagnostics(request: PuzzleGenerationRequest) -> GenerationDiagnostics {
        var rng = SeededRandomNumberGenerator(seed: request.seed)
        var rejections = PuzzleGenerationRejectionCounts()

        for attempt in 1...max(1, request.maxAttempts) {
            switch attemptCandidate(request: request, attempt: attempt, rng: &rng) {
            case let .success(puzzle):
                return GenerationDiagnostics(result: .generated(puzzle), attempts: attempt, rejections: rejections)
            case let .rejected(reason):
                apply(reason, to: &rejections)
            }
        }

        let report = PuzzleGenerationReport(seed: request.seed, attempts: request.maxAttempts, rejections: rejections)
        return GenerationDiagnostics(result: .exhausted(report), attempts: request.maxAttempts, rejections: rejections)
    }

    private static func apply(_ reason: RejectionReason, to rejections: inout PuzzleGenerationRejectionCounts) {
        switch reason {
        case .invalidLevel: rejections.invalidLevel += 1
        case .noSolution: rejections.noSolution += 1
        case .multipleSolutions: rejections.multipleSolutions += 1
        case .wrongUniqueSolution: rejections.wrongUniqueSolution += 1
        case .logicalStuck: rejections.logicalStuck += 1
        case .notChallenge: rejections.notChallenge += 1
        }
    }

    private static func attemptCandidate(
        request: PuzzleGenerationRequest,
        attempt: Int,
        rng: inout SeededRandomNumberGenerator
    ) -> CandidateOutcome {
        let solution = generateSolution(size: request.size, rng: &rng)
        let colorIDs = assignColors(
            size: request.size,
            solution: solution,
            strategy: request.colorAssignmentStrategy,
            rng: &rng
        )

        let level = LevelDefinition(
            id: "generated-seed\(request.seed)-attempt\(attempt)",
            size: request.size,
            catCount: request.size,
            maxMistakes: request.maxMistakes,
            colorIDs: colorIDs
        )

        guard (try? LevelValidator.validate(level)) != nil else {
            return .rejected(.invalidLevel)
        }

        switch PuzzleSolver.solve(level: level) {
        case .none:
            return .rejected(.noSolution)
        case .multiple:
            return .rejected(.multipleSolutions)
        case let .unique(foundSolution):
            guard foundSolution == solution else {
                return .rejected(.wrongUniqueSolution)
            }
        }

        switch request.mode {
        case .mainline:
            let result = LogicalPuzzleSolver.solve(level: level, mode: .logicOnly)
            guard case let .solved(report) = result, report.statistics.assumptionCount == 0 else {
                return .rejected(.logicalStuck)
            }
            return .success(makeGeneratedPuzzle(level: level, solution: solution, report: report, request: request, attempt: attempt))

        case let .challenge(maxAssumptionDepth):
            let logicOnlyResult = LogicalPuzzleSolver.solve(level: level, mode: .logicOnly)
            guard !logicOnlyResult.isSolved else {
                return .rejected(.notChallenge)
            }

            let challengeResult = LogicalPuzzleSolver.solve(
                level: level,
                mode: .challenge(maxAssumptionDepth: maxAssumptionDepth)
            )
            guard case let .solved(report) = challengeResult,
                  report.statistics.assumptionCount > 0,
                  report.statistics.maxAssumptionDepth <= maxAssumptionDepth else {
                return .rejected(.logicalStuck)
            }
            return .success(makeGeneratedPuzzle(level: level, solution: solution, report: report, request: request, attempt: attempt))
        }
    }

    private static func makeGeneratedPuzzle(
        level: LevelDefinition,
        solution: [CellPosition],
        report: LogicalSolveReport,
        request: PuzzleGenerationRequest,
        attempt: Int
    ) -> GeneratedPuzzle {
        GeneratedPuzzle(
            level: level,
            solution: solution,
            logicalReport: report,
            difficulty: PuzzleDifficultyAnalyzer.analyze(report),
            generationMetadata: PuzzleGenerationMetadata(seed: request.seed, attempt: attempt)
        )
    }

    // MARK: - Solution generation

    /// Backtracks a column permutation (one cat per row/column) that also
    /// satisfies the 8-neighbor adjacency rule. Because same-row/-column
    /// collisions are already excluded by construction, adjacency only
    /// needs checking between consecutive rows. Column order at each row is
    /// shuffled from `rng` so different attempts explore different
    /// permutations, while staying fully deterministic for a given seed.
    static func generateSolution(size: Int, rng: inout SeededRandomNumberGenerator) -> [CellPosition] {
        var columnsByRow = [Int](repeating: -1, count: size)
        var usedColumns = Set<Int>()

        func backtrack(row: Int) -> Bool {
            if row == size { return true }
            let candidates = Array(0..<size).filter { !usedColumns.contains($0) }.shuffled(using: &rng)
            for column in candidates {
                if row > 0, abs(columnsByRow[row - 1] - column) <= 1 { continue }
                columnsByRow[row] = column
                usedColumns.insert(column)
                if backtrack(row: row + 1) { return true }
                usedColumns.remove(column)
                columnsByRow[row] = -1
            }
            return false
        }

        _ = backtrack(row: 0)
        return columnsByRow.enumerated().map { CellPosition(row: $0.offset, column: $0.element) }
    }

    // MARK: - Color assignment

    /// Each solution cat claims its row index as a unique color; every
    /// other cell is then colored per `strategy`. Colors are pure grouping
    /// labels here — no connectivity is enforced or checked (CLAUDE.md).
    static func assignColors(
        size: Int,
        solution: [CellPosition],
        strategy: ColorAssignmentStrategy,
        rng: inout SeededRandomNumberGenerator
    ) -> [[Int]] {
        var colorIDs = Array(repeating: Array(repeating: -1, count: size), count: size)
        for (colorID, position) in solution.enumerated() {
            colorIDs[position.row][position.column] = colorID
        }

        for row in 0..<size {
            for column in 0..<size where colorIDs[row][column] == -1 {
                colorIDs[row][column] = pickColor(
                    for: CellPosition(row: row, column: column),
                    size: size,
                    solution: solution,
                    strategy: strategy,
                    rng: &rng
                )
            }
        }
        return colorIDs
    }

    private static func pickColor(
        for position: CellPosition,
        size: Int,
        solution: [CellPosition],
        strategy: ColorAssignmentStrategy,
        rng: inout SeededRandomNumberGenerator
    ) -> Int {
        switch strategy {
        case .uniform:
            return Int.random(in: 0..<size, using: &rng)
        case let .biased(nearbySampleProbability):
            guard Double.random(in: 0..<1, using: &rng) < nearbySampleProbability else {
                return Int.random(in: 0..<size, using: &rng)
            }
            let nearest = solution.min { lhs, rhs in
                let lhsDistance = manhattanDistance(lhs, position)
                let rhsDistance = manhattanDistance(rhs, position)
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                if lhs.row != rhs.row { return lhs.row < rhs.row }
                return lhs.column < rhs.column
            }
            guard let nearest, let colorID = solution.firstIndex(of: nearest) else {
                return Int.random(in: 0..<size, using: &rng)
            }
            return colorID
        }
    }

    private static func manhattanDistance(_ lhs: CellPosition, _ rhs: CellPosition) -> Int {
        abs(lhs.row - rhs.row) + abs(lhs.column - rhs.column)
    }
}
