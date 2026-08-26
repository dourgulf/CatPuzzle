import SwiftUI

enum CatPuzzleTheme {
    static let background = Color(
        red: 1.0,
        green: 249.0 / 255.0,
        blue: 243.0 / 255.0
    )
    static let surface = Color.white
    static let textPrimary = Color(
        red: 73.0 / 255.0,
        green: 53.0 / 255.0,
        blue: 63.0 / 255.0
    )
    static let textSecondary = Color(
        red: 128.0 / 255.0,
        green: 108.0 / 255.0,
        blue: 117.0 / 255.0
    )
    static let action = Color(
        red: 32.0 / 255.0,
        green: 185.0 / 255.0,
        blue: 107.0 / 255.0
    )
    static let warning = Color(
        red: 1.0,
        green: 112.0 / 255.0,
        blue: 79.0 / 255.0
    )
    static let divider = Color(
        red: 233.0 / 255.0,
        green: 222.0 / 255.0,
        blue: 215.0 / 255.0
    )

    private static let groupColors: [Color] = [
        Color(red: 237.0 / 255.0, green: 134.0 / 255.0, blue: 213.0 / 255.0),
        Color(red: 56.0 / 255.0, green: 170.0 / 255.0, blue: 112.0 / 255.0),
        Color(red: 244.0 / 255.0, green: 207.0 / 255.0, blue: 104.0 / 255.0),
        Color(red: 93.0 / 255.0, green: 131.0 / 255.0, blue: 180.0 / 255.0),
        Color(red: 174.0 / 255.0, green: 118.0 / 255.0, blue: 84.0 / 255.0),
        Color(red: 137.0 / 255.0, green: 207.0 / 255.0, blue: 120.0 / 255.0),
    ]

    private static let groupSymbols = [
        "circle.fill",
        "triangle.fill",
        "square.fill",
        "diamond.fill",
        "star.fill",
        "hexagon.fill",
    ]

    static func groupColor(for colorID: Int) -> Color {
        groupColors[normalizedIndex(for: colorID)]
    }

    static func groupSymbol(for colorID: Int) -> String {
        groupSymbols[normalizedIndex(for: colorID)]
    }

    static func groupName(for colorID: Int) -> String {
        "Group \(normalizedIndex(for: colorID) + 1)"
    }

    static func markerColor(for colorID: Int) -> Color {
        switch normalizedIndex(for: colorID) {
        case 3, 4:
            .white
        default:
            textPrimary
        }
    }

    private static func normalizedIndex(for colorID: Int) -> Int {
        let count = groupColors.count
        return ((colorID % count) + count) % count
    }
}

struct RootView: View {
    @ObservedObject var session: AppSession
    @State private var showPlaytestLab = false

    var body: some View {
        ZStack {
            CatPuzzleTheme.background
                .ignoresSafeArea()

            switch session.destination {
            case .playing:
                if let viewModel = session.gameViewModel {
                    GameScreen(
                        viewModel: viewModel,
                        onContinue: session.continueAfterCompletion
                    )
                }
            case .readyForNextLevel:
                if let level = session.nextLevel {
                    NextLevelScreen(
                        levelName: level.id.capitalized,
                        onStart: session.startNextLevel
                    )
                }
            case .allCompleted:
                AllLevelsCompleteView()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            playtestLabEntryButton
        }
        .foregroundStyle(CatPuzzleTheme.textPrimary)
        .fontDesign(.rounded)
        .tint(CatPuzzleTheme.action)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showPlaytestLab) {
            PlaytestLabScreen()
        }
    }

    /// Dev-only shortcut into `PlaytestLabScreen` for trying out
    /// `PuzzleGenerator` candidates. Always visible — `AppSession` resumes
    /// straight into `.playing` on launch whenever a `SavedGame` exists
    /// (even a freshly-restarted, all-empty one), so hiding this during
    /// `.playing` would make it unreachable most of the time in practice.
    /// Placed bottom-trailing via `.overlay` (not the `ZStack`'s own
    /// alignment) so it doesn't disturb the centering of screens like
    /// `NextLevelScreen` that don't fill the frame themselves, and so it
    /// clears `GameScreen`'s top-trailing mistake-count badge.
    private var playtestLabEntryButton: some View {
        Button {
            showPlaytestLab = true
        } label: {
            Image(systemName: "flask.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CatPuzzleTheme.textSecondary)
                .padding(10)
                .background(CatPuzzleTheme.surface, in: Circle())
                .shadow(color: CatPuzzleTheme.textPrimary.opacity(0.10), radius: 8, y: 4)
        }
        .padding(16)
        .accessibilityLabel("Puzzle Lab")
        .accessibilityIdentifier("open-playtest-lab")
    }
}
