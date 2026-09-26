import SwiftUI

struct CelebrationCatPose {
    let time: TimeInterval
    let reduceMotion: Bool

    var catchProgress: Double {
        if reduceMotion { return 1 }
        let progress = min(1, max(0, (time - 1.05) / 0.8))
        return 1 - pow(1 - progress, 3)
    }
    var entrance: Double {
        guard !reduceMotion else { return 1 }
        let progress = min(1, max(0, time / 0.7))
        return progress == 1 ? 1 : 1 - exp(-6 * progress) * cos(9 * progress)
    }
    var jump: Double {
        guard !reduceMotion, time > 0.2, time < 1.25 else { return 0 }
        return -30 * sin((time - 0.2) / 1.05 * .pi)
    }
    var sway: Double { reduceMotion || time < 1.85 ? 0 : sin((time - 1.85) * 2.3) * 3 }
    var tail: Double { reduceMotion ? 0 : sin(time * 3.4) * 12 }
}

/// Original orange mascot, built from separate limbs so catching the medal is a real pose change.
struct CelebrationCatView: View {
    let pose: CelebrationCatPose
    private let orange = Color(red: 1, green: 0.65, blue: 0.15)
    private let amber = Color(red: 0.89, green: 0.37, blue: 0.06)
    private let cream = Color(red: 1, green: 0.92, blue: 0.74)
    private let ink = Color(red: 0.27, green: 0.13, blue: 0.09)

