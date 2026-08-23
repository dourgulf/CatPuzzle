import SwiftUI

struct RootView: View {
    @ObservedObject var session: AppSession

    var body: some View {
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
}
