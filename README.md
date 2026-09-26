# CatPuzzle

CatPuzzle is an original, logic-based iOS puzzle game in development. The
repository contains a platform-independent Swift rules engine, a deduction-guided
puzzle generator, and a playable SwiftUI MVP for iOS.

## Core rules

Boards are square and may vary in size. A valid solution has exactly one cat in
each row, column, and Region. Region membership is a rule; its rendered color
is presentation. Hand-authored levels may use disconnected Regions.
Cats may not occupy horizontally, vertically, or diagonally adjacent cells.
Levels explicitly configure their cat count and maximum allowed mistakes.

## CatPuzzleCore

`CatPuzzleCore` is a pure Swift Package with no UIKit, SwiftUI, SpriteKit, or
third-party dependencies.

- `Cell` identifies a board coordinate and its Region.
- `CellState` represents an empty, excluded, or cat cell.
- `Puzzle` validates and stores the board layout and current player state.
- `PuzzleValidator` performs side-effect-free placement, conflict, and solved
  state checks.
- `LevelDefinition` describes a level using an identifier, size, cat count,
  maximum mistakes, and Region ID grid; `BuiltInLevels` is generated offline and
  contains three ten-level cycles (30 `LevelFixture` values), each paired with
  its own verified solution. `SampleLevels` keeps the three original hand-made
  6×6 boards as a fixed reference set for tests and tooling.
- `GameState` exposes the current puzzle, mistake count, and solved/failed
  states.
- `GameEngine.setState` is the core domain operation. It validates every cat
  placement and owns atomic board changes, mistake tracking, undo history, and
  restart behavior.
- `PuzzleSolver` is the budgeted MRV-search safety net for mathematical
  solvability and uniqueness. Its report distinguishes proven outcomes from
  an inconclusive exhausted budget and includes deterministic search metrics.
  `LogicalPuzzleSolver` separately models candidates and emits deterministic,
  explainable technique events with the candidate-board snapshot after each
  event.
- `LogicalPuzzleSolver` supports `.logicOnly` for main levels and bounded
  `.challenge(maxAssumptionDepth:)` proof by contradiction. Reports retain the
  final candidate board, every accepted deduction, grouped technique events,
  assumption outcomes, and stable statistics. `PuzzleDifficultyAnalyzer`
  converts those reports into a deterministic score and tier; any report that
  used assumptions is always classified as `challenge`.

`GameEngine.toggleCell` remains a convenience adapter for the MVP interaction
cycle `empty → excluded → cat → empty`; it delegates every change to
`setState`. UI code may instead map separate gestures directly to explicit
states. Setting a cell to its current state is a no-op and does not create undo
history. An illegal cat is not placed, increments the mistake count, and does
not create undo history. After the mistake limit is reached, only Restart is
allowed; Restart clears the board, history, and mistakes.

The package accepts any square board size so later game modes can reuse the
same model. `LevelValidator` checks dimensions, cat/Region counts, and mistake
configuration without imposing Region connectivity. Every shipped level is
independently verified as both unique by `PuzzleSolver` and solvable with
zero assumptions by `LogicalPuzzleSolver`.

## Levels

One hand-authored 6×6 tutorial board comes first and teaches all three rules
across a single chain of deductions. It is played once and cannot be lost. The
opening five moves are guided — the board is masked down to the row, column or
block being explained, and only the cells the step asks for are tappable — and
then the board is handed over, with the outstanding cells pulsing if the player
stalls for three seconds. The lesson is derived from the board rather than
listed beside it, so the two cannot drift apart; see `Docs/Tutorial.md`.

After the tutorial, shipped levels form a repeating ten-level cycle — one 8×8, three 9×9, five
10×10, then a 10×10 finale built from the `hard` deduction blueprint. Three
cycles ship, and progress loops back to level 1 once all of them are complete.
The ladder is generated offline; see `Docs/LevelLadder.md` for the shape, the
regeneration command, and why the ladder orders slots by measured difficulty
rather than by the generator's own tier.

## Run tests

```bash
swift test
```

Open `CatPuzzle.xcodeproj` in Xcode to build and run the iOS app. The app starts
by offering the next unfinished built-in level. Once a level is started, every
state change is saved as compact JSON in `UserDefaults`, including mistakes.
Relaunching the app resumes that board and mistake count with fresh undo
history. Single-tap a
cell to toggle an exclusion mark; double-tap to place or remove a cat. Restart
always returns to the empty level with zero mistakes. Completing a level
advances progress to the next fixture, wrapping back to level 1 once every
level is complete; reaching the mistake limit keeps the current level active
until Restart.

The project file is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). After changing target or
project settings, regenerate it with:

```bash
xcodegen generate --spec project.yml
```

GitHub Actions runs the core tests and builds the iOS app for a generic iOS
Simulator destination on every push and pull request. The app-level
`GameViewModel` and board-border tests run through the shared `CatPuzzle` Xcode
scheme.
