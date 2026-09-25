# Tutorial

One hand-authored 6x6 board teaches all three rules, played once ever before
the generated ladder starts. The board lives in
`Sources/CatPuzzleCore/TutorialLevels.swift`; the lesson walked across it is
`Sources/CatPuzzleCore/TutorialScript.swift`.

## Why one board and not three

The rules only become useful where they meet. A block runs out of room
*because* a row was settled; the next block runs out of room *because* a cat
refused a neighbour. Three separate boards can only show each rule working
alone, and each one has to re-teach the board from scratch. One board lets the
lesson be a single chain of deductions the player watches turn into a habit.

It also removes the constraint that shaped the old three-board tutorial: a
board could not *need* a rule it had not taught yet, which forced pre-placed
cats to carry the uniqueness. This board has no givens at all — its Region
layout alone has exactly one answer, so `PuzzleSolver` certifies it like any
shipped level.

## The lesson

The script is **derived from the board**, not listed next to it, so the two
cannot drift apart. `TutorialScript.build` walks a five-step curriculum and
then hands over:

| Step | Coaching | Rule | Move |
| --- | --- | --- | --- |
| 1 | guided | Regions | The pink block is a single cell — its cat goes there |
| 2 | guided | Rows | That row has its cat, so the rest of it is out |
| 3 | guided | Columns | And so is the rest of that column |
| 4 | guided | Regions | Which leaves the green block exactly one cell |
| 5 | guided | No touching | So the cells around that new cat are out |
| 6+ | discovery | all three | The player runs the loop themselves |

Steps 1 and 4 are the same rule on purpose. The first is free — a one-cell
block needs no deduction to see. The second is the same rule arrived at, and it
only works because steps 2 and 3 emptied the block out. That is the moment the
tutorial exists for.

From step 6 the script is just the loop the rest of the game is played in:
mark everything the cats on the board rule out, then place the cat some block,
row or column has been narrowed down to. On this board every one of those
placements happens to be a block running out of room, which keeps reinforcing
the rule that does the most work.

### Guided versus discovery

A **guided** step masks the board down to its `spotlight` — the whole row,
column or block the lesson is about, so the player sees the reason and not just
the answer — and leaves only the cells it is actually asking for tappable. The
move cannot be got wrong, and neither can the ones before it be undone.

A **discovery** step masks nothing and points at nothing. If the player sits on
it for three seconds without marking anything, the cells still outstanding
pulse (`GameViewModel.tutorialNudge`). Every mark restarts that delay, so
somebody who is working is never interrupted; once a step has nudged, later
marks in the same step re-show it immediately rather than making the player
wait the delay out again.

## Where the player is in the script

`TutorialCoach.currentStepIndex(for:)` returns **the first step the board does
not already satisfy**, recomputed from the board on every change rather than
counted up. Restarting the level, resuming it a week later, and clearing a mark
during the discovery phase all land on the right step with no bookkeeping that
could fall out of sync with `GameEngine`.

Clearing a mark an earlier step asked for therefore reopens that step, mask and
all. During the guided phase the mask makes that impossible in the first place.

## Challenge mode, and why

The tutorial is played in **challenge mode**, whatever the player prefers.
Challenge mode refuses a cat that is not in the solution instead of letting it
land — and a wrong cat left on the board would leave every later step pointing
at a deduction that is no longer there. The preference the player sets during
the tutorial is remembered and applies to the next real level.

It still cannot be lost: `maxMistakes` is 9,999 and `GameScreen` hides the
mistake counter on a tutorial. The Hint button is hidden too — the tutorial
already *is* a hint, step by step, and a hint preview would fight with the
step's own mask. Undo is absent because challenge mode has none; every
exclusion is undone by tapping it again.

## A board that cannot teach

`TutorialScript.build` returns an empty script rather than inventing a lesson
when the board does not fit the curriculum — no single-cell Region, pre-placed
cats, no Region left with one cell after step 3, and so on. `GameViewModel`
then plays the level uncoached instead of pointing at deductions that are not
there. `TutorialLevelTests` rules this out for the shipped board and checks the
fallback with boards that deliberately do not fit.

## What the tests pin down

`Tests/CatPuzzleCoreTests/TutorialLevelTests.swift`:

- The board is 6x6 with no givens, has exactly one solution, and needs nothing
  beyond the three rules — no locked sets, common attacks or strong links.
- No step ever asks for a move that contradicts the solution, every cell is
  asked for exactly once, and following every step in order solves the board
  with zero mistakes.
- The opening five steps are the curriculum above, in that order, covering all
  three rules; coaching only ever falls away, never comes back; guided steps
  spotlight more than their own answer; discovery steps mask nothing.

`CatPuzzleAppTests/TutorialFlowTests.swift` covers the app side: the masking,
the step advancing and reopening, restart, resume, the nudge delay, challenge
mode refusing a wrong cat, and the progression rules below.

## Progression

`AppSession` offers the unfinished tutorial before anything else.
`GameProgress.completedTutorialIDs` is kept separate from `completedLevelIDs`
because the latter is cleared every time the ladder loops — without the split,
every lap would replay the introduction. Progress saved before the tutorial
existed decodes as "tutorial already finished", so existing players are not
sent back to square one by the update.

In debug builds only, Settings → Debug → **Reset Tutorial**
(`AppSession.resetTutorial`) forgets `completedTutorialIDs` and offers the
tutorial again, so the lesson can be replayed while it is being worked on
without wiping the install. It drops any game in progress — a saved game left
behind would be resumed on the next launch and route straight past the thing
the reset just re-offered — but leaves finished ladder levels alone.
