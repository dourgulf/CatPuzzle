import SwiftUI

/// The next-level action appears after the mascot catches its medal.
struct LevelCelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.locale) private var locale
    @State private var revealed = false
    @State private var controlsRevealed = false
    var snapshotTime: TimeInterval? = nil
    var snapshotReduceMotion = false
    var nextPresentation: LevelPresentation? = nil
    let onContinue: () -> Void

    private var reduceMotion: Bool { systemReduceMotion || (snapshotTime != nil && snapshotReduceMotion) }
    private var isVisible: Bool { reduceMotion || (snapshotTime.map { $0 >= 1.3 } ?? revealed) }

    private var showsControls: Bool { reduceMotion || (snapshotTime.map { $0 >= 2.1 } ?? controlsRevealed) }

    var body: some View {
        GeometryReader { geometry in
            let mascotSide = min(330, geometry.size.width * 0.85, geometry.size.height * 0.46)
            ZStack {
                Color.black.opacity(0.80)
                    .ignoresSafeArea()

                CelebrationEffects(snapshotTime: snapshotTime, reduceMotion: reduceMotion)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Spacer(minLength: 20)
                    CelebrationCatAnimation(snapshotTime: snapshotTime, reduceMotion: reduceMotion)
                        .frame(width: mascotSide, height: mascotSide)
                        .accessibilityHidden(true)

                    VStack(spacing: 12) {
                        Text("Purrfect!")
                            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                            .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.34))
                            .accessibilityIdentifier("level-complete-message")
                        Text("Every cat found!")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 24)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.55).delay(1.3), value: isVisible)

                    Spacer(minLength: 32)
                    Button(action: onContinue) {
                        Text(nextPresentation?.localizedTitle(locale: locale) ?? L10n.text("Continue", locale: locale))
                    }
                        .font(.title3.bold())
                        .buttonStyle(GameActionButtonStyle(prominent: true))
                        .frame(maxWidth: 360)
                        .shadow(color: CatPuzzleTheme.actionInk.opacity(0.18), radius: 16, y: 8)
                        .accessibilityIdentifier("continue-after-completion")
                        .opacity(showsControls ? 1 : 0)
                        .offset(y: showsControls ? 0 : 12)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: showsControls)
                        .allowsHitTesting(showsControls)
                        .accessibilityHidden(!showsControls)
                        .padding(.bottom, max(24, geometry.size.height * 0.07))
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityAddTraits(.isModal)
        .onAppear { revealed = true }
        .task {
            guard snapshotTime == nil, !reduceMotion else { return }
            do { try await Task.sleep(for: .seconds(2.1)) } catch { return }
            controlsRevealed = true
        }
        .sensoryFeedback(.success, trigger: revealed)
    }
}

/// Deterministic particles keep rendering stable and make every animation phase reviewable.
struct CelebrationParticle {
    static let duration: TimeInterval = 7
    static let all: [CelebrationParticle] = (0..<252).map { CelebrationParticle(index: $0) }
    private static let palette = [Color(red: 1, green: 0.69, blue: 0.16), Color(red: 1, green: 0.38, blue: 0.43),
                                  Color(red: 0.57, green: 0.44, blue: 0.88), Color(red: 0.19, green: 0.71, blue: 0.57),
                                  Color(red: 0.27, green: 0.68, blue: 0.89), Color(red: 1, green: 0.47, blue: 0.72)]
    let index: Int

    private func noise(_ salt: Int) -> Double {
        let value = sin(Double(index * 73 + salt * 197 + 11)) * 43758.5453
        return value - floor(value)
    }

