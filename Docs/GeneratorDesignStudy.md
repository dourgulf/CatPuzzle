# Generator Design Study

This study records structural observations from ten supplied human-designed screenshots. The source screenshots remain local and out of version control; the layouts are research input only and are not product levels to copy.

## Sample Verification

The screenshots contain one 8×8, two 9×9, and seven 10×10 layouts. Each grid was transcribed from cell-center colors, checked with `PuzzleSolver`, and simulated with `LogicalPuzzleSolver.logicOnly`.

| Sample | Source level | Size | Solution columns by row (1-based) | Largest region | Logic-only result | Notable techniques |
| --- | ---: | ---: | --- | ---: | --- | --- |
| 001 | 221 | 8 | 3, 1, 8, 2, 6, 4, 7, 5 | 17/64 | Solved | Region singles, locked pair |
| 002 | 222 | 10 | 2, 5, 3, 8, 10, 7, 9, 6, 1, 4 | 67/100 | Solved | Singleton anchor, locked pair |
| 003 | 223 | 10 | 4, 7, 9, 6, 8, 10, 1, 3, 5, 2 | 36/100 | Solved | Locked pair and triple |
| 004 | 214 | 9 | 8, 3, 5, 7, 1, 6, 2, 4, 9 | 18/81 | Solved | Three locked pairs |
| 005 | 215 | 10 | 7, 1, 6, 8, 10, 5, 2, 4, 9, 3 | 32/100 | Solved | Pair, triple, common attack |
| 006 | 216 | 10 | 4, 8, 6, 10, 5, 7, 1, 3, 9, 2 | 36/100 | Solved | Four locked pairs |
| 007 | 217 | 9 | 3, 9, 7, 1, 4, 6, 2, 5, 8 | 22/81 | Solved | Pair, triple, common attack |
| 008 | 218 | 10 | 8, 2, 7, 5, 10, 6, 4, 9, 3, 1 | 32/100 | Solved | Three locked pairs |
| 009 | 219 | 10 | 4, 6, 10, 7, 5, 9, 1, 3, 8, 2 | 36/100 | Solved | Four pairs and a triple |
| 010 | 220 | 10 | 5, 8, 3, 9, 1, 10, 6, 2, 7, 4 | 31/100 | Stuck after 2 cats | Adjacency-aware forcing net |

All ten layouts have exactly one solution. Every region is connected even under the stricter four-neighbor definition; none relies on diagonal contact alone.

## Observed Design Characteristics

- Region areas are intentionally unbalanced. Largest regions occupy 22%–67% of their boards, while three samples contain a one-cell region.
- Seven layouts contain a dominant 31–67 cell region. It behaves like a connected background left after smaller clue-bearing regions are carved out.
- Small regions are compact blocks, short bands, or simple polyominoes. Large regions may wind between them and contain narrow corridors.
- Region geometry is aligned with rows and columns. This creates constrained region-to-row and region-to-column relationships that become locked pairs or triples.
- Easy entry points are deliberate rather than accidental: singleton or very small regions create an initial cat, while harder samples begin with a locked-set elimination before the first placement.
- The planted cat permutation itself is varied. The useful structure comes from the interaction between that solution and region boundaries, not from a fixed column pattern.
- Accepted levels form a deduction cascade: an anchor deduction places a cat, propagation reduces other rows, columns, and regions, and the next planned deduction becomes available.

## Generator Direction Suggested by the Samples

The replacement generator should be constructive rather than rejection-driven:

1. Generate a legal, non-touching solution permutation.
2. Choose an intended deduction profile and one or more initial anchors.
3. Seed every region with its planted solution cat.
4. Grow or carve connected regions while deliberately creating the desired region↔row and region↔column candidate relationships.
5. Fill remaining cells with a connected background region or a balanced mosaic profile.
6. Mutate only region boundaries, preserving planted cats and the selected connectivity profile.
7. Use the logical solver as generation feedback; run exhaustive uniqueness verification only on final candidates.

Random per-cell assignment and single-cell uniqueness repair do not preserve these characteristics and should remain only as a benchmark baseline.

## Accepted Generation Contract

Connectivity remains a design-profile property rather than a `LevelValidator` rule. Generated layouts default to four-neighbor connectivity; diagonal-only connectivity remains available to a future profile. The first version supports two configurable profiles:

