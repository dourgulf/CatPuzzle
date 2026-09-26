# Languages

Settings → Language offers Follow System, 简体中文, and English. The selection
is stored in `GameProgress.language`; older saves and unknown future values
fall back to Follow System without discarding game progress.

`RootView` supplies the resolved locale to the whole view hierarchy, including
settings and other sheets. Switching language preserves the active view model,
board, and tutorial step. System selection is refreshed when the app becomes
active; unsupported system languages fall back to English.

`CatPuzzleApp/Localizable.xcstrings` contains English and Simplified Chinese.
SwiftUI literal text uses the locale environment. Known runtime text keys are
explicitly catalogued and displayed through `LocalizedStringKey`. Formatted
model descriptions use `L10n` with an explicit locale and arguments, so changing
languages also updates a visible hint or import error. Keep format arguments
in both translations; use numbered placeholders when Chinese reorders them.

`AppLanguageTests` covers locale resolution, explicit overrides, old-save
migration, persistence, preserving an in-progress tutorial, and translated
resource/format lookups. Test persistence uses an isolated UserDefaults suite.
