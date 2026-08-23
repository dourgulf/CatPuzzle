# CatPuzzle

CatPuzzle is an original, logic-based iOS puzzle game in development. This
repository currently contains the platform-independent Swift rules engine; it
does not yet include an iOS user interface or a puzzle generator.

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
  grid; `BuiltInLevels` contains three original 6×6 fixtures.
- `GameState` exposes the current puzzle and solved state.
- `GameEngine` owns cell transitions, validates every cat placement, and
  supports undo and restart.

Cell interaction cycles through `empty → excluded → cat → empty`. A rejected
cat placement leaves both the board and undo history unchanged.

The package accepts any square board size so later game modes can reuse the
same model. Level data is responsible for supplying a valid region layout;
region contiguity is outside the first-phase validator scope.

## Run tests

```bash
swift test
```

GitHub Actions runs the same command for every push and pull request.
