#if os(tvOS)
import Shared
import SwiftUI

struct TVLoginBackgroundView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let accent: Color
    let secondaryAccent: Color

    @State private var drifting = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.028, green: 0.032, blue: 0.055),
                    Color(red: 0.010, green: 0.012, blue: 0.022),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [accent.opacity(0.34), .clear],
                center: .topLeading,
                startRadius: 30,
                endRadius: 920
            )
            .offset(x: drifting ? 60 : -40, y: drifting ? -34 : -12)

            RadialGradient(
                colors: [secondaryAccent.opacity(0.24), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 780
            )
            .offset(x: drifting ? -36 : 44, y: drifting ? -10 : 20)

            LinearGradient(
                colors: [Color.white.opacity(0.04), .clear, Color.black.opacity(0.64)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            drifting = true
        }
        .animation(
            reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 10).repeatForever(autoreverses: true),
            value: drifting
        )
    }
}

struct TVLoginHeroView: View {
    let imagePipeline: any ImagePipelineProtocol
    let accent: Color
    let secondaryAccent: Color
    let phase: TVLoginPhase

    private let posters = [
        "onboarding-poster-1.jpg",
        "onboarding-poster-3.jpg",
        "onboarding-poster-2.jpg",
        "onboarding-poster-4.jpg",
        "onboarding-poster-5.webp"
    ]

