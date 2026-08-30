# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Architecture

CatPuzzle is a "one cat per row/column/Region, no adjacent cats" logic puzzle. The codebase is split into two strictly separated layers:

- **`Sources/CatPuzzleCore`** — a pure Swift Package (no UIKit/SwiftUI/SpriteKit/third-party deps) holding the entire rules engine. This boundary is load-bearing: nothing in this target may import a UI framework.
- **`CatPuzzleApp`** — the SwiftUI app: screens, `GameViewModel`, persistence, sound, and gesture handling. UI code never re-implements game rules; it calls into `GameEngine`/`GameViewModel` domain APIs.

### Core domain flow (`Sources/CatPuzzleCore`)

- `Cell` / `CellState` — board coordinate + Region, and the three-state cell value (empty/excluded/cat).
- `Puzzle` — stores the board layout and current player state; `PuzzleValidator` does side-effect-free placement/conflict/solved checks against it.
- `LevelDefinition` — id, size, cat count, max mistakes, Region-ID grid. `BuiltInLevels` ships three verified 6×6 `LevelFixture`s (each paired with a known-correct solution). `LevelValidator` checks a definition's internal consistency (dimensions, cat/Region counts, mistake config) without imposing Region connectivity.
- `GameEngine.setState` is the single core domain operation: every cat placement is validated here, and it atomically owns board mutation, mistake tracking, undo history, and restart. `GameEngine.toggleCell` is a convenience adapter over `setState` implementing the MVP cycle `empty → excluded → cat → empty`; UI is free to call `setState` directly for other gesture mappings instead. Setting a cell to its current state is a no-op (no undo entry). An illegal cat placement is rejected, increments mistakes, and does not create undo history. Once the mistake limit is hit, only Restart is allowed.
- `GameState` — read-only snapshot exposed to callers: current puzzle, mistake count, solved/failed flags.
- Two independent solvers exist for different purposes:
  - `PuzzleSolver` — backtracking search used as the safety net proving a level is mathematically solvable and has a unique solution.
  - `LogicalPuzzleSolver` — models per-cell candidates and emits deterministic, explainable step-by-step deductions (row/column/Region/confirmed-cat propagation). Supports `.logicOnly` (used for the shipped levels) and bounded `.challenge(maxAssumptionDepth:)` proof-by-contradiction. Any report that required an assumption is classified as `challenge`.
  - `PuzzleDifficultyAnalyzer` turns a `LogicalPuzzleSolver` report into a deterministic score/tier.

### App layer (`CatPuzzleApp`)

- `AppSession` is the top-level `ObservableObject` router: on launch it loads `GameProgress` from `GameProgressStore`, rebuilds a `GameEngine` from any in-progress `SavedGame`, and routes between `.playing` / `.readyForNextLevel` / `.allCompleted` (`AppDestination`). It persists progress on every `GameState` change via a callback from `GameViewModel`.
- `GameProgressStore` is a protocol; `UserDefaultsGameProgressStore` is the concrete `UserDefaults`-backed implementation, JSON-encoding `GameProgress` (completed level IDs + active `SavedGame`). Tests must inject a fake/in-memory store — never touch `UserDefaults.standard` directly (see AGENTS.md testing guidance).
- `GameViewModel` wraps a `GameEngine` instance for one active level, publishing `puzzle`, `canUndo`, `isSolved`, `isFailed`, `mistakeCount`, `feedbackMessage`, and `previewStates` (for drag-marking) to SwiftUI. It also owns `CellTapInterpreter`, a small state machine that resolves single-tap-vs-double-tap-within-interval into an exclusion toggle vs. a cat placement, without desyncing from `GameEngine`'s undo history.
- `LevelProgression` maps the ordered `BuiltInLevels` list against a set of completed IDs to find the next unfinished level.
- `BoardView`/`CellView`/`GameScreen` render the puzzle and translate taps/drags into `GameViewModel` calls (drag-to-mark-exclusions, drag-to-clear-exclusions — see DESIGN.md for exact interaction semantics). `PuzzleSound` plays distinct mark/unmark SFX from `CatPuzzleApp/Sounds/`.

### Design reference

`DESIGN.md` defines the semantic color tokens, typography, per-cell-state visuals, and interaction rules (tap/drag/double-tap timing, accessibility requirements) that UI changes must follow — read it before touching `BoardView`, `CellView`, or `GameScreen`.
