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
    /// left to point at when they request a clue.
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

    /// What the player has to do, as the gesture they do it with.
    var actionHint: String {
        switch task {
        case .placeCat:
            return coaching == .guided
                ? "Double-tap the lit cell to place a cat."
                : "Double-tap the right cell to place a cat."
        case .exclude:
            if coaching == .discovery {
                switch lesson {
                case .secondCatRulesOut:
                    return "Find and tap one empty cell this new cat rules out."
                default:
                    return "Tap one ruled-out empty cell. The rest will follow."
                }
            }
            switch lesson {
            case .rowAlreadyHasItsCat:
                return "Tap every other cell in this cat's row to mark ×."
            case .columnAlreadyHasItsCat:
                return "Tap every other cell in the same cat's column to mark ×."
            case .catsNeverTouch:
                return "Tap all four unmarked corners around this cat to mark ×."
            default:
                return "Tap each lit empty cell to mark ×."
            }
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
            "Your turn: rule out a cell"
        case .secondCatRulesOut:
            "Now follow this cat"
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
                ? "The crosses you just made leave the \(block(regionID, showsRegionIcons)) with one open cell. Its cat goes there."
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
            "The cat you just placed fills row \(row + 1). Every row holds exactly one cat, so no other cell in its row can hold one."
        case let .columnAlreadyHasItsCat(column):
            "Stay with the same cat. It fills column \(column + 1) too, so no other cell in its column can hold one."
        case .catsNeverTouch:
            "The row and column crosses cover this cat's four sides. Cats cannot touch at the corners either, so mark the four diagonal cells around this same cat."
        case .everythingTheCatsRuleOut:
            "Look along a cat's row or column, inside its colored block, or at a neighboring square. Which empty cell cannot hold a cat?"
        case .secondCatRulesOut:
            "The second cat starts the same pattern. Find one cell it rules out; then watch its row, column, and neighboring cells fill in."
        }
    }

    private func block(_ regionID: Int, _ showsRegionIcons: Bool) -> String {
        "\(CatPuzzleTheme.regionDescription(for: regionID, includingShape: showsRegionIcons)) block"
    }
}