    var body: some View {
        ZStack {
            TVPosterHeroCarousel(
                posters: posters,
                accent: accent,
                secondaryAccent: secondaryAccent,
                imagePipeline: imagePipeline
            )
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.10), Color.black.opacity(0.46)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 220)
                .scaleEffect(x: 1.18, y: 1, anchor: .center)
                .blur(radius: 28)
                .offset(y: 42)
        }
        .scaleEffect(phase == .landing ? 1 : 0.94)
        .opacity(phase == .success ? 0.52 : (phase == .landing ? 1 : 0.78))
        .blur(radius: phase == .landing ? 0 : 1.4)
        .offset(y: phase == .landing ? 0 : -20)
        .animation(.smooth(duration: 0.42, extraBounce: 0.02), value: phase)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TVPosterHeroCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let posters: [String]
    let accent: Color
    let secondaryAccent: Color
    let imagePipeline: any ImagePipelineProtocol

    @State private var motion = TVPosterMotion(phase: 1, interaction: 0, settling: 0)

    var body: some View {
        ZStack {
            Ellipse()
                .fill(accent.opacity(0.22))
                .frame(width: 760, height: 220)
                .blur(radius: 50)
                .offset(y: 156)

            Ellipse()
                .fill(secondaryAccent.opacity(0.18))
                .frame(width: 640, height: 180)
                .blur(radius: 38)
                .offset(x: 90, y: -10)

            ForEach(Array(posters.enumerated()), id: \.offset) { index, poster in
                let transform = transform(for: index, motion: motion)

                FloatingPreviewCard(
                    descriptor: .init(
                        badge: "",
                        title: "",
                        subtitle: "",
                        palette: [Color.black, accent.opacity(0.70), secondaryAccent.opacity(0.64)],
                        posterAssetName: poster
                    ),
                    width: 316,
                    highlight: transform.distance < 0 ? secondaryAccent : accent,
                    imagePipeline: imagePipeline
                )
                .scaleEffect(transform.scale)
                .rotationEffect(.degrees(transform.rotation))
                .rotation3DEffect(.degrees(transform.tilt), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                .offset(x: transform.x, y: transform.y)
                .opacity(transform.opacity)
                .blur(radius: transform.blur)
                .saturation(transform.saturation)
                .zIndex(transform.zIndex)
            }
        }
        .frame(maxWidth: 1_160, maxHeight: .infinity)
        .task(id: reduceMotion) {
            await runMotionLoop()
        }
    }

    @MainActor
    private func runMotionLoop() async {
        setMotion(.init(phase: 1, interaction: 0, settling: 0), animation: nil)

        guard !reduceMotion, !posters.isEmpty else { return }

        var basePhase = 1.0

        while !Task.isCancelled {
            if await pause(for: 1.10) { return }
            setMotion(.init(phase: wrappedPhase(basePhase + 0.14), interaction: 0.42, settling: 0), animation: .timingCurve(0.28, 0.78, 0.52, 1, duration: 0.55))
            if await pause(for: 0.55) { return }
            setMotion(.init(phase: wrappedPhase(basePhase + 0.05), interaction: 0.20, settling: 0), animation: .easeOut(duration: 0.26))
            if await pause(for: 0.26) { return }
            setMotion(.init(phase: wrappedPhase(basePhase + 0.84), interaction: 0.92, settling: 0), animation: .timingCurve(0.20, 0.82, 0.26, 1, duration: 1.14))
            if await pause(for: 1.14) { return }
            setMotion(.init(phase: wrappedPhase(basePhase + 1.03), interaction: 0.34, settling: 1), animation: .spring(response: 0.56, dampingFraction: 0.86, blendDuration: 0.12))
            if await pause(for: 0.50) { return }
            setMotion(.init(phase: wrappedPhase(basePhase + 1), interaction: 0, settling: 0), animation: .easeOut(duration: 0.20))
            if await pause(for: 0.20) { return }
            basePhase = wrappedPhase(basePhase + 1)
            setMotion(.init(phase: basePhase, interaction: 0, settling: 0), animation: nil)
        }
    }

    @MainActor
    private func setMotion(_ nextMotion: TVPosterMotion, animation: Animation?) {
        guard let animation else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                motion = nextMotion
            }
            return
        }

        withAnimation(animation) {
            motion = nextMotion
        }
    }

    private func pause(for seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return false
        } catch {
            return true
        }
    }

    private func wrappedPhase(_ phase: Double) -> Double {
        guard !posters.isEmpty else { return 1 }

        let count = Double(posters.count)
        var wrapped = phase.truncatingRemainder(dividingBy: count)

        if wrapped < 0 {
            wrapped += count
        }

        return wrapped
    }

    private func transform(for index: Int, motion: TVPosterMotion) -> TVPosterTransform {
        let distance = wrappedDistance(for: index, phase: motion.phase)
        let absoluteDistance = abs(distance)
        let touchBias = max(0, 1 - absoluteDistance)
        let incomingBias = max(0, 1 - abs(distance - 0.66))
        let outgoingBias = max(0, 1 - abs(distance + 0.30))
        let gestureLean = motion.interaction * (distance >= 0 ? -1.0 : 1.0)

        let x = distance * 186
        let y = pow(absoluteDistance, 1.16) * 28 - touchBias * 42 - motion.interaction * (touchBias * 16 + incomingBias * 8) + motion.settling * touchBias * 6
        let scale = max(0.78, 1.08 - absoluteDistance * 0.12) + motion.interaction * (touchBias * 0.022 + incomingBias * 0.012) - motion.settling * outgoingBias * 0.010
        let rotation = distance * 8.4 + gestureLean * (touchBias * 4.0 + incomingBias * 1.8) - motion.settling * outgoingBias
        let tilt = gestureLean * (touchBias * 5.8 + incomingBias * 2.8) - motion.settling * outgoingBias * 1.2
        let opacity = max(0.26, 1 - absoluteDistance * 0.18)
        let blur = max(0, absoluteDistance - 1.3) * 1.2
        let saturation = max(0.80, 1 - absoluteDistance * 0.10)

        return .init(
            distance: distance,
            x: x,
            y: y,
            scale: scale,
            rotation: rotation,
            tilt: tilt,
            opacity: opacity,
            blur: blur,
            saturation: saturation,
            zIndex: 10 - absoluteDistance
        )
    }

    private func wrappedDistance(for index: Int, phase: Double) -> Double {
        guard !posters.isEmpty else { return 0 }

        let count = Double(posters.count)
        let halfCount = count / 2
        var distance = Double(index) - phase

        if distance > halfCount {
            distance -= count
        } else if distance < -halfCount {
            distance += count
        }

        return distance
    }
}

private struct TVPosterMotion {
    let phase: Double
    let interaction: Double
    let settling: Double
}

private struct TVPosterTransform {
    let distance: Double
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let rotation: Double
    let tilt: Double
    let opacity: Double
    let blur: CGFloat
    let saturation: Double
    let zIndex: Double
}
#endif
