# First Ten Ordinary Levels

The guided tutorial introduces the rules. Ordinary levels 1–10 then let the
player use them without prompts. Their color-block layouts and solutions are
hand-authored in `Sources/CatPuzzleCore/OpeningLevels.swift`; the generator
does not change them.

Every row, column, and color block contains exactly one cat. Cats also cannot
touch in any of the eight directions. Because the row and column counts must
match, these boards grow from 6×6 through 7×7 to 8×8. A 6×7 or 6×8 board
cannot satisfy the current “one in **every** row and column” rule.

| Level | Size | Solution: cat column in rows 1…N | Direct practice |
| --- | --- | --- | --- |
| 1 | 6×6 | 1, 3, 5, 2, 4, 6 | Start with a one-cell block; use diagonal exclusion, then rows and columns across wider blocks. |
| 2 | 6×6 | 6, 4, 2, 5, 3, 1 | A vertical block uses the filled row; the next horizontal block uses no touching. |
| 3 | 6×6 | 2, 4, 6, 1, 3, 5 | Alternate diagonal and row exclusions. |
| 4 | 6×6 | 5, 3, 1, 6, 4, 2 | Resolve color blocks that cross rows. |
| 5 | 7×7 | 1, 3, 5, 7, 2, 4, 6 | Extend the same direct chain over seven rows. |
| 6 | 7×7 | 7, 5, 3, 1, 6, 4, 2 | Work from the opposite side; clear a wider middle block. |
| 7 | 7×7 | 2, 4, 6, 1, 3, 5, 7 | An occupied column resolves the blue block in the fourth row. |
| 8 | 8×8 | 1, 3, 5, 7, 2, 4, 6, 8 | An occupied column removes a blue candidate beyond the nearest cat's touching range. |
| 9 | 8×8 | 8, 6, 4, 2, 7, 5, 3, 1 | Read a reflected path, using the other corners. |
| 10 | 8×8 | 2, 4, 6, 8, 1, 3, 5, 7 | Settle seven small blocks directly, then place the last cat in the unused row and column. |

Each level has one unique solution. The logical solver completes every board
using only single-candidate placements and their immediate row, column, color,
and touching exclusions. No assumption, locked set, common attack, or strong
link is used. `OpeningLevelsTests` checks those properties and verifies that
every color block is connected.

After level 10, play continues into the existing generated 8×8–10×10 ladder.
Completing all 40 ordinary levels starts a fresh lap at level 1.

## Simulator playtest

On 2026-09-26, the author played levels 1–10 in order on an iPhone 16
simulator (iOS 26.5) using `sim-use`. Each board was read from the displayed
colors and solved by direct row, column, color-block, and no-touch deductions.
After the first run showed that columns seldom mattered before the final cat,
levels 7 and 8 were adjusted and the final ladder was played again. In the
revised boards, the column rule uniquely settles a color block after the
first three cats. All ten final levels finished with **0 mistakes and no
hints**. The 10→11 transition showed level 11 as an 8×8 board.

The 6×6, 7×7, and 8×8 boards fit on screen and their colors were
distinguishable. Every board begins with a one-cell block and proceeds
through a similar chain. In most levels, the column rule is most visible
when identifying the last cat; levels 7 and 8 require it earlier.
This self-play verifies a direct path through every board, but does not
measure how quickly a new player recognizes that path.
