import CatPuzzleCore
import PhotosUI
import SwiftUI

/// Pick a screenshot of a board — this app's or another one's — and carry on
/// playing it here, marks and all.
///
/// Nothing about a screenshot can be trusted, so the import proves the board
/// before offering it: `ScreenshotLevelImporter` certifies that the Region
/// layout has exactly one solution and reconciles the marks against it. An
/// imported game is therefore always winnable from where it starts. It is
/// also a scratch game — it never touches level progress.
struct ScreenshotImportScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    let mode: GameplayMode
    let showsRegionIcons: Bool

    @State private var selection: PhotosPickerItem?
    @State private var state: ImportState = .idle

    var body: some View {
        NavigationStack {
            List {
                pickerSection
                switch state {
                case .idle:
                    EmptyView()
                case .working:
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Reading the board…")
                                .foregroundStyle(CatPuzzleTheme.textSecondary)
                        }
                    }
                case let .failed(error):
                    Section {
                        Text(ScreenshotImportCopy.message(for: error, locale: locale))
                            .foregroundStyle(CatPuzzleTheme.warning)
                            .accessibilityIdentifier("screenshot-import-error")
                    }
                case let .ready(imported):
                    boardSection(imported)
                    playSection(imported)
                }
            }
            .navigationTitle("Play from Screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(for: ImportedGame.self) { game in
                ScreenshotPlayView(
                    imported: game.imported,
                    mode: mode,
                    showsRegionIcons: showsRegionIcons
                )
            }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                load(item)
            }
        }
    }

    private var pickerSection: some View {
        Section {
            PhotosPicker(
                selection: $selection,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Choose Screenshot", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("choose-screenshot")
        } footer: {
            Text(
                "Pick a screenshot of a puzzle board. Cats and ✕ marks already on it are carried over, so you can keep going where the screenshot left off."
            )
        }
    }

    private func boardSection(_ imported: ImportedScreenshotLevel) -> some View {
        Section("Board") {
            ScreenshotBoardPreview(
                puzzle: imported.puzzle,
                showsRegionIcons: showsRegionIcons
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            LabeledContent(
                "Size",
                value: "\(imported.level.size) × \(imported.level.size)"
            )
            LabeledContent("Marks carried over", value: markSummary(imported))
            if imported.hasCorrections {
                Text(correctionSummary(imported))
                    .font(.footnote)
                    .foregroundStyle(CatPuzzleTheme.warning)
                    .accessibilityIdentifier("screenshot-import-corrections")
            }
        }
    }

    private func playSection(_ imported: ImportedScreenshotLevel) -> some View {
        Section {
            NavigationLink(value: ImportedGame(imported: imported)) {
                Label(
                    LocalizedStringKey(imported.isAlreadySolved ? "Open Board" : "Continue Playing"),
                    systemImage: "play.fill"
                )
            }
            .accessibilityIdentifier("play-screenshot")
        } footer: {
            Text(
                LocalizedStringKey(imported.isAlreadySolved
                    ? "This board is already complete — every cat is placed."
                    : "This board is a one-off and is not saved to your level progress.")
            )
        }
    }

    private func markSummary(_ imported: ImportedScreenshotLevel) -> String {
        let cats = imported.puzzle.states.count { $0 == .cat }
        let excluded = imported.puzzle.states.count { $0 == .excluded }
        return L10n.format("%@ cats, %@ ✕", [String(cats), String(excluded)], locale: locale)
    }

    private func correctionSummary(_ imported: ImportedScreenshotLevel) -> String {
        L10n.format("Cleared %@ incorrect cats and %@ incorrect marks.",
                    [String(imported.discardedCats.count), String(imported.discardedExclusions.count)], locale: locale)
    }

    private func load(_ item: PhotosPickerItem) {
        state = .working
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    state = .failed(ScreenshotPixelDecoder.DecodeError.unreadableImage)
                    return
                }
                // Decoding and the uniqueness proof are both heavy enough to
                // drop frames on a large screenshot; keep them off the main
                // actor so the spinner above actually spins.
                let imported = try await Task.detached(priority: .userInitiated) {
                    try ScreenshotLevelImporter.makeLevel(
                        from: try ScreenshotPixelDecoder.decode(data)
                    )
                }.value
                state = .ready(imported)
            } catch {
                state = .failed(error)
            }
        }
    }
}

private enum ImportState {
    case idle
    case working
    case failed(any Error)
    case ready(ImportedScreenshotLevel)
}

private struct ImportedGame: Hashable {
    let id = UUID()
    let imported: ImportedScreenshotLevel

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Player-facing wording for every way an import can fail. Each one says what
/// the screenshot looked like and what to do about it — "invalid image" tells
/// the player nothing they can act on.
enum ScreenshotImportCopy {
    static let unreadable =
        "That image could not be opened. Try picking the screenshot again."

