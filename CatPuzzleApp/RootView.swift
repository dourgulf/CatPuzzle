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

    private static let regionColors: [Color] = [
        Color(red: 237.0 / 255.0, green: 134.0 / 255.0, blue: 213.0 / 255.0),
        Color(red: 56.0 / 255.0, green: 170.0 / 255.0, blue: 112.0 / 255.0),
        Color(red: 244.0 / 255.0, green: 207.0 / 255.0, blue: 104.0 / 255.0),
        Color(red: 93.0 / 255.0, green: 131.0 / 255.0, blue: 180.0 / 255.0),
        Color(red: 174.0 / 255.0, green: 118.0 / 255.0, blue: 84.0 / 255.0),
        Color(red: 137.0 / 255.0, green: 207.0 / 255.0, blue: 120.0 / 255.0),
        Color(red: 1.0, green: 153.0 / 255.0, blue: 85.0 / 255.0),
        Color(red: 136.0 / 255.0, green: 119.0 / 255.0, blue: 216.0 / 255.0),
        Color(red: 73.0 / 255.0, green: 191.0 / 255.0, blue: 207.0 / 255.0),
        Color(red: 239.0 / 255.0, green: 105.0 / 255.0, blue: 112.0 / 255.0),
    ]

    private static let regionSymbols = [
        "circle.fill",
        "triangle.fill",
        "square.fill",
        "diamond.fill",
        "star.fill",
        "hexagon.fill",
        "heart.fill",
        "moon.fill",
        "cloud.fill",
        "bolt.fill",
    ]

    static func regionColor(for regionID: Int) -> Color {
        regionColors[normalizedIndex(for: regionID)]
    }

    static func regionSymbol(for regionID: Int) -> String {
        regionSymbols[normalizedIndex(for: regionID)]
    }

    static func regionName(for regionID: Int) -> String {
        "Region \(regionID + 1)"
    }

    static func markerColor(for regionID: Int) -> Color {
        switch normalizedIndex(for: regionID) {
        case 3, 4, 7:
            .white
        default:
            textPrimary
        }
    }

    private static func normalizedIndex(for regionID: Int) -> Int {
        let count = regionColors.count
        return ((regionID % count) + count) % count
    }
}

struct RootView: View {
    @ObservedObject var session: AppSession
    @State private var presentedSheet: PresentedSheet?

    var body: some View {
        ZStack {
            CatPuzzleTheme.background
                .ignoresSafeArea()

            switch session.destination {
            case .playing:
                if let viewModel = session.gameViewModel {
                    GameScreen(
                        viewModel: viewModel,
                        showsRegionIcons: session.showsRegionIcons,
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
        .overlay(alignment: .topTrailing) {
            settingsEntryButton
        }
        .foregroundStyle(CatPuzzleTheme.textPrimary)
        .fontDesign(.rounded)
        .tint(CatPuzzleTheme.action)
        .preferredColorScheme(.light)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .settings:
                SettingsScreen(
                    session: session,
                    onOpenLab: { presentedSheet = .lab }
                )
            case .lab:
                PlaytestLabScreen(
                    showsRegionIcons: session.showsRegionIcons
                )
            }
        }
    }

    private var settingsEntryButton: some View {
        Button {
            presentedSheet = .settings
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CatPuzzleTheme.textSecondary)
                .padding(10)
                .background(CatPuzzleTheme.surface, in: Circle())
                .shadow(color: CatPuzzleTheme.textPrimary.opacity(0.10), radius: 8, y: 4)
        }
        .padding(16)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("open-settings")
    }
}

private enum PresentedSheet: String, Identifiable {
    case settings
    case lab

    var id: String { rawValue }
}

private struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: AppSession
    let onOpenLab: () -> Void

    @State private var showsRestartConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                gameplaySection
                boardSection
                actionsSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Restart this level?",
                isPresented: $showsRestartConfirmation
            ) {
                Button("Restart", role: .destructive) {
                    session.restartCurrentGame()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your current board and mistake count will be cleared.")
            }
        }
    }

    private var gameplaySection: some View {
        Section {
            Toggle("Challenge Mode", isOn: challengeModeBinding)
                .accessibilityIdentifier("challenge-mode-toggle")

        } header: {
            Text("Gameplay")
        } footer: {
            Text(modeDescription)
        }
    }

    private var boardSection: some View {
        Section("Board") {
            Toggle("Show Region Icons", isOn: regionIconsBinding)
                .accessibilityIdentifier("region-icons-toggle")
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            if session.gameViewModel != nil {
                Button("Restart Level", systemImage: "arrow.clockwise") {
                    showsRestartConfirmation = true
                }
                .foregroundStyle(CatPuzzleTheme.warning)
                .accessibilityIdentifier("restart-level-setting")
            }

            Button("Puzzle Lab", systemImage: "flask.fill") {
                onOpenLab()
            }
            .accessibilityIdentifier("open-playtest-lab")
        }
    }

    private var challengeModeBinding: Binding<Bool> {
        Binding(
            get: { session.gameplayMode == .challenge },
            set: {
                session.setGameplayMode($0 ? .challenge : .exploration)
            }
        )
    }

    private var regionIconsBinding: Binding<Bool> {
        Binding(
            get: { session.showsRegionIcons },
            set: { session.setShowsRegionIcons($0) }
        )
    }

    private var modeDescription: String {
        switch session.gameplayMode {
        case .exploration:
            "Explore freely and undo moves. Cat placements only need to follow the puzzle rules."
        case .challenge:
            "Wrong cat placements cost a mistake, and Undo is disabled."
        }
    }
}
