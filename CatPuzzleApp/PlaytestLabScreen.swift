import SwiftUI
import CatPuzzleCore

/// Developer-only surface for the offline constructive generator. Generated
/// candidates are scratch levels and never affect player progress.
struct PlaytestLabScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    let showsRegionIcons: Bool

    @State private var seedText = "1"
    @State private var count = 3
    @State private var size = 8
    @State private var difficulty: GeneratorDifficulty = .easy
    @State private var profile: RegionGeometryProfile = .dominantBackground
    @State private var isChallenge = false
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var candidates: [PlaytestCandidate] = []
    @State private var statistics: ConstructiveBatchStatistics?
    @State private var generationTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                configurationSection
                if let errorMessage {
                    Text(LocalizedStringKey(errorMessage))
                        .foregroundStyle(CatPuzzleTheme.warning)
                }
                if let statistics {
                    statisticsSection(statistics)
                }
                if !candidates.isEmpty {
                    candidatesSection
                }
            }
            .navigationTitle("Puzzle Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(for: PlaytestCandidate.self) { candidate in
                PlaytestPlayView(
                    puzzle: candidate.puzzle,
                    mode: isChallenge ? .challenge : .exploration,
                    showsRegionIcons: showsRegionIcons
                )
            }
            .onChange(of: difficulty) { _, newDifficulty in
                if newDifficulty == .easy {
                    profile = .dominantBackground
                }
            }
            .onDisappear {
                generationTask?.cancel()
                generationTask = nil
            }
        }
    }

    private var configurationSection: some View {
        Section("Constructive batch") {
            TextField("Seed", text: $seedText)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("playtest-seed-field")
            Stepper("Size: \(size)×\(size)", value: $size, in: 8...10)
            Stepper("Count: \(count)", value: $count, in: 1...10)

            Picker("Difficulty", selection: $difficulty) {
                ForEach(GeneratorDifficulty.allCases, id: \.self) {
                    Text(LocalizedStringKey($0.displayName)).tag($0)
                }
            }
            Picker("Geometry", selection: $profile) {
                ForEach(RegionGeometryProfile.allCases, id: \.self) { value in
                    Text(LocalizedStringKey(value.displayName)).tag(value)
                }
            }
            .disabled(difficulty == .easy)

            Toggle("Challenge Mode", isOn: $isChallenge)
                .accessibilityIdentifier("playtest-challenge-mode-toggle")

            Button(action: generate) {
                if isGenerating {
                    HStack {
                        ProgressView()
                        Text("Generating…")
                    }
                } else {
                    Text("Generate")
                }
            }
            .disabled(isGenerating)
            .accessibilityIdentifier("playtest-generate-button")
        }
    }

    private func statisticsSection(
        _ statistics: ConstructiveBatchStatistics
    ) -> some View {
        Section("Batch result") {
            LabeledContent(
                "Generated",
                value: "\(statistics.generatedCount) / \(statistics.requestedCount)"
            )
            LabeledContent("Logical evaluations", value: "\(statistics.logicalEvaluations)")
            LabeledContent("Boundary mutations", value: "\(statistics.boundaryMutations)")
            if !statistics.failures.isEmpty {
                Text(statistics.failures.map { failure in
                    L10n.format("Seed %@: %@ — %@", [String(failure.seed),
                        L10n.text(failure.stage.rawValue, locale: locale),
                        L10n.text(failure.message, locale: locale)], locale: locale)
                }.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(CatPuzzleTheme.textSecondary)
            }
        }
    }

    private var candidatesSection: some View {
        Section("Candidates") {
            ForEach(candidates) { candidate in
                NavigationLink(value: candidate) {
                    PlaytestCandidateRow(puzzle: candidate.puzzle)
                }
            }
        }
    }

    private func generate() {
        guard let seed = UInt64(seedText) else {
            errorMessage = "Seed must be a whole non-negative number."
            return
        }

        generationTask?.cancel()
        errorMessage = nil
        isGenerating = true
        candidates = []
        statistics = nil
        let requestCount = count
        let requestSize = size
        let requestDifficulty = difficulty
        let requestProfile = profile

        generationTask = Task.detached(priority: .userInitiated) {
            var generated: [ConstructiveGeneratedPuzzle] = []
            var failures: [GenerationFailure] = []
            var evaluations = 0
            var mutations = 0

            for offset in 0..<requestCount {
                guard !Task<Never, Never>.isCancelled else { return }
                let candidateSeed = seed &+ UInt64(offset)
                let result = ConstructivePuzzleGenerator.generate(request: .init(
                    size: requestSize,
                    seed: candidateSeed,
                    difficulty: requestDifficulty,
                    profile: requestProfile
                ), isCancelled: { Task<Never, Never>.isCancelled })
                switch result {
                case let .success(puzzle):
                    generated.append(puzzle)
                    evaluations += puzzle.work.logicalEvaluations
                    mutations += puzzle.work.boundaryMutations
                case let .failure(failure):
                    evaluations += failure.work.logicalEvaluations
                    mutations += failure.work.boundaryMutations
                    failures.append(failure)
                }
            }

            guard !Task<Never, Never>.isCancelled else { return }
            await MainActor.run {
                candidates = generated.map(PlaytestCandidate.init)
                statistics = ConstructiveBatchStatistics(
                    requestedCount: requestCount,
                    generatedCount: generated.count,
                    logicalEvaluations: evaluations,
                    boundaryMutations: mutations,
                    failures: failures
                )
                isGenerating = false
                generationTask = nil
            }
        }
    }
}

