import SwiftUI

/// The tutorial's own dark, spotlighted color system — a separate namespace
/// from `CatPuzzleTheme` rather than new cases mixed into it, so a call site
/// makes clear which screen a token belongs to. `TutorialScreen` is the one
/// screen exempted from the app's forced-light lock; see the
/// "Tutorial (Dark) Color System" section of `DESIGN.md`.
enum TutorialTheme {
    static let background = Color(red: 0.07, green: 0.075, blue: 0.09)
    /// Keep earlier crosses readable outside the current row, column or
    /// block, so each lesson still looks like the same evolving board.
    static let scrim = Color.black.opacity(0.25)
    static let surface = Color(red: 0.16, green: 0.16, blue: 0.19)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    /// Reused from the brand palette rather than a new dark-only accent, so
    /// "Start Game" on the graduation page reads as the same action color the
    /// player is about to meet on every ladder level.
    static let accent = CatPuzzleTheme.action
    static let spotlightRing = Color.white.opacity(0.9)
    static let celebration = Color(red: 1.0, green: 0.78, blue: 0.35)
}
