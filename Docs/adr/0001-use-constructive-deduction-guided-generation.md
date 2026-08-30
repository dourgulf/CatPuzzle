---
status: accepted
---

# Use constructive deduction-guided level generation

The offline 8×8–10×10 generator will construct a legal planted solution, choose a Region Geometry Profile and Deduction Blueprint, grow connected regions around solution seeds, and optimize only through connectivity-preserving boundary changes. A blueprint expresses technique milestones and their partial order, not an exact solver trace. `LogicalPuzzleSolver` provides periodic search feedback and logic-only completion is the constructive solve criterion; exhaustive uniqueness checking runs once on a final candidate as independent certification. The generator defaults to four-neighbor-connected layouts, although diagonal connectivity remains valid in the broader level model. Random per-cell coloring and solution-by-solution recoloring repair are retained only as a benchmark because their search cost grows rapidly and their output does not resemble human-designed region geometry or reasoning chains.

## Considered Options

- Random cell coloring followed by rejection or uniqueness repair: rejected because it repeatedly invokes exponential search and destroys region structure.
- Shape-first random partition followed by solver filtering: rejected as the primary design because it still discovers reasoning quality by chance.
- Constructive, deduction-guided generation: accepted because geometry, solvability, difficulty, and explanation share one explicit plan.

## Consequences

The generator needs separate components for solution construction, geometry profiles, deduction blueprints, a Region partition with explicit construction invariants, connectivity-preserving boundary operations, logical evaluation, bounded diagnostics, and final certification. The first profiles are dominant background and balanced mosaic; their area and shape limits remain configurable defaults rather than level-validity rules. Boundary optimization initially uses reversible single-cell transfers and bounded restarts. Candidate quality is compared lexicographically: invariants, logical outcome and progress, blueprint coverage, then geometry. Search uses deterministic work budgets and seeded tie-breaking so results do not depend primarily on machine speed. Existing random-color strategies are not part of the production generation API.

The implementation begins with a behavior-preserving semantic migration from `colorID` to `regionID`, with no compatibility layer. Constructive generation follows as a separate change so terminology migration and algorithm replacement can be reviewed independently.

The production API accepts only sizes 8 through 10, a seed, Easy/Medium/Hard target, a compatible geometry profile, and explicit generation budgets. Concrete deduction blueprints remain internal and are recorded as metadata. The final logical report must satisfy the requested technique contract; the legacy numeric difficulty score is informative rather than the acceptance authority. A thin executable may expose the Core generator for offline JSON production without moving algorithmic responsibility into an app or command layer.

Blueprints use ordered predicate stages. Initial singleton or locked-set motifs are constructed explicitly; later milestones are discovered by solver-guided search. Layout optimization uses a bounded, deduplicated beam that retains logical, blueprint, geometry, and diversity elites. Final uniqueness certification uses a budgeted MRV exact solver and distinguishes budget exhaustion from proof of no solution.
