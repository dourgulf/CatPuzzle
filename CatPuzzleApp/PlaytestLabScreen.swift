import SwiftUI
import CatPuzzleCore

/// Developer-only screen for playtesting `PuzzleGenerator` candidates.
/// Fully self-contained: it never touches `AppSession`, `GameProgressStore`,
/// or `BuiltInLevels` — generated puzzles are played in a scratch
/// `GameViewModel` that nothing persists or counts toward progression.
struct PlaytestLabScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var seedText = "1"
    @State private var count = 10
    @State private var isChallenge = false
    @State private var challengeDepth = 2
    @State private var maxAttempts = 1000
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var candidates: [PlaytestCandidate] = []
    @State private var statistics: PuzzleBatchStatistics?

    var body: some View {
        NavigationStack {
            List {
                configurationSection
                if let errorMessage {
                    Text(errorMessage)
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
                PlaytestPlayView(puzzle: candidate.puzzle)
            }
        }
    }

    private var configurationSection: some View {
        Section("Batch") {
            TextField("Seed", text: $seedText)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("playtest-seed-field")
            Stepper("Count: \(count)", value: $count, in: 1...100)
            Toggle("Challenge mode", isOn: $isChallenge)
            if isChallenge {
                Stepper("Max assumption depth: \(challengeDepth)", value: $challengeDepth, in: 1...5)
            }
            Stepper("Max attempts / puzzle: \(maxAttempts)", value: $maxAttempts, in: 100...5000, step: 100)

            Button {
                generate()
            } label: {
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

    private func statisticsSection(_ statistics: PuzzleBatchStatistics) -> some View {
        Section("Batch result") {
            LabeledContent("Generated", value: "\(statistics.generatedCount) / \(statistics.requestedCount)")
            LabeledContent("Total attempts", value: "\(statistics.totalAttempts)")
            LabeledContent("Acceptance rate", value: String(format: "%.2f%%", statistics.acceptanceRate * 100))
            if statistics.generatedCount < statistics.requestedCount {
                Text(
                    "Rejections — multiple: \(statistics.rejectedMultipleSolutions), " +
                    "noSolution: \(statistics.rejectedNoSolution), " +
                    "wrongSolution: \(statistics.rejectedWrongUniqueSolution), " +
                    "logicStuck: \(statistics.rejectedLogicalStuck), " +
                    "notChallenge: \(statistics.rejectedNotChallenge)"
                )
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

        errorMessage = nil
        isGenerating = true
        candidates = []
        statistics = nil

        let mode: PuzzleGenerationMode = isChallenge
            ? .challenge(maxAssumptionDepth: challengeDepth)
            : .mainline
        let request = PuzzleBatchGenerationRequest(
            startSeed: seed,
            count: count,
            mode: mode,
            maxAttemptsPerPuzzle: maxAttempts
        )

        Task.detached(priority: .userInitiated) {
            let result = PuzzleGenerator.generateBatch(request: request)
            await MainActor.run {
                candidates = result.generated.map(PlaytestCandidate.init)
                statistics = result.statistics
                isGenerating = false
            }
        }
    }
}

/// Wraps a `GeneratedPuzzle` with a stable identity for SwiftUI navigation —
/// `GeneratedPuzzle` itself is a plain value type with no identity of its own.
private struct PlaytestCandidate: Identifiable, Hashable {
    let id = UUID()
    let puzzle: GeneratedPuzzle

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct PlaytestCandidateRow: View {
    let puzzle: GeneratedPuzzle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Seed \(puzzle.generationMetadata.seed)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(puzzle.difficulty.score) · \(tierName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CatPuzzleTheme.action)
            }
            Text(
                "pair \(statistics.lockedPairCount) · triple \(statistics.lockedTripleCount) · " +
                "attack \(statistics.commonAttackCount) · strongLink \(statistics.strongLinkDeductionCount) · " +
                "assumptions \(statistics.assumptionCount)"
            )
            .font(.caption)
            .foregroundStyle(CatPuzzleTheme.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private var statistics: LogicalSolveStatistics {
        puzzle.logicalReport.statistics
    }

    private var tierName: String {
        switch puzzle.difficulty.tier {
        case .beginner: "beginner"
        case .easy: "easy"
        case .medium: "medium"
        case .hard: "hard"
        case .expert: "expert"
        case .challenge: "challenge"
        }
    }
}

/// Plays a single generated candidate through the normal `GameScreen`,
/// completely detached from `AppSession` — nothing here is persisted or
/// counted toward level progression.
private struct PlaytestPlayView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GameViewModel

    init(puzzle: GeneratedPuzzle) {
        // `puzzle.level` already passed LevelValidator + a unique-solution
        // check during generation, so this can never throw in practice.
        _viewModel = StateObject(wrappedValue: try! GameViewModel(engine: GameEngine(level: puzzle.level)))
    }

    var body: some View {
        GameScreen(viewModel: viewModel, onContinue: { dismiss() })
    }
}
