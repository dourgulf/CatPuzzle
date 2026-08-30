# Generator Implementation Plan

This plan replaces rejection-driven random coloring with deterministic offline construction for 8×8, 9×9, and 10×10 levels. Generated output is design input and must be reviewed before becoming a built-in level.

## Delivery Sequence

### PR A — Region terminology

Rename `colorID` and related Color rule terminology to `regionID` across models, validators, solvers, app rendering, persistence/export, documentation, and tests. Preserve behavior, provide no compatibility aliases, and do not extend the old repair algorithm.

### PR B — Solver infrastructure

Expose generic logical technique events and candidate snapshots without teaching the solver about generation difficulty or blueprints. Upgrade exact solving to budgeted MRV search with occupancy bitsets and statistics. Represent budget exhaustion as inconclusive.

### PR C — Constructive generator

Add `SolutionPermutationGenerator`, internal staged `DeductionBlueprint` presets, `RegionPartition`, the dominant-background and balanced-mosaic builders, reversible boundary moves, geometry analysis, bounded beam optimization, blueprint evaluation, and structured diagnostics.

### PR D — Offline workflow

Add `catpuzzle-generate`, versioned JSON export, Markdown review reports, fixed-seed integration coverage, and an offline multi-seed performance harness. The CLI never modifies `BuiltInLevels`.

## Request and Result

The production request specifies size, seed, Easy/Medium/Hard difficulty, a compatible geometry profile, and explicit generation budgets. Results contain the canonicalized level, verified planted solution, logical report, achieved blueprint stages, geometry metrics, algorithm version, budget usage, and exact-solver certification. A failure identifies its stage and preserves the best available diagnostic candidate.

Region IDs are canonicalized by planted-cat row. Reproducibility is guaranteed only for identical algorithm version, request, and seed.

## Verification Gates

- Unit tests cover partition invariants, connectivity, holes, reversible moves, profiles, blueprint predicates, budgets, and failures.
- Fixed seeds cover every supported size/profile/difficulty combination, deterministic replay, logical completion, technique contracts, and exact uniqueness.
- Offline benchmarks measure success rate and latency distributions. The acceptance target is 10×10 p95 at or below ten seconds on an ordinary development Mac.
- A human reviews the Region diagram, solution, reasoning report, and play experience before promotion to a product fixture.