private struct ConstructiveBatchStatistics {
    let requestedCount: Int
    let generatedCount: Int
    let logicalEvaluations: Int
    let boundaryMutations: Int
    let failures: [GenerationFailure]
}

private struct PlaytestCandidate: Identifiable, Hashable {
    let id = UUID()
    let puzzle: ConstructiveGeneratedPuzzle

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct PlaytestCandidateRow: View {
    @Environment(\.locale) private var locale
    let puzzle: ConstructiveGeneratedPuzzle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(puzzle.level.size)×\(puzzle.level.size) · seed \(puzzle.seed)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(LocalizedStringKey(puzzle.difficulty.displayName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CatPuzzleTheme.action)
            }
            Text(L10n.format("%@ · pair %@ · triple %@ · set4+ %@ · attack %@ · strongLink %@", [
                L10n.text(puzzle.profile.displayName, locale: locale), String(statistics.lockedPairCount),
                String(statistics.lockedTripleCount), String(statistics.higherOrderLockedSetCount),
                String(statistics.commonAttackCount), String(statistics.strongLinkDeductionCount)
            ], locale: locale))
            .font(.caption)
            .foregroundStyle(CatPuzzleTheme.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private var statistics: LogicalSolveStatistics {
        puzzle.logicalReport.statistics
    }
}

private struct PlaytestPlayView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GameViewModel

    init(
        puzzle: ConstructiveGeneratedPuzzle,
        mode: GameplayMode,
        showsRegionIcons: Bool
    ) {
        self.showsRegionIcons = showsRegionIcons
        _viewModel = StateObject(
            wrappedValue: try! PlaytestGameFactory.makeViewModel(
                puzzle: puzzle,
                mode: mode
            )
        )
    }

    private let showsRegionIcons: Bool

    var body: some View {
        GameScreen(
            viewModel: viewModel,
            presentation: .scratch(title: "Puzzle Lab"),
            showsRegionIcons: showsRegionIcons,
            onBackToLevelStart: { dismiss() },
            onOpenSettings: nil,
            onContinue: { dismiss() }
        )
    }
}

@MainActor
enum PlaytestGameFactory {
    static func makeViewModel(
        puzzle: ConstructiveGeneratedPuzzle,
        mode: GameplayMode
    ) throws -> GameViewModel {
        let fixture = LevelFixture(
            level: puzzle.level,
            solution: puzzle.solution
        )
        return GameViewModel(
            engine: try GameEngine(fixture: fixture, mode: mode)
        )
    }
}

private extension GeneratorDifficulty {
    var displayName: String { rawValue.capitalized }
}

private extension RegionGeometryProfile {
    var displayName: String {
        switch self {
        case .dominantBackground: "Dominant"
        case .balancedMosaic: "Balanced"
        }
    }
}
