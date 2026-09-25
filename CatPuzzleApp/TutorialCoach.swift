import CatPuzzleCore

/// Where a player is in the scripted tutorial.
///
/// The current step is **recomputed from the board** rather than counted up as
/// moves are made: the first step the board does not already satisfy is the
/// one being taught. So restarting the level, resuming it a week later, or
/// clearing a mark all land on the right step with no bookkeeping that could
/// fall out of sync with `GameEngine`.
struct TutorialCoach {
    let script: TutorialScript

    var stepCount: Int { script.steps.count }

    /// `stepCount` once the script is finished.
    func currentStepIndex(for puzzle: Puzzle) -> Int {
        script.steps.firstIndex { !$0.isSatisfied(by: puzzle) } ?? stepCount
    }

    func step(at index: Int) -> TutorialStep? {
        script.steps.indices.contains(index) ? script.steps[index] : nil
    }
}

extension TutorialStep {
    func isSatisfied(by puzzle: Puzzle) -> Bool {
        remainingPositions(in: puzzle).isEmpty
    }

    /// The cells of this step the player has not dealt with yet — what is
    /// left to point at, so a nudge never flashes a cell already marked.
    func remainingPositions(in puzzle: Puzzle) -> [CellPosition] {
        let wanted: CellState
        switch task {
        case .placeCat: wanted = .cat
        case .exclude: wanted = .excluded
        }
        return task.positions.filter { position in
            puzzle.state(atRow: position.row, column: position.column) != wanted
        }
    }

    /// What the player has to do, as the gesture they do it with. The tutorial
    /// is the only place in the game that teaches the gestures, so every step
    /// names one.
    var actionHint: String {
        switch task {
        case .placeCat:
            "Double-tap the cell to put a cat on it."
        case let .exclude(positions):
            positions.count == 1
                ? "Tap the cell once to mark it ×."
                : "Tap each of those cells once to mark it ×."
        }
    }
}

extension TutorialLesson {
    /// The headline the step is taught under. Reinforcement steps repeat the
    /// rule's own headline, so a player who missed it the first time sees the
    /// same sentence again rather than a new one to decode.
    var headline: String {
        switch self {
        case .regionIsASingleCell, .regionHasOneCellLeft:
            PuzzleRule.oneCatPerRegion.headline
        case .rowHasOneCellLeft, .columnHasOneCellLeft,
             .rowAlreadyHasItsCat, .columnAlreadyHasItsCat:
            PuzzleRule.oneCatPerRowAndColumn.headline
        case .catsNeverTouch:
            PuzzleRule.noTouchingCats.headline
        case .everythingTheCatsRuleOut:
            "Now all three at once"
        }
    }

    /// Why this move is the right one. A `.discovery` step deliberately does
    /// not say *where*: naming the block would answer the question the step
    /// exists to ask.
    func explanation(
        coaching: TutorialCoaching,
        showsRegionIcons: Bool
    ) -> String {
        switch self {
        case let .regionIsASingleCell(regionID):
            "Every colored block holds exactly one cat. The \(block(regionID, showsRegionIcons)) is a single cell, so there is nowhere else its cat could go."
        case let .regionHasOneCellLeft(regionID):
            coaching == .guided
                ? "Every other cell of the \(block(regionID, showsRegionIcons)) is ruled out now, so only one is left — and that is where its cat goes."
                : "One colored block has a single cell left. Find it, and put its cat there."
        case let .rowHasOneCellLeft(row):
            coaching == .guided
                ? "Row \(row + 1) has one cell left, so that is where its cat goes."
                : "One row has a single cell left. Find it, and put its cat there."
        case let .columnHasOneCellLeft(column):
            coaching == .guided
                ? "Column \(column + 1) has one cell left, so that is where its cat goes."
                : "One column has a single cell left. Find it, and put its cat there."
        case let .rowAlreadyHasItsCat(row):
            "Every row holds exactly one cat, and row \(row + 1) has got its own. No other cell in that row can hold one."
        case let .columnAlreadyHasItsCat(column):
            "Every column holds exactly one cat too, and column \(column + 1) has got its own. No other cell in that column can hold one."
        case .catsNeverTouch:
            "Cats will not sit next to each other, not even corner to corner. None of the cells around this one can hold a cat."
        case .everythingTheCatsRuleOut:
            "The cats on the board rule out their own rows, their own columns, their own blocks, and everything they touch. Mark all of it out."
        }
    }

    private func block(_ regionID: Int, _ showsRegionIcons: Bool) -> String {
        "\(CatPuzzleTheme.regionDescription(for: regionID, includingShape: showsRegionIcons)) block"
    }
}
