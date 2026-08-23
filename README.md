# CatPuzzle

CatPuzzle is an original, logic-based iOS puzzle game in development. The
repository contains a platform-independent Swift rules engine and a playable
SwiftUI MVP for iOS. It does not yet include a puzzle generator.

## Core rules

The first supported board size is 6×6. A valid solution has exactly one cat in
each row, column, and region. Cats may not occupy horizontally, vertically, or
diagonally adjacent cells.

## CatPuzzleCore

`CatPuzzleCore` is a pure Swift Package with no UIKit, SwiftUI, SpriteKit, or
third-party dependencies.

- `Cell` identifies a board coordinate and its region.
- `CellState` represents an empty, excluded, or cat cell.
- `Puzzle` validates and stores the board layout and current player state.
- `PuzzleValidator` performs side-effect-free placement, conflict, and solved
  state checks.
- `LevelDefinition` describes a level using an identifier, size, and region ID
  grid; `BuiltInLevels` contains three original 6×6 `LevelFixture` values, each
  paired with its own verified solution.
- `GameState` exposes the current puzzle and solved state.
- `GameEngine.setState` is the core domain operation. It validates every cat
  placement and owns atomic state changes, undo history, and restart behavior.

`GameEngine.toggleCell` remains a convenience adapter for the MVP interaction
cycle `empty → excluded → cat → empty`; it delegates every change to
`setState`. UI code may instead map separate gestures directly to explicit
states. Setting a cell to its current state is a no-op and does not create undo
history. Rejected operations leave both the board and history unchanged.

The package accepts any square board size so later game modes can reuse the
same model. Level data is responsible for supplying a valid region layout;
region contiguity is outside the first-phase validator scope.

## Run tests

```bash
swift test
```

Open `CatPuzzle.xcodeproj` in Xcode to build and run the iOS app. The app starts
by offering the next unfinished built-in level. Once a level is started, every
successful board change is saved as compact JSON in `UserDefaults`. Relaunching
the app automatically resumes that board with fresh undo history. Single-tap a
cell to toggle an exclusion mark; double-tap to place or remove a cat. Restart
always returns to the empty level, and completing a level advances progress to
the next fixture.

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
