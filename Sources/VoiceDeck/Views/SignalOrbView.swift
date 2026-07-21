import SwiftUI

struct SignalOrbView: View {
    let size: CGFloat
    var isActive = false
    var showsRipples = false
    var isSoft = false
    var activity: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(
            minimumInterval: reduceMotion ? 1 : 1 / 30,
            paused: reduceMotion || !isActive
        )) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let energy = motionEnergy
            let breathSpeed = 2.6 + energy * 2.2
            let breathDepth = 0.022 + energy * 0.032
            let breath = CGFloat(reduceMotion ? 1 : 1 + sin(time * breathSpeed) * breathDepth)

            ZStack {
                if isSoft {
                    if showsRipples && isActive && !reduceMotion {
                        ForEach(0 ..< 3, id: \.self) { index in
                            ripple(index: index, time: time)
                        }
                    }
                    softOrb(time: time)
                } else {
                    ambientGlow(time: time)
                    if showsRipples && isActive && !reduceMotion {
                        ForEach(0 ..< 3, id: \.self) { index in
                            ripple(index: index, time: time)
                        }
                    }
                    orbBody(time: time)
                    rim(time: time)
                }
            }
            .scaleEffect(breath)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func softOrb(time: TimeInterval) -> some View {
        let energy = motionEnergy
        let speed = 0.95 + energy * 1.8
        let distance = size * CGFloat(0.035 + energy * 0.055)
        let movementX = reduceMotion ? CGFloat.zero : CGFloat(sin(time * speed)) * distance
        let movementY = reduceMotion ? CGFloat.zero : CGFloat(cos(time * (speed * 0.82))) * distance * 0.72
        let cyanScale = CGFloat(1 + sin(time * (1.7 + energy * 1.8)) * (0.025 + energy * 0.045))
        let purpleScale = CGFloat(1 + cos(time * (1.5 + energy * 2.0)) * (0.03 + energy * 0.05))
        return ZStack {
            Circle()
                .fill(Color(red: 0.06, green: 0.63, blue: 0.98).opacity(0.78))
                .frame(width: size * 0.84, height: size * 0.84)
                .blur(radius: size * 0.095)
                .scaleEffect(cyanScale)
                .offset(x: -size * 0.08 + movementX, y: -size * 0.08 + movementY)
            Circle()
                .fill(Color(red: 0.20, green: 0.16, blue: 0.72).opacity(0.76))
                .frame(width: size * 0.66, height: size * 0.66)
                .blur(radius: size * 0.105)
                .scaleEffect(purpleScale)
                .offset(x: size * 0.12 - movementX, y: size * 0.13 - movementY)
            Circle()
                .fill(Color(red: 0.04, green: 0.48, blue: 0.96).opacity(0.28 + energy * 0.16))
                .frame(width: size * 1.08, height: size * 1.08)
                .blur(radius: size * CGFloat(0.125 - energy * 0.02))
        }
    }

    private func ambientGlow(time: TimeInterval) -> some View {
        let pulse = CGFloat(reduceMotion ? 1 : 0.92 + sin(time * 2.1) * 0.08)
        return Circle()
            .fill(Color.cyan.opacity(isActive ? 0.17 : 0.08))
            .frame(width: size * 1.32, height: size * 1.32)
            .blur(radius: size * 0.13)
            .scaleEffect(pulse)
    }

    private func ripple(index: Int, time: TimeInterval) -> some View {
        let energy = motionEnergy
        let period = 1.65 - energy * 0.72
        let progress = (time / period + Double(index) / 3)
            .truncatingRemainder(dividingBy: 1)
        return Circle()
            .stroke(
                Color(red: 0.06, green: 0.55, blue: 0.98)
                    .opacity((1 - progress) * (0.38 + energy * 0.44)),
                lineWidth: 0.9 + energy * 0.8
            )
            .scaleEffect(CGFloat(0.8 + progress * (0.58 + energy * 0.18)))
    }

    private var motionEnergy: Double {
        pow(min(max(activity, 0), 1), 1.35) * 0.72
    }

    private func orbBody(time: TimeInterval) -> some View {
        let blueX = CGFloat(sin(time * 1.7)) * size * 0.09
        let blueY = CGFloat(cos(time * 1.3)) * size * 0.06
        let purpleX = CGFloat(cos(time * 1.2)) * size * 0.1
        let purpleY = CGFloat(sin(time * 1.5)) * size * 0.08

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.94),
                            Color(red: 0.52, green: 0.84, blue: 1).opacity(0.78),
                            Color(red: 0.12, green: 0.55, blue: 0.94).opacity(0.88),
                            Color(red: 0.30, green: 0.29, blue: 0.69).opacity(0.9)
                        ],
                        center: UnitPoint(x: 0.31, y: 0.22),
                        startRadius: 0,
                        endRadius: size * 0.54
                    )
                )

            Ellipse()
                .fill(Color(red: 0.29, green: 0.80, blue: 1).opacity(0.88))
                .frame(width: size * 0.78, height: size * 0.56)
                .blur(radius: max(2, size * 0.065))
                .offset(x: -size * 0.16 + blueX, y: -size * 0.14 + blueY)

            Ellipse()
                .fill(Color(red: 0.35, green: 0.28, blue: 0.88).opacity(0.74))
                .frame(width: size * 0.72, height: size * 0.68)
                .blur(radius: max(2, size * 0.075))
                .offset(x: size * 0.2 + purpleX, y: size * 0.2 + purpleY)

            Circle()
                .fill(Color.white.opacity(0.44))
                .frame(width: size * 0.1, height: size * 0.1)
                .blur(radius: size * 0.025)
                .offset(x: -size * 0.2, y: -size * 0.23)
        }
        .clipShape(Circle())
        .padding(size * 0.08)
        .shadow(color: Color.cyan.opacity(0.25), radius: size * 0.16, y: size * 0.05)
    }

    private func rim(time: TimeInterval) -> some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        Color.cyan.opacity(0.3),
                        Color(red: 0.38, green: 0.83, blue: 1),
                        Color(red: 0.35, green: 0.33, blue: 0.78).opacity(0.7),
                        .white.opacity(0.9),
                        Color(red: 0.18, green: 0.68, blue: 1),
                        Color.cyan.opacity(0.3)
                    ],
                    center: .center
                ),
                lineWidth: max(1, size * 0.025)
            )
            .padding(1)
            .rotationEffect(reduceMotion ? .zero : .degrees(time * 18))
    }
}