    private var fur: LinearGradient {
        LinearGradient(colors: [Color(red: 1, green: 0.81, blue: 0.35), orange, amber],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Ellipse()
                    .fill(Color(red: 1, green: 0.75, blue: 0.2).opacity(0.20))
                    .frame(width: 210, height: 28)
                    .blur(radius: 10)
                    .position(x: 150, y: 308)

                ZStack {
                    tail
                    Ellipse().fill(fur).frame(width: 64, height: 39)
                        .rotationEffect(.degrees(-12)).position(x: 111, y: 291)
                    Ellipse().fill(fur).frame(width: 64, height: 39)
                        .rotationEffect(.degrees(12)).position(x: 189, y: 291)
                    Ellipse().fill(fur).frame(width: 124, height: 150).position(x: 150, y: 225)
                    Ellipse().fill(cream).frame(width: 84, height: 114).position(x: 150, y: 233)

                    head
                        .rotationEffect(.degrees(pose.sway * 0.8), anchor: UnitPoint(x: 0.5, y: 0.5))

                    medal
                        .scaleEffect(0.75 + 0.25 * pose.catchProgress)
                        .rotationEffect(.degrees((1 - pose.catchProgress) * -100 + pose.sway))
                        .position(x: 150 + (1 - pose.catchProgress) * 118,
                                  y: 229 - (1 - pose.catchProgress) * 190)
                        .opacity(pose.reduceMotion || pose.time >= 1.05 ? 1 : 0)

                    arm(left: true)
                    arm(left: false)
                }
                .frame(width: 300, height: 330)
                .rotationEffect(.degrees(pose.sway), anchor: .bottom)
                .scaleEffect(0.4 + 0.6 * pose.entrance, anchor: .bottom)
                .offset(y: pose.jump)
                .opacity(min(1, pose.entrance * 2))
                .compositingGroup()
                .shadow(color: .black.opacity(0.22), radius: 12, y: 12)
            }
            .frame(width: 300, height: 330)
            .scaleEffect(min(geometry.size.width / 300, geometry.size.height / 330))
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var tail: some View {
        Path { path in
            path.move(to: CGPoint(x: 194, y: 265))
            path.addCurve(to: CGPoint(x: 267, y: 181), control1: CGPoint(x: 258, y: 293), control2: CGPoint(x: 282, y: 222))
        }
        .stroke(fur, style: StrokeStyle(lineWidth: 24, lineCap: .round))
        .overlay {
            Path { path in
                path.move(to: CGPoint(x: 269, y: 193))
                path.addQuadCurve(to: CGPoint(x: 267, y: 181), control: CGPoint(x: 270, y: 187))
            }
            .stroke(cream, style: StrokeStyle(lineWidth: 24, lineCap: .round))
        }
        .rotationEffect(.degrees(pose.tail), anchor: UnitPoint(x: 0.65, y: 0.80))
    }

    private var head: some View {
        ZStack {
            CatEar().fill(fur).frame(width: 70, height: 91)
                .rotationEffect(.degrees(-18)).position(x: 91, y: 67)
            CatEar().fill(fur).frame(width: 70, height: 91)
                .rotationEffect(.degrees(18)).position(x: 209, y: 67)
            CatEar().fill(Color(red: 1, green: 0.66, blue: 0.53)).frame(width: 41, height: 60)
                .rotationEffect(.degrees(-18)).position(x: 92, y: 66)
            CatEar().fill(Color(red: 1, green: 0.66, blue: 0.53)).frame(width: 41, height: 60)
                .rotationEffect(.degrees(18)).position(x: 208, y: 66)
            Ellipse().fill(fur).frame(width: 192, height: 157).position(x: 150, y: 130)
            Capsule().fill(amber.opacity(0.85)).frame(width: 15, height: 36).position(x: 150, y: 68)
            Capsule().fill(amber.opacity(0.75)).frame(width: 12, height: 28)
                .rotationEffect(.degrees(-22)).position(x: 128, y: 68)
            Capsule().fill(amber.opacity(0.75)).frame(width: 12, height: 28)
                .rotationEffect(.degrees(22)).position(x: 172, y: 68)
            Ellipse().fill(cream).frame(width: 126, height: 68).position(x: 150, y: 166)
            eye(left: true).position(x: 111, y: 126)
            eye(left: false).position(x: 189, y: 126)
            Ellipse().fill(Color(red: 1, green: 0.39, blue: 0.35).opacity(0.35))
                .frame(width: 24, height: 13).position(x: 91, y: 152)
            Ellipse().fill(Color(red: 1, green: 0.39, blue: 0.35).opacity(0.35))
                .frame(width: 24, height: 13).position(x: 209, y: 152)
            RoundedRectangle(cornerRadius: 5).fill(ink).frame(width: 20, height: 13)
                .rotationEffect(.degrees(180)).position(x: 150, y: 153)
            Path { path in
                path.move(to: CGPoint(x: 150, y: 157))
                path.addLine(to: CGPoint(x: 150, y: 166))
                path.addCurve(to: CGPoint(x: 127, y: 169), control1: CGPoint(x: 145, y: 181), control2: CGPoint(x: 130, y: 181))
                path.move(to: CGPoint(x: 150, y: 166))
                path.addCurve(to: CGPoint(x: 173, y: 169), control1: CGPoint(x: 155, y: 181), control2: CGPoint(x: 170, y: 181))
            }
            .stroke(ink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            ForEach(0..<2) { index in
                Capsule().fill(ink.opacity(0.8)).frame(width: 25, height: 3)
                    .rotationEffect(.degrees(Double(index * 14 - 7))).position(x: 78, y: CGFloat(161 + index * 12))
                Capsule().fill(ink.opacity(0.8)).frame(width: 25, height: 3)
                    .rotationEffect(.degrees(Double(7 - index * 14))).position(x: 222, y: CGFloat(161 + index * 12))
            }
        }
        .frame(width: 300, height: 330)
    }

    private func eye(left: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Ellipse().fill(ink)
            Ellipse().fill(.white).frame(width: 12, height: 14).offset(x: 5, y: 4)
            Circle().fill(.white.opacity(0.8)).frame(width: 5, height: 5).offset(x: 19, y: 26)
        }
        .frame(width: 31, height: 40)
        .scaleEffect(y: pose.time > 1.7 && pose.time < 2.0 && !pose.reduceMotion ? 0.25 : 1)
        .rotationEffect(.degrees(left ? -5 : 5))
    }

    private func arm(left: Bool) -> some View {
        let progress = pose.catchProgress
        return Capsule()
            .fill(fur)
            .overlay(alignment: .bottom) {
                Ellipse().fill(cream).frame(width: 29, height: 25).padding(.bottom, 3)
            }
            .frame(width: 35, height: 79)
            .rotationEffect(.degrees(left ? 145 - progress * 169 : -145 + progress * 169), anchor: .top)
            .position(x: left ? 101 : 199, y: 225)
    }

    private var medal: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.94, blue: 0.50), Color(red: 1, green: 0.64, blue: 0.08)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(Color.white.opacity(0.75), lineWidth: 3).padding(5)
            Image(systemName: "pawprint.fill")
                .resizable().scaledToFit().foregroundStyle(Color(red: 0.65, green: 0.30, blue: 0.04))
                .padding(19)
        }
        .frame(width: 88, height: 88)
        .shadow(color: Color.orange.opacity(0.4), radius: 16)
    }
}

private struct CatEar: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.midX - 4, y: rect.minY + 3),
                              control: CGPoint(x: rect.minX, y: rect.minY - 8))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                              control: CGPoint(x: rect.maxX, y: rect.minY - 8))
            path.closeSubpath()
        }
    }
}

struct CelebrationCatAnimation: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = Date()
    @State private var finished = false
    let snapshotTime: TimeInterval?
    let reduceMotion: Bool

    var body: some View {
        Group {
            if reduceMotion || snapshotTime != nil {
                CelebrationCatView(pose: CelebrationCatPose(time: snapshotTime ?? 3, reduceMotion: reduceMotion))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: finished || scenePhase != .active)) { context in
                    CelebrationCatView(pose: CelebrationCatPose(
                        time: min(7, context.date.timeIntervalSince(started)), reduceMotion: false
                    ))
                }
            }
        }
        .task {
            guard snapshotTime == nil, !reduceMotion else { return }
            started = Date()
            do { try await Task.sleep(for: .seconds(7)) } catch { return }
            finished = true
        }
    }
}
