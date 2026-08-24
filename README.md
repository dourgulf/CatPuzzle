# CatPuzzle

CatPuzzle is an original, logic-based iOS puzzle game in development. The
repository contains a platform-independent Swift rules engine and a playable
SwiftUI MVP for iOS. It does not yet include a puzzle generator.

## Core rules

Boards are square and may vary in size. A valid solution has exactly one cat in
each row, column, and color group. A color may appear in disconnected cells.
Cats may not occupy horizontally, vertically, or diagonally adjacent cells.
Levels explicitly configure their cat count and maximum allowed mistakes.

## CatPuzzleCore

`CatPuzzleCore` is a pure Swift Package with no UIKit, SwiftUI, SpriteKit, or
third-party dependencies.

- `Cell` identifies a board coordinate and its color group.
- `CellState` represents an empty, excluded, or cat cell.
- `Puzzle` validates and stores the board layout and current player state.
- `PuzzleValidator` performs side-effect-free placement, conflict, and solved
  state checks.
- `LevelDefinition` describes a level using an identifier, size, cat count,
  maximum mistakes, and color ID grid; `BuiltInLevels` contains three original
  6×6 `LevelFixture` values, each paired with its own verified solution.
- `GameState` exposes the current puzzle, mistake count, and solved/failed
  states.
- `GameEngine.setState` is the core domain operation. It validates every cat
  placement and owns atomic board changes, mistake tracking, undo history, and
  restart behavior.
- `PuzzleSolver` is the backtracking safety net for mathematical solvability
  and uniqueness. `LogicalPuzzleSolver` separately models candidates and emits
  deterministic, explainable placement/exclusion steps using row, column,
  color, and confirmed-cat propagation rules.
- `LogicalPuzzleSolver` supports `.logicOnly` for main levels and bounded
  `.challenge(maxAssumptionDepth:)` proof by contradiction. Reports retain the
  final candidate board, every accepted deduction, assumption outcomes, and
  stable statistics. `PuzzleDifficultyAnalyzer` converts those reports into a
  deterministic score and tier; any report that used assumptions is always
  classified as `challenge`.

`GameEngine.toggleCell` remains a convenience adapter for the MVP interaction
cycle `empty → excluded → cat → empty`; it delegates every change to
`setState`. UI code may instead map separate gestures directly to explicit
states. Setting a cell to its current state is a no-op and does not create undo
history. An illegal cat is not placed, increments the mistake count, and does
not create undo history. After the mistake limit is reached, only Restart is
allowed; Restart clears the board, history, and mistakes.

The package accepts any square board size so later game modes can reuse the
same model. `LevelValidator` checks dimensions, cat/color counts, and mistake
configuration without imposing color connectivity. The three built-in levels
are independently verified as both unique by `PuzzleSolver` and solvable with
zero assumptions by `LogicalPuzzleSolver`.

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
advances progress to the next fixture; reaching the mistake limit keeps the
current level active until Restart.

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
