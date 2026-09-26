import SwiftUI

struct NextLevelScreen: View {
    @Environment(\.locale) private var locale
    let presentation: LevelPresentation
    let onStart: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let logoSide = min(200, geometry.size.width * 0.5)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                    .frame(height: geometry.size.height * 0.18)

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSide, height: logoSide)
                    .clipShape(RoundedRectangle(cornerRadius: logoSide * 0.22, style: .continuous))
                    .accessibilityHidden(true)

                Spacer(minLength: 24)

                Button(action: onStart) {
                    Text(presentation.isTutorial
                        ? L10n.text("Start Tutorial", locale: locale)
                        : presentation.localizedTitle(locale: locale))
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(GameActionButtonStyle(prominent: true))
                .frame(maxWidth: 360)
                .accessibilityIdentifier("start-next-level")
                .padding(.bottom, max(24, geometry.size.height * 0.10))
            }
            .padding(.horizontal, 24)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