    func position(at time: TimeInterval, in size: CGSize) -> CGPoint? {
        guard time >= 0, time < Self.duration else { return nil }
        let rain = index >= 192
        let delay = rain ? 0.9 + noise(1) * 2.2 : Double(index / 64) * 0.55
        let age = time - delay
        guard age >= 0, age < 4.2 else { return nil }
        let x: Double
        let y: Double
        if rain {
            x = noise(2) * size.width + sin(age * 2 + noise(3) * 6) * 24
            y = -24 + age * size.height * (0.18 + noise(4) * 0.12)
        } else {
            let fromLeft = index.isMultiple(of: 2)
            let direction = fromLeft ? 1.0 : -1.0
            x = (fromLeft ? -12 : size.width + 12)
                + direction * size.width * (0.23 + noise(2) * 0.70) * age
                + sin(age * 4 + noise(3) * 6) * 12
            y = size.height * (0.72 + noise(4) * 0.12)
                - size.height * (0.72 + noise(5) * 0.55) * age
                + size.height * 0.36 * age * age
        }
        guard x > -40, x < size.width + 40, y > -60, y < size.height + 40 else { return nil }
        return CGPoint(x: x, y: y)
    }

    var color: Color {
        Self.palette[index % Self.palette.count]
    }
    var side: Double { 5 + noise(6) * 7 }
    func angle(at time: TimeInterval) -> Double { noise(7) * 360 + time * (80 + noise(8) * 240) }
    func flip(at time: TimeInterval) -> Double { 0.25 + abs(cos(time * (3 + noise(9) * 5))) * 0.75 }
}

private struct CelebrationEffects: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = Date()
    @State private var finished = false
    let snapshotTime: TimeInterval?
    let reduceMotion: Bool

    var body: some View {
        Group {
            if reduceMotion {
                canvas(at: CelebrationParticle.duration)
            } else if let snapshotTime {
                canvas(at: snapshotTime)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: finished || scenePhase != .active)) { context in
                    canvas(at: min(CelebrationParticle.duration, context.date.timeIntervalSince(started)))
                }
            }
        }
        .task {
            guard snapshotTime == nil, !reduceMotion else { return }
            started = Date()
            do { try await Task.sleep(for: .seconds(CelebrationParticle.duration)) }
            catch { return }
            finished = true
        }
    }

    private func canvas(at time: TimeInterval) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.38)
            let radius = max(size.width, size.height)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [Color.orange.opacity(0.28), Color.clear]),
                center: center, startRadius: 0, endRadius: size.width * 0.8
            ))
            for index in 0..<12 {
                let angle = Double(index) * .pi / 6 + time * 0.045
                var ray = Path()
                ray.move(to: center)
                ray.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                ray.addLine(to: CGPoint(x: center.x + cos(angle + 0.13) * radius, y: center.y + sin(angle + 0.13) * radius))
                ray.closeSubpath()
                context.fill(ray, with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.14), .clear]),
                    center: center, startRadius: 0, endRadius: size.width * 1.1
                ))
            }
            for index in 0..<22 {
                let x = Double((index * 137 + 29) % 997) / 997 * size.width
                let y = Double((index * 211 + 71) % 991) / 991 * size.height * 0.86
                let sparkle = Self.star(points: 4, outer: index.isMultiple(of: 3) ? 5 : 3, inner: 1)
                var layer = context
                layer.translateBy(x: x, y: y)
                layer.opacity = 0.3 + 0.3 * abs(sin(time * 1.1 + Double(index)))
                layer.fill(sparkle, with: .color(Color(red: 0.94, green: 0.62, blue: 0.18)))
            }
            for particle in CelebrationParticle.all {
                guard let position = particle.position(at: time, in: size) else { continue }
                var layer = context
                layer.translateBy(x: position.x, y: position.y)
                layer.rotate(by: .degrees(particle.angle(at: time)))
                layer.scaleBy(x: particle.flip(at: time), y: 1)
                layer.opacity = min(1, (CelebrationParticle.duration - time) / 0.8)
                let side = particle.side
                let shape: Path
                switch particle.index % 4 {
                case 0: shape = Self.star(points: 5, outer: side * 0.7, inner: side * 0.32)
                case 1: shape = Path(ellipseIn: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
                default: shape = Path(roundedRect: CGRect(x: -side / 2, y: -side, width: side, height: side * 2), cornerRadius: 1.5)
                }
                layer.fill(shape, with: .color(particle.color))
            }
        }
    }

    private static func star(points: Int, outer: Double, inner: Double) -> Path {
        Path { path in
            for index in 0..<(points * 2) {
                let angle = Double(index) * .pi / Double(points) - .pi / 2
                let radius = index.isMultiple(of: 2) ? outer : inner
                let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}