    static func message(for error: any Error, locale: Locale = Locale(identifier: "en")) -> String {
        switch error {
        case let error as ScreenshotImportError:
            message(for: error, locale: locale)
        case is ScreenshotPixelDecoder.DecodeError:
            L10n.text(unreadable, locale: locale)
        default:
            L10n.text("Something went wrong reading that screenshot.", locale: locale)
        }
    }

    static func message(for error: ScreenshotImportError, locale: Locale = Locale(identifier: "en")) -> String {
        switch error {
        case let .transcription(reason):
            message(for: reason, locale: locale)
        case .invalidLevel:
            L10n.text("The colors on that board did not come out as one Region per row. A screenshot taken straight from the puzzle, without anything drawn over it, reads best.", locale: locale)
        case .noSolution:
            L10n.text("That board has no solution, so it was probably read wrong. Try a screenshot of the full board with nothing covering it.", locale: locale)
        case .multipleSolutions:
            L10n.text("That board has more than one solution, so it cannot be played here. Check that no part of it is cut off.", locale: locale)
        case .searchInconclusive:
            L10n.text("That board was too large to check for a single solution.", locale: locale)
        }
    }

    static func message(for error: ScreenshotTranscriptionError, locale: Locale = Locale(identifier: "en")) -> String {
        switch error {
        case .boardNotFound:
            L10n.text("No puzzle board was found in that screenshot.", locale: locale)
        case .nonSquareGrid:
            L10n.text("The board in that screenshot is not square — part of it may be cut off or covered.", locale: locale)
        case let .unsupportedBoardSize(size):
            L10n.format("That board is %@ × %@. Boards from 4 × 4 to 12 × 12 can be imported.", [String(size), String(size)], locale: locale)
        case let .regionCountMismatch(regions, size):
            L10n.format("That board is %@ × %@ but %@ colors were read from it. Screenshots taken at full brightness, with no overlay or color filter, read best.", [String(size), String(size), String(regions)], locale: locale)
        }
    }
}

/// A read-only thumbnail of the parsed board, drawn with this app's palette so
/// the player sees what they are about to play rather than the source image.
private struct ScreenshotBoardPreview: View {
    let puzzle: Puzzle
    let showsRegionIcons: Bool

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<puzzle.size, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<puzzle.size, id: \.self) { column in
                        cell(row: row, column: column)
                    }
                }
            }
        }
        .padding(6)
        .background(
            CatPuzzleTheme.surface,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Parsed board, \(puzzle.size) by \(puzzle.size)"
        )
        .accessibilityIdentifier("screenshot-board-preview")
    }

    @ViewBuilder
    private func cell(row: Int, column: Int) -> some View {
        let regionID = puzzle.cell(atRow: row, column: column)?.regionID ?? 0
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(CatPuzzleTheme.regionColor(for: regionID))
            .frame(width: 22, height: 22)
            .overlay {
                marker(
                    for: puzzle.state(atRow: row, column: column) ?? .empty,
                    regionID: regionID
                )
            }
            .overlay(alignment: .topLeading) {
                if showsRegionIcons {
                    Image(systemName: CatPuzzleTheme.regionSymbol(for: regionID))
                        .font(.system(size: 5, weight: .bold))
                        .foregroundStyle(
                            CatPuzzleTheme.markerColor(for: regionID).opacity(0.45)
                        )
                        .padding(2)
                }
            }
    }

    @ViewBuilder
    private func marker(for state: CellState, regionID: Int) -> some View {
        switch state {
        case .empty:
            EmptyView()
        case .excluded:
            Text("×")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        case .cat:
            Circle()
                .fill(CatPuzzleTheme.surface.opacity(0.94))
                .overlay {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CatPuzzleTheme.textPrimary)
                }
                .padding(2)
        }
    }
}

private struct ScreenshotPlayView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GameViewModel

    private let showsRegionIcons: Bool

    init(
        imported: ImportedScreenshotLevel,
        mode: GameplayMode,
        showsRegionIcons: Bool
    ) {
        self.showsRegionIcons = showsRegionIcons
        _viewModel = StateObject(
            wrappedValue: ScreenshotGameFactory.makeViewModel(
                imported: imported,
                mode: mode
            )
        )
    }

    var body: some View {
        GameScreen(
            viewModel: viewModel,
            presentation: .scratch(title: "Screenshot"),
            showsRegionIcons: showsRegionIcons,
            onContinue: { dismiss() }
        )
    }
}

@MainActor
enum ScreenshotGameFactory {
    /// The importer already proved the level valid and the marks consistent
    /// with its solution, so `GameEngine` cannot reject this board. Falling
    /// back to a blank engine keeps that guarantee from turning a bug into a
    /// crash in a player's hands.
    static func makeViewModel(
        imported: ImportedScreenshotLevel,
        mode: GameplayMode
    ) -> GameViewModel {
        if let engine = try? GameEngine(
            fixture: imported.fixture,
            puzzle: imported.puzzle,
            mode: mode
        ) {
            return GameViewModel(engine: engine)
        }
        return GameViewModel(
            engine: try! GameEngine(fixture: imported.fixture, mode: mode)
        )
    }
}