- `dominantBackground`: the background normally occupies 25%–70% of the board. Other regions normally contain 1–12 cells, with at most one intentional singleton. Small regions are four-neighbor connected and hole-free; the background may enclose islands and use one-cell corridors.
- `balancedMosaic`: no singleton regions; target areas normally range from `N / 2` through `2N`, the largest region occupies at most 28%, and every region is four-neighbor connected and hole-free.

These ranges are profile defaults inferred from a small sample, not domain invariants. A future `layeredBands` profile can be added without changing level validity.

Difficulty is also constructive:

- Easy starts with a single anchor and propagation, optionally followed by one locked pair.
- Medium requires a locked pair or triple and avoids a cascade of immediately available singleton placements.
- Hard requires common attack, strong link, or a multi-stage locked-set transfer, but never an assumption.

A `DeductionBlueprint` records a partial order of milestones, not an exact solver trace. The generator may construct an initial static motif directly; later deductions emerge after propagation and are optimized with logical-solver feedback. Logic-only completion is the constructive proof used during search. `PuzzleSolver` runs once on a final candidate as independent uniqueness certification.

Sample 010 is an explicit solver capability-gap study. After the current rules stop, assuming either of two incorrect row-one candidates and applying deterministic closure forces a cat that attacks both remaining candidates of another region. Each branch therefore empties an exactly-one constraint and proves its assumption false. This is an adjacency-aware forcing net (or grouped forcing chain), not another pair/triple or a simple strong link. Supporting it as an explainable technique requires a bounded contradiction-elimination rule; it is not a first-version generation target.

## Proposed Generator Architecture

1. `SolutionPermutationGenerator` creates a legal non-touching planted solution.
2. `DeductionBlueprint` describes required techniques and dependency milestones.
3. `RegionPartition` owns region membership, planted cats, boundaries, areas, and row/column footprints while enforcing construction invariants.
4. `DominantBackgroundBuilder` or `BalancedMosaicBuilder` creates an initial connected partition.
5. `BoundaryOptimizer` applies reversible, connectivity-preserving boundary transfers.
6. `CandidateEvaluator` orders decisions lexicographically: construction invariants, logical outcome, reasoning progress, blueprint coverage, then geometry quality.
7. A final certifier runs exact uniqueness verification and reports bounded diagnostics.

The dominant-background builder starts with one connected background and grows the other regions outward from their planted cats. The balanced-mosaic builder uses quota-aware multi-source growth, with row/column footprints reserved for reasoning motifs. Boundary optimization uses deterministic seeded tie-breaking and fixed work budgets; wall-clock time is a safety limit and performance observation, not the primary stopping rule.

`RegionPartition` is the generator's internal source of truth for membership, planted cats, region cells, boundaries, areas, per-row counts, and per-column counts. A reversible `BoundaryMove` may transfer only a non-solution boundary cell to an orthogonally adjacent region. The source must remain connected after removal; adjacency makes the destination remain connected. For boards up to 10×10, a direct breadth-first connectivity check is preferred over a dynamic connectivity structure. The first implementation combines single-cell moves with bounded deterministic restarts and does not implement region swaps or multi-cell transfers.

Candidate comparison is lexicographic rather than a blended weighted score:

1. Reject any violated construction invariant.
2. Prefer logical `solved` over `stuck` over `contradiction`.
3. For incomplete candidates, prefer more confirmed cats and lower remaining candidate entropy.
4. Prefer the longest satisfied partial order of blueprint milestones.
5. Compare profile-specific geometry quality.

Raw exclusion and propagation counts are diagnostics, not progress objectives, because they can increase without making the puzzle meaningfully closer to a solve. Geometry quality cannot compensate for a broken invariant.

Generation uses fixed budgets for solution restarts, boundary mutations, logical evaluations, and exact-solver nodes. A ten-second wall-clock limit is a safety stop and the 10×10 p95 acceptance metric, not the primary termination mechanism. Failure returns structured diagnostics containing the seed, stopped stage, consumed budgets, best logical progress, and geometry deviations. It never retries indefinitely.

