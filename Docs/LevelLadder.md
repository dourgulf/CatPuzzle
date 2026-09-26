# Level Ladder

The ordinary game starts with ten hand-authored rule-practice boards in
`Sources/CatPuzzleCore/OpeningLevels.swift`. They are followed by the 30
generated levels in `Sources/CatPuzzleCore/GeneratedLadderLevels.swift`.
`BuiltInLevels.fixtures` joins the two sets in play order. See
`Docs/OpeningLevels.md` for the first ten. This document describes the
generated part and how to regenerate it.

## Shape

After the ten opening levels, the generated section has this ten-level cycle:

| Slot | Board | Notes |
| --- | --- | --- |
| 1 | 8x8 | The gentle opener every lap starts on |
| 2-4 | 9x9 | Step up in size, still ordinary deduction |
| 5-9 | 10x10 | Full size, rising through the middle of the cycle |
| 10 | 10x10 | The finale, generated from the `hard` deduction blueprint |

Three generated cycles ship, so `GeneratedLadderLevels.fixtures` holds 30
levels and `GeneratedLadderLevels.levelsPerCycle` is 10. The complete ordinary
progression has 40 levels. Progress loops: finishing level 40 clears the lap
and starts again from opening level 1 (`LevelProgression.nextLevel`).

## Two difficulty axes, and why both are needed

`GeneratorDifficulty` (`easy` / `medium` / `hard`) picks which
`DeductionBlueprint` a candidate must satisfy — which techniques the intended
reasoning chain exposes.

`PuzzleDifficultyAnalyzer` scores a finished logical solve.

**These two do not agree at 8x8-10x10.** Measured on pools of 18-90 candidates,
9x9 `easy` boards score 58-64 while 9x9 `medium` boards score 54-56: the
blueprint tier constrains technique, but the score counts deduction volume, and
a sprawling easy board out-scores a tight medium one. Ordering slots by
requested tier alone would put an easier board after a harder one.

So the ladder uses both:

- Slots that share a board size draw from **one pool mixing `easy` and
  `medium`** candidates, ordered by measured score.
- Slot 10 draws from **`hard` only**, so every lap ends on a board that
  genuinely needs advanced techniques. `hard` does separate cleanly (10x10
  `hard` scores around 83 against 62-63 for `medium`).
- Each group only accepts candidates at or above the previous group's highest
  assigned score, which keeps the ramp rising where one board size hands over
  to the next.
- Inside a group, the *slots* are spread across the sorted pool (that is the
  ramp) while the three cycles' versions of one slot are taken from **adjacent**
  pool positions, so every lap covers the same difficulty shape instead of the
  last lap inheriting every band's hardest board.
- No two shipped levels may share a cat placement. Different Region layouts can
  produce the same solution, and shipping both reads as a repeat, so candidates
  are de-duplicated on their row-ordered solution before selection.

Note that `DifficultyTier` labels (`beginner`…`expert`) are calibrated for 6x6
boards and read `expert` for nearly everything at these sizes. Only the raw
score is used here, and only to order boards of comparable size — see
`DifficultyScoringStudy.md`.

## Regenerating

```bash
swift run -c release CatPuzzleGenerator \
  --ladder Sources/CatPuzzleCore/GeneratedLadderLevels.swift \
  --ladder-json /tmp/ladder.json \
  --cycles 3 --pool 6 --seed 20260914 --max-mistakes 3
```

- `--pool N` generates N candidates per shipped level. A wider pool gives the
  score ordering more range to spread slots across, at a linear cost in time.
- `--seed` fixes the run. The generator is deterministic, so the same seed,
  pool, and algorithm version reproduce the same 30 levels.
- The command prints each cycle's score sequence and flags any that is not
  monotonic. Fix that before committing the output.

Every regeneration must keep `Tests/CatPuzzleCoreTests/LevelLadderTests.swift`
green — it asserts the shape above (whole cycles, distinct ids, Region layouts
and solutions, the board-size pattern, a non-decreasing score inside each cycle, and
each cycle ending on its hardest level) — plus the uniqueness and
logic-only-solvability contracts in `BuiltInLogicalAnalysisTests`. It does not
rewrite the hand-authored opening levels.

## What the ladder does not do

- **No given anchors.** `ConstructiveGenerationRequest.givenAnchorCount` can
  pre-place locked cats for a gentler opening, and the app renders them, but the
  shipped ladder uses none. Difficulty comes from board selection alone.
- **No tutorial.** The guided tutorial plays before ordinary level 1. The
  ten hand-authored opening levels reinforce its three rules. The older three
  hand-authored 6x6 examples live in `SampleLevels` as test references only.
- **Only one geometry profile in practice.** The generator alternates
  `dominantBackground` and `balancedMosaic` requests, but every accepted
  candidate at 8x8-10x10 came back `dominantBackground`: `balancedMosaic`
  requires `largestRegionFraction <= 0.28` with every Region in
  `[size / 2, 2 * size]`, and the partition cascade grows small satellites
  around one large background, so at these sizes it essentially never matches
  (`RegionGeometryAnalyzer.matches`). The same cause already forced the
  `dominantBackground` Easy cap to be scaled by board size. Every shipped board
  therefore has one dominant Region plus small satellites — valid and verified,
  but structurally similar. Widening mosaic coverage at these sizes is generator
  work, not ladder work.
