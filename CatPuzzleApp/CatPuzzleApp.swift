import SwiftUI

@main
struct CatPuzzleApp: App {
    @StateObject private var viewModel: GameViewModel

    init() {
        let model: GameViewModel
        do {
            model = try GameViewModel()
        } catch {
            preconditionFailure("The built-in meadow level must be valid: \(error)")
        }
        _viewModel = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup {
            GameScreen(viewModel: viewModel)
        }
    }
}
