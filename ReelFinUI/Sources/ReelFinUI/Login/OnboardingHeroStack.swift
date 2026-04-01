#if os(iOS)
import Shared
import SwiftUI

struct OnboardingHeroStack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let page: OnboardingPageContent
    let compact: Bool
    let imagePipeline: any ImagePipelineProtocol

    @State private var floating = false

    var body: some View {
        ZStack {
            heroBody

            Ellipse()
                .fill(Color.black.opacity(0.24))
                .frame(width: compact ? 314 : 420, height: compact ? 96 : 126)
                .blur(radius: compact ? 24 : 30)
                .offset(y: compact ? 102 : 118)
                .allowsHitTesting(false)
        }
        .onAppear {
            guard !reduceMotion else { return }
            floating = true
        }
        .animation(
            reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 7.5).repeatForever(autoreverses: true),
            value: floating
        )
    }

    @ViewBuilder
    private var heroBody: some View {
        switch page.heroStyle {
        case .floatingCards:
            NativePosterHero(
                page: page,
                compact: compact,
                imagePipeline: imagePipeline
            )
        case .playbackPipeline:
            PlaybackPipelineHero(page: page, compact: compact, floating: floating)
        case .qualityBadges:
            QualityPreservationHero(page: page, compact: compact, floating: floating)
        case .browserPreview:
            BrowserImmersionHero(page: page, compact: compact, floating: floating)
        }
    }
}

private struct NativePosterHero: View {
    let page: OnboardingPageContent
    let compact: Bool
    let imagePipeline: any ImagePipelineProtocol

    var body: some View {
        RollingPosterCarousel(
            posters: page.heroPosterAssets,
            compact: compact,
            accent: page.accent,
            glow: page.glow,
            imagePipeline: imagePipeline
        )
    }
}

private struct PlaybackPipelineHero: View {
    let page: OnboardingPageContent
    let compact: Bool
    let floating: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                pipelineCurve(in: proxy.size)

                PipelineModule(
                    title: "Direct Play",
                    detail: "Native when the source already fits.",
                    accent: page.glow
                )
                .frame(width: compact ? 126 : 150)
                .offset(x: compact ? -92 : -126, y: floating ? -28 : -12)

                PipelineModule(
                    title: "Smart Remux",
                    detail: "Repackages only when Apple playback wins.",
                    accent: page.accent
                )
                .frame(width: compact ? 150 : 182)
                .scaleEffect(1.04)
                .offset(y: floating ? 2 : -6)

                PipelineModule(
                    title: "Fallback",
                    detail: "Difficult formats stay smooth.",
                    accent: OnboardingPalette.teal
                )
                .frame(width: compact ? 126 : 150)
                .offset(x: compact ? 92 : 126, y: floating ? 24 : 38)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func pipelineCurve(in size: CGSize) -> some View {
        Path { path in
            let left = CGPoint(x: size.width * 0.30, y: size.height * 0.34)
            let center = CGPoint(x: size.width * 0.50, y: size.height * 0.47)
            let right = CGPoint(x: size.width * 0.70, y: size.height * 0.64)

            path.move(to: left)
            path.addCurve(
                to: center,
                control1: CGPoint(x: size.width * 0.38, y: size.height * 0.34),
                control2: CGPoint(x: size.width * 0.44, y: size.height * 0.45)
            )
            path.addCurve(
                to: right,
                control1: CGPoint(x: size.width * 0.56, y: size.height * 0.50),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.64)
            )
        }
        .stroke(
            LinearGradient(
                colors: [page.glow.opacity(0.18), page.accent.opacity(0.92), OnboardingPalette.teal.opacity(0.26)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
        )
        .shadow(color: page.accent.opacity(0.24), radius: 10, x: 0, y: 0)
    }
}

private struct PipelineModule: View {
    let title: String
    let detail: String
    let accent: Color

    var body: some View {
        GlassPanel(cornerRadius: 28, tint: accent.opacity(0.08), padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Capsule(style: .continuous)
                    .fill(accent.opacity(0.82))
                    .frame(width: 38, height: 5)

                Spacer(minLength: 0)

                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(OnboardingPalette.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OnboardingPalette.secondaryText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.88)
            }
            .frame(height: 134, alignment: .topLeading)
        }
    }
}

