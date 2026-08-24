# Repository Guidelines

## Project Structure & Module Organization

- `Sources/CatPuzzleCore/` contains the platform-independent rules engine, level models, validators, solvers, and difficulty analysis. Keep this target free of SwiftUI, UIKit, persistence, and third-party frameworks.
- `Tests/CatPuzzleCoreTests/` contains Swift Package XCTest coverage for core behavior.
- `CatPuzzleApp/` contains the SwiftUI application, session/progress persistence, screens, and interaction adapters.
- `CatPuzzleAppTests/` covers app-layer state, persistence, view-model behavior, and board helpers.
- `project.yml` is the source of truth for the Xcode project; `.github/workflows/test.yml` defines CI.

## Build, Test, and Development Commands

```bash
swift test
```

Builds `CatPuzzleCore` and runs all package tests.

```bash
xcodebuild -project CatPuzzle.xcodeproj -scheme CatPuzzle \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Builds the iOS app without requiring signing. Run app tests from Xcode or select an available simulator dynamically with `xcrun simctl`, then use `xcodebuild ... -only-testing:CatPuzzleAppTests test`. After changing targets or build settings, run `xcodegen generate --spec project.yml` and review the generated project diff.

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift API Design Guidelines. Types use `UpperCamelCase`; properties, methods, and enum cases use `lowerCamelCase`. Prefer value types and explicit domain operations in the core. Keep validators and solvers deterministic and side-effect free. UI gestures belong in the app layer and should call `GameViewModel` or `GameEngine` domain APIs. No formatter or linter is currently enforced; match surrounding code and run `git diff --check`.

## Testing Guidelines

Use XCTest and name tests `testExpectedBehavior`, for example `testIllegalCatPlacementPreservesPuzzle`. Add focused regression tests for every rule or interaction change, including failure and no-op paths. Run both `swift test` and `CatPuzzleAppTests` before submitting. Tests must isolate persistence; never use `UserDefaults.standard` directly.

## Commit & Pull Request Guidelines

Write concise, imperative commits such as `Improve cell tap responsiveness`. Develop on a focused feature or fix branch, not `main`. PRs should explain behavior and architecture changes, list exact test commands/results, and include screenshots for visible UI changes. Keep unrelated files unstaged, ensure GitHub Actions is green, and merge only after review readiness is confirmed.
