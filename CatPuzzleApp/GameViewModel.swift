import Combine
import CatPuzzleCore

@MainActor
final class GameViewModel: ObservableObject {
    let level: LevelDefinition

    @Published private(set) var puzzle: Puzzle
    @Published private(set) var canUndo: Bool
    @Published private(set) var isSolved: Bool
    @Published private(set) var feedbackMessage: String?

    private var engine: GameEngine

    init(level: LevelDefinition = BuiltInLevels.meadow) throws {
        let engine = try GameEngine(level: level)
        self.engine = engine
        self.level = engine.state.level
        puzzle = engine.state.puzzle
        canUndo = engine.canUndo
        isSolved = engine.state.isSolved
        feedbackMessage = nil
    }

    func toggleExcluded(atRow row: Int, column: Int) {
        guard let currentState = puzzle.state(atRow: row, column: column) else {
            feedbackMessage = "That cell is outside the board."
            return
        }

        switch currentState {
        case .empty:
            apply(.excluded, atRow: row, column: column)
        case .excluded:
            apply(.empty, atRow: row, column: column)
        case .cat:
            feedbackMessage = nil
        }
    }

    func toggleCat(atRow row: Int, column: Int) {
        guard let currentState = puzzle.state(atRow: row, column: column) else {
            feedbackMessage = "That cell is outside the board."
            return
        }

        let nextState: CellState = currentState == .cat ? .empty : .cat
        apply(nextState, atRow: row, column: column)
    }

    func undo() {
        guard engine.undo() else { return }
        feedbackMessage = nil
        synchronizeFromEngine()
    }

    func restart() {
        engine.restart()
        feedbackMessage = nil
        synchronizeFromEngine()
    }

    private func apply(_ state: CellState, atRow row: Int, column: Int) {
        do {
            try engine.setState(state, atRow: row, column: column)
            feedbackMessage = nil
            synchronizeFromEngine()
        } catch GameEngineError.illegalCatPlacement {
            feedbackMessage = "That cat conflicts with another cat."
        } catch GameEngineError.invalidCell {
            feedbackMessage = "That cell is outside the board."
        } catch {
            feedbackMessage = "Unable to update this cell."
        }
    }

    private func synchronizeFromEngine() {
        puzzle = engine.state.puzzle
        canUndo = engine.canUndo
        isSolved = engine.state.isSolved
    }
}