private struct QualityPreservationHero: View {
    let page: OnboardingPageContent
    let compact: Bool
    let floating: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .fill(page.accent.opacity(0.18))
                .frame(width: compact ? 250 : 320, height: compact ? 150 : 188)
                .blur(radius: 28)
                .offset(y: 18)

            FloatingPreviewCard(
                descriptor: .init(
                    badge: "QUALITY",
                    title: "Preserve Impact",
                    subtitle: "HDR, Dolby Vision, and surround stay intact.",
                    palette: [Color(red: 0.18, green: 0.12, blue: 0.10), Color(red: 0.30, green: 0.22, blue: 0.14), Color(red: 0.38, green: 0.30, blue: 0.16)],
                ),
                width: compact ? 172 : 206,
                highlight: page.accent
            )
            .offset(y: floating ? 10 : -2)

            QualityBadgeChip(label: "HDR", tint: page.accent)
                .offset(x: compact ? -108 : -134, y: floating ? -34 : -18)

            QualityBadgeChip(label: "Dolby Vision", tint: page.glow)
                .offset(x: compact ? 100 : 128, y: floating ? -48 : -34)

            QualityBadgeChip(label: "Surround", tint: OnboardingPalette.teal)
                .offset(x: compact ? -96 : -118, y: floating ? 72 : 88)

            QualityBadgeChip(label: "4K", tint: Color.white.opacity(0.92))
                .offset(x: compact ? 108 : 132, y: floating ? 58 : 74)

            QualityBadgeChip(label: "High Bitrate", tint: page.accent)
                .offset(y: floating ? -94 : -78)
        }
    }
}

private struct QualityBadgeChip: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular.tint(tint.opacity(0.05)), in: .capsule)
                } else {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
    }
}

private struct BrowserImmersionHero: View {
    let page: OnboardingPageContent
    let compact: Bool
    let floating: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            GlassPanel(cornerRadius: 34, tint: page.accent.opacity(0.07), padding: compact ? 18 : 22) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("ReelFin")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(OnboardingPalette.primaryText)

                        Text("Now Playing")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(OnboardingPalette.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                if #available(iOS 26.0, *) {
                                    Color.clear
                                        .glassEffect(.regular.tint(Color.white.opacity(0.04)), in: .capsule)
                                } else {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                }
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            }

                        Spacer(minLength: 0)

                        Capsule(style: .continuous)
                            .fill(page.glow.opacity(0.48))
                            .frame(width: 28, height: 6)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Continue Watching")
                            .font(.system(size: compact ? 20 : 24, weight: .bold))
                            .foregroundStyle(OnboardingPalette.primaryText)

                        Text("Jump back in without friction.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(OnboardingPalette.secondaryText)
                    }

                    HStack(spacing: 12) {
                        BrowserPoster(accent: page.glow, height: compact ? 126 : 148)
                        BrowserPoster(accent: page.accent, height: compact ? 126 : 148)
                        BrowserPoster(accent: OnboardingPalette.gold, height: compact ? 126 : 148)
                    }

                    HStack(spacing: 8) {
                        ForEach(0 ..< 3, id: \.self) { index in
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(index == 0 ? 0.44 : 0.16))
                                .frame(width: index == 0 ? 72 : 44, height: 6)
                        }
                    }
                }
            }
            .frame(maxWidth: compact ? 320 : 430)
            .rotation3DEffect(.degrees(floating ? 4 : 0), axis: (x: 1, y: 0, z: 0))

            GlassPanel(cornerRadius: 28, tint: page.glow.opacity(0.08), padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ready")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OnboardingPalette.secondaryText)

                    Text("Instant Details")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(OnboardingPalette.primaryText)
                }
                .frame(width: 116, alignment: .leading)
            }
            .offset(x: compact ? 26 : 48, y: floating ? -72 : -56)
        }
    }
}

private struct BrowserPoster: View {
    let accent: Color
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.12, green: 0.14, blue: 0.18), accent.opacity(0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .overlay(alignment: .bottomLeading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 44, height: 6)
                    .padding(14)
            }
    }
}
#endif
