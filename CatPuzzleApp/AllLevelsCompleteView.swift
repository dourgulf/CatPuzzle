import SwiftUI

struct AllLevelsCompleteView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("All Levels Complete")
                .font(.title.bold())
        }
        .padding(24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("all-levels-complete")
    }
}
