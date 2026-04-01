#if os(iOS)
import Shared
import SwiftUI

struct RollingPosterCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let posters: [String]
    let compact: Bool
    let accent: Color
    let glow: Color
    let imagePipeline: any ImagePipelineProtocol

    @State private var motion = SwipeLikeMotion(phase: 1.0, interaction: 0, settling: 0)

    private let initialPhase = 1.0

    var body: some View {
        ZStack {
            ambientGlow

            ForEach(Array(posters.enumerated()), id: \.offset) { index, poster in
                let transform = transform(for: index, motion: motion)

                FloatingPreviewCard(
                    descriptor: .init(
                        badge: "",
                        title: "",
                        subtitle: "",
                        palette: [Color.black, Color.black.opacity(0.9), accent],
                        posterAssetName: poster
                    ),
                    width: compact ? 182 : 206,
                    highlight: transform.distance < 0 ? glow : accent,
                    imagePipeline: imagePipeline
                )
                .scaleEffect(transform.scale)
                .rotationEffect(.degrees(transform.rotation))
                .rotation3DEffect(
                    .degrees(transform.tilt),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.65
                )
                .offset(x: transform.x, y: transform.y)
                .opacity(transform.opacity)
                .saturation(transform.saturation)
                .blur(radius: transform.blur)
                .zIndex(transform.zIndex)
            }
        }
        .frame(maxWidth: compact ? 328 : 420, maxHeight: .infinity)
        .task(id: reduceMotion) {
            await runMotionLoop()
        }
    }

    private var ambientGlow: some View {
        ZStack {
            Ellipse()
                .fill(glow.opacity(0.16))
                .frame(width: compact ? 258 : 332, height: compact ? 126 : 154)
                .blur(radius: compact ? 26 : 34)
                .offset(y: compact ? 72 : 82)

            Ellipse()
                .fill(accent.opacity(0.10))
                .frame(width: compact ? 220 : 288, height: compact ? 108 : 132)
                .blur(radius: compact ? 18 : 24)
                .offset(x: compact ? 28 : 34, y: compact ? -18 : -24)
        }
    }

    @MainActor
    private func runMotionLoop() async {
        setMotion(.init(phase: initialPhase, interaction: 0, settling: 0), animation: nil)

        guard !reduceMotion, !posters.isEmpty else { return }

        var basePhase = initialPhase

        while !Task.isCancelled {
            if await pause(for: 0.95) { return }

            setMotion(
                .init(phase: wrappedPhase(basePhase + 0.16), interaction: 0.50, settling: 0),
                animation: .timingCurve(0.30, 0.78, 0.52, 1, duration: 0.50)
            )
            if await pause(for: 0.50) { return }

            setMotion(
                .init(phase: wrappedPhase(basePhase + 0.08), interaction: 0.30, settling: 0),
                animation: .easeOut(duration: 0.30)
            )
            if await pause(for: 0.30) { return }

            setMotion(
                .init(phase: wrappedPhase(basePhase + 0.78), interaction: 0.92, settling: 0),
                animation: .timingCurve(0.18, 0.84, 0.26, 1, duration: 1.02)
            )
            if await pause(for: 1.02) { return }

            setMotion(
                .init(phase: wrappedPhase(basePhase + 1.03), interaction: 0.40, settling: 1),
                animation: .spring(response: 0.48, dampingFraction: 0.86, blendDuration: 0.18)
            )
            if await pause(for: 0.46) { return }

            setMotion(
                .init(phase: wrappedPhase(basePhase + 1), interaction: 0, settling: 0),
                animation: .easeOut(duration: 0.24)
            )
            if await pause(for: 0.24) { return }

            basePhase = wrappedPhase(basePhase + 1)
            setMotion(.init(phase: basePhase, interaction: 0, settling: 0), animation: nil)

            if await pause(for: 1.04) { return }
        }
    }

    @MainActor
    private func setMotion(_ nextMotion: SwipeLikeMotion, animation: Animation?) {
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
        guard !posters.isEmpty else { return initialPhase }

        let count = Double(posters.count)
        var wrapped = phase.truncatingRemainder(dividingBy: count)

        if wrapped < 0 {
            wrapped += count
        }

        return wrapped
    }

    private func transform(for index: Int, motion: SwipeLikeMotion) -> CardTransform {
        let distance = wrappedDistance(for: index, phase: motion.phase)
        let absoluteDistance = abs(distance)
        let spacing = compact ? 100.0 : 118.0
        let verticalStep = compact ? 15.0 : 18.0
        let touchBias = max(0, 1 - absoluteDistance)
        let incomingBias = max(0, 1 - abs(distance - 0.65))
        let outgoingBias = max(0, 1 - abs(distance + 0.35))
        let gestureLean = motion.interaction * (distance >= 0 ? -1.0 : 1.0)

        let x = distance * spacing
        let y = pow(absoluteDistance, 1.18) * verticalStep
            - touchBias * (compact ? 22 : 26)
            - motion.interaction * (touchBias * 13 + incomingBias * 8)
            + motion.settling * touchBias * 4
        let scale = max(0.80, 1.06 - absoluteDistance * 0.15)
            + motion.interaction * (touchBias * 0.020 + incomingBias * 0.010)
            - motion.settling * outgoingBias * 0.012
        let rotation = distance * (compact ? 6.4 : 5.8)
            + gestureLean * (touchBias * 3.0 + incomingBias * 1.6)
            - motion.settling * outgoingBias * 0.9
        let tilt = gestureLean * (touchBias * 4.2 + incomingBias * 2.2)
            - motion.settling * outgoingBias * 1.2
        let opacity = max(0.30, 1.0 - absoluteDistance * 0.18)
        let blur = max(0, absoluteDistance - 1.35) * 1.4
        let saturation = max(0.82, 1.0 - absoluteDistance * 0.10)
        let zIndex = 10 - absoluteDistance

        return CardTransform(
            distance: distance,
            x: x,
            y: y,
            scale: scale,
            rotation: rotation,
            tilt: tilt,
            opacity: opacity,
            blur: blur,
            saturation: saturation,
            zIndex: zIndex
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

private struct SwipeLikeMotion {
    let phase: Double
    let interaction: Double
    let settling: Double
}

private struct CardTransform {
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
