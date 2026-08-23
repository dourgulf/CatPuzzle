import SwiftUI

struct NextLevelScreen: View {
    let levelName: String
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Next Level")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(levelName)
                .font(.largeTitle.bold())
            Button("Start", action: onStart)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("start-next-level")
        }
        .padding(24)
    }
}