The initial Easy, Medium, and Hard profiles remain forward-deduction Mainline levels. Sample 010's adjacency-aware forcing net is reserved for a later Challenge profile with bounded contradiction elimination. The new solution generator returns `Result`; backtracking failure is explicit and contributes to diagnostics rather than leaving an incomplete permutation.

The first-version compatibility matrix is intentional. Easy uses `dominantBackground` and one singleton anchor. Medium allows either geometry profile, forbids singletons, and opens through a locked pair or triple. Hard also allows either profile, forbids singletons, and requires a locked-set chain leading to common attack or strong link. `balancedMosaic` Easy is deferred because an initially empty board with no singleton cannot begin with a basic single deduction.

Callers choose only Easy, Medium, or Hard. The concrete blueprint remains an internal generation plan recorded in output metadata. Blueprint requirements define the target; the final logical report is the authority on achieved techniques. A candidate whose measured technique contract does not match is rejected even if its legacy numeric difficulty score falls in the requested range.

A hole is defined topologically: after removing one region, a remaining four-neighbor component that cannot reach the board boundary is enclosed by that region. Balanced mosaics and small dominant-background regions must be hole-free; the dominant background may intentionally enclose other regions. One-cell corridors are allowed but penalized by the geometry evaluator.

The production request contains size (8...10), seed, difficulty, geometry profile, and `GenerationBudget`. Generation returns `Result<GeneratedPuzzle, GenerationFailure>` with the level, verified solution, logical report, blueprint coverage, geometry metrics, and diagnostics. Legacy color-assignment strategies, repair limits, and Challenge mode are absent from the production API.

A thin `catpuzzle-generate` Swift executable provides the offline entry point and JSON output while keeping all algorithms in `CatPuzzleCore`. Before layout construction, each legal solution permutation undergoes Profile and Blueprint feasibility checks. An infeasible permutation consumes a bounded solution restart; it is not forced through boundary optimization.

## Deduction Contracts

Blueprints are ordered stages containing `allOf` and `anyOf` technique predicates. They are intentionally less general than arbitrary dependency graphs and do not prescribe the solver's exact order when multiple deductions are simultaneously available.

- Easy: a singleton Region places the first cat; at most one locked pair may be used; locked triples, common attacks, and strong links are forbidden.
- Medium: a locked pair or triple must occur before the first cat; at least two reasoning stages separated by a cat placement are required; common attacks and strong links are forbidden.
- Hard: a locked set must occur first, at least one cat must then be placed, and a later common attack or strong link must occur.
- Every Mainline contract requires logic-only completion and zero assumptions.

Initial motifs are constructed through Region footprints. Easy reserves one singleton Region. Medium and Hard choose two or three Regions and confine their cells to the corresponding two or three rows or columns, creating an initial locked set. The seed selects the axis deterministically. Later techniques are not compiled directly into geometry; they emerge through solver-guided boundary optimization.

## Construction and Search

The dominant-background builder assigns one planted cat to the background. Every other planted cat begins as a singleton island; legal cells are transferred outward from the connected background until target areas and footprints are approached. The balanced-mosaic builder starts every Region at its planted cat and fills the board through quota-aware, motif-aware multi-source priority flood. Quotas guide selection rather than acting as hard caps. A dead end consumes a bounded builder restart.

Boundary optimization uses a bounded beam rather than a single hill-climbing path. Each generation retains logical-progress, blueprint-coverage, geometry-quality, and layout-diversity elites, deduplicated by canonical layout hash. Only invariant-preserving moves enter the beam. Exact numeric beam and evaluation budgets are calibrated by the benchmark rather than embedded in the design contract.

Final certification uses a budgeted exact solver upgraded from fixed row-order DFS to minimum-remaining-values search with compact row, column, Region, and adjacency occupancy sets. Budget exhaustion is an inconclusive certification result, never no-solution.

The CLI emits both machine-readable JSON and an inspection-oriented Markdown package containing the Region grid, solution diagram, ordered logical explanation, blueprint stages, geometry metrics, seed, algorithm version, consumed budgets, and exact-certification statistics.

Implementation is split into two independent phases. Phase 1 renames the rule-bearing API from `colorID` to `regionID` across core, solver, app, export, and tests without changing behavior or preserving a compatibility layer. Phase 2 replaces production random coloring with the constructive pipeline; the existing random-repair implementation remains benchmark-only.
