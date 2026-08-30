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
                colorAssignmentStrategy: request.colorAssignmentStrategy,
                targetTiers: request.targetTiers,
                maxRepairAttempts: request.maxRepairAttempts
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
            rejectedNotChallenge: rejections.notChallenge,
            rejectedDifficultyMismatch: rejections.difficultyMismatch
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
        case difficultyMismatch
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
        case .difficultyMismatch: rejections.difficultyMismatch += 1
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

        var level = LevelDefinition(
            id: "generated-seed\(request.seed)-attempt\(attempt)",
            size: request.size,
            catCount: request.size,
            maxMistakes: request.maxMistakes,
            colorIDs: colorIDs
        )

        guard (try? LevelValidator.validate(level)) != nil else {
            return .rejected(.invalidLevel)
        }

        if let repaired = repairForUniqueSolution(
            level: level,
            solution: solution,
            maxRepairAttempts: request.maxRepairAttempts
        ) {
            level = repaired
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

        let report: LogicalSolveReport
        switch request.mode {
        case .mainline:
            let result = LogicalPuzzleSolver.solve(level: level, mode: .logicOnly)
            guard case let .solved(mainlineReport) = result, mainlineReport.statistics.assumptionCount == 0 else {
                return .rejected(.logicalStuck)
            }
            report = mainlineReport

        case let .challenge(maxAssumptionDepth):
            let logicOnlyResult = LogicalPuzzleSolver.solve(level: level, mode: .logicOnly)
            guard !logicOnlyResult.isSolved else {
                return .rejected(.notChallenge)
            }

            let challengeResult = LogicalPuzzleSolver.solve(
                level: level,
                mode: .challenge(maxAssumptionDepth: maxAssumptionDepth)
            )
            guard case let .solved(challengeReport) = challengeResult,
                  challengeReport.statistics.assumptionCount > 0,
                  challengeReport.statistics.maxAssumptionDepth <= maxAssumptionDepth else {
                return .rejected(.logicalStuck)
            }
            report = challengeReport
        }

        let difficulty = PuzzleDifficultyAnalyzer.analyze(report)
        guard request.targetTiers.isEmpty || request.targetTiers.contains(difficulty.tier) else {
            return .rejected(.difficultyMismatch)
        }

        return .success(makeGeneratedPuzzle(
            level: level,
            solution: solution,
            report: report,
            difficulty: difficulty,
            request: request,
            attempt: attempt
        ))
    }

    private static func makeGeneratedPuzzle(
        level: LevelDefinition,
        solution: [CellPosition],
        report: LogicalSolveReport,
        difficulty: PuzzleDifficulty,
        request: PuzzleGenerationRequest,
        attempt: Int
    ) -> GeneratedPuzzle {
        GeneratedPuzzle(
            level: level,
            solution: solution,
            logicalReport: report,
            difficulty: difficulty,
            generationMetadata: PuzzleGenerationMetadata(seed: request.seed, attempt: attempt)
        )
    }

    // MARK: - Uniqueness repair

    /// Plain random coloring's odds of producing a level with a unique
    /// solution collapse once the board grows past ~7x7 — there are simply
    /// too many other row/column/adjacency-valid permutations for an
    /// independently-random coloring to also happen to make each of them
    /// non-rainbow (empirically: at size 8, 500/500 `.uniform` attempts
    /// were rejected as `.multipleSolutions`). Rather than hoping a fresh
    /// random attempt eventually gets lucky, this actively eliminates
    /// competing solutions one at a time: find another valid permutation
    /// `spurious` (row/column/adjacency-legal, and — since it differs from
    /// `solution` — using a color combination that happens to also be
    /// rainbow), then force two of its own cells to share a color. Since
    /// two distinct permutations of the same size must differ in at least
    /// two positions, there's always a non-solution cell in `spurious` to
    /// recolor — so `solution`'s own cells (and thus its validity as *a*
    /// solution) are never touched, only whether other permutations
    /// compete with it.
    ///
    /// Returns a repaired `LevelDefinition` once `PuzzleSolver` finds
    /// `solution` to be the unique solution, or `nil` if `maxRepairAttempts`
    /// is exhausted first (the caller falls back to its normal uniqueness
    /// check, which will reject the untouched candidate as usual).
    ///
    /// Once a cell is used in a repair (as the one recolored, or as the
    /// color it was copied from) it is locked from ever being touched
    /// again. Without this, a later repair could recolor the "source" side
    /// of an earlier fix, silently reintroducing the color match that made
    /// the earlier fix work and undoing it — observed empirically as
    /// non-convergence (5000+ repairs without reaching uniqueness at 8x8).
    /// Locking guarantees each repair permanently kills its target
    /// permutation, bounding the loop by the number of non-solution cells
    /// rather than needing an unbounded attempt budget.
    static func repairForUniqueSolution(
        level: LevelDefinition,
        solution: [CellPosition],
        maxRepairAttempts: Int
    ) -> LevelDefinition? {
        var colorIDs = level.colorIDs
        let solutionSet = Set(solution)
        var lockedCells: Set<CellPosition> = []

        for _ in 0..<max(0, maxRepairAttempts) {
            let candidate = LevelDefinition(
                id: level.id,
                size: level.size,
                catCount: level.catCount,
                maxMistakes: level.maxMistakes,
                colorIDs: colorIDs
            )

            let solutions = PuzzleSolver.solutions(for: candidate, limit: 2)
            switch solutions.count {
            case 0:
                // A previous repair over-constrained the board; nothing
                // further can help this attempt.
                return nil
            case 1:
                return candidate
            default:
                guard let spurious = solutions.first(where: { Set($0) != solutionSet }) else {
                    return nil
                }
                guard let targetCell = spurious.first(where: {
                    !solutionSet.contains($0) && !lockedCells.contains($0)
                }) else {
                    // Every touchable cell in this competing permutation has
                    // already been spent on an earlier fix we can't risk
                    // undoing — give up on repairing this candidate.
                    return nil
                }
                guard let colorSourceCell = spurious.first(where: { $0 != targetCell }) else {
                    return nil
                }
                colorIDs[targetCell.row][targetCell.column] =
                    colorIDs[colorSourceCell.row][colorSourceCell.column]
                lockedCells.insert(targetCell)
                lockedCells.insert(colorSourceCell)
            }
        }

        return nil
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

        let context = colorAssignmentContext(size: size, solution: solution, strategy: strategy, rng: &rng)

        for row in 0..<size {
            for column in 0..<size where colorIDs[row][column] == -1 {
                colorIDs[row][column] = pickColor(
                    for: CellPosition(row: row, column: column),
                    size: size,
                    solution: solution,
                    strategy: strategy,
                    context: context,
                    rng: &rng
                )
            }
        }
        return colorIDs
    }

    /// Seed-derived, once-per-puzzle choices for the two onboarding
    /// strategies: which color is reserved as a singleton, or which two
    /// colors are confined and to which rows/columns. `.uniform`/`.biased`
    /// leave this empty and are unaffected.
    private struct ColorAssignmentContext {
        var reservedColor: Int?
        var confinedPair: (Int, Int)?
        var confinedRows: Set<Int>?
        var confinedColumns: Set<Int>?
    }

    private static func colorAssignmentContext(
        size: Int,
        solution: [CellPosition],
        strategy: ColorAssignmentStrategy,
        rng: inout SeededRandomNumberGenerator
    ) -> ColorAssignmentContext {
        switch strategy {
        case .uniform, .biased:
            return ColorAssignmentContext()

        case .singletonColor:
            let reserved = Int.random(in: 0..<size, using: &rng)
            return ColorAssignmentContext(reservedColor: reserved)

        case let .confinedColorPair(axis):
            let colorA = Int.random(in: 0..<size, using: &rng)
            var colorB = Int.random(in: 0..<(size - 1), using: &rng)
            if colorB >= colorA { colorB += 1 }

            switch axis {
            case .rows:
                // Solution row i always holds colorID i (generateSolution
                // builds the solution array in row order), so a color's own
                // solution row is just its colorID.
                return ColorAssignmentContext(confinedPair: (colorA, colorB), confinedRows: [colorA, colorB])
            case .columns:
                let columnA = solution[colorA].column
                let columnB = solution[colorB].column
                return ColorAssignmentContext(confinedPair: (colorA, colorB), confinedColumns: [columnA, columnB])
            }
        }
    }

    private static func pickColor(
        for position: CellPosition,
        size: Int,
        solution: [CellPosition],
        strategy: ColorAssignmentStrategy,
        context: ColorAssignmentContext,
        rng: inout SeededRandomNumberGenerator
    ) -> Int {
        let excluded = excludedColors(for: position, context: context)

        switch strategy {
        case .uniform, .singletonColor, .confinedColorPair:
            return randomColor(excluding: excluded, size: size, rng: &rng)

        case let .biased(nearbySampleProbability):
            guard Double.random(in: 0..<1, using: &rng) < nearbySampleProbability else {
                return randomColor(excluding: excluded, size: size, rng: &rng)
            }
            let nearest = solution.min { lhs, rhs in
                let lhsDistance = manhattanDistance(lhs, position)
                let rhsDistance = manhattanDistance(rhs, position)
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                if lhs.row != rhs.row { return lhs.row < rhs.row }
                return lhs.column < rhs.column
            }
            guard let nearest, let colorID = solution.firstIndex(of: nearest), !excluded.contains(colorID) else {
                return randomColor(excluding: excluded, size: size, rng: &rng)
            }
            return colorID
        }
    }

    private static func excludedColors(for position: CellPosition, context: ColorAssignmentContext) -> Set<Int> {
        var excluded: Set<Int> = []
        if let reserved = context.reservedColor {
            excluded.insert(reserved)
        }
        if let pair = context.confinedPair {
            let inConfinedZone = context.confinedRows?.contains(position.row)
                ?? context.confinedColumns?.contains(position.column)
                ?? false
            if !inConfinedZone {
                excluded.insert(pair.0)
                excluded.insert(pair.1)
            }
        }
        return excluded
    }

    private static func randomColor(
        excluding: Set<Int>,
        size: Int,
        rng: inout SeededRandomNumberGenerator
    ) -> Int {
        let pool = (0..<size).filter { !excluding.contains($0) }
        guard !pool.isEmpty else { return Int.random(in: 0..<size, using: &rng) }
        return pool[Int.random(in: 0..<pool.count, using: &rng)]
    }

    private static func manhattanDistance(_ lhs: CellPosition, _ rhs: CellPosition) -> Int {
        abs(lhs.row - rhs.row) + abs(lhs.column - rhs.column)
    }
}
