#if os(tvOS)
import SwiftUI
import UIKit

struct TVOnboardingShowcaseView: View {
    let items: [TVOnboardingItem]
    let currentIndex: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    var body: some View {
        GeometryReader { proxy in
            let tvWidth = min(proxy.size.width * 0.82, 1_180)

            ZStack {
                ambientGlow(width: tvWidth)

                ForEach(items) { item in
                    let isActive = item.id == currentIndex

                    TVOnboardingTelevision(item: item, width: tvWidth)
                        .opacity(isActive ? 1 : 0)
                        .scaleEffect(isActive ? 1 : 0.965)
                        .offset(y: isActive ? (drifting ? -6 : 6) : 28)
                        .blur(radius: isActive ? 0 : 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            guard !reduceMotion else { return }
            drifting = true
        }
        .animation(.smooth(duration: 0.48, extraBounce: 0.02), value: currentIndex)
        .animation(
            reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 6.8).repeatForever(autoreverses: true),
            value: drifting
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func ambientGlow(width: CGFloat) -> some View {
        let item = items[currentIndex]

        ZStack {
            Ellipse()
                .fill(item.secondaryAccent.opacity(0.14))
                .frame(width: width * 0.84, height: 120)
                .blur(radius: 52)
                .offset(y: width * 0.22)

            Ellipse()
                .fill(Color.white.opacity(0.08))
                .frame(width: width * 0.56, height: 80)
                .blur(radius: 34)
                .offset(y: -width * 0.18)
        }
    }
}

private struct TVOnboardingTelevision: View {
    let item: TVOnboardingItem
    let width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.97, green: 0.98, blue: 0.99),
                                Color(red: 0.83, green: 0.86, blue: 0.90),
                                Color(red: 0.50, green: 0.54, blue: 0.62)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 38, style: .continuous)
                            .stroke(Color.white.opacity(0.36), lineWidth: 1.4)
                    }

                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.black.opacity(0.98))
                    .padding(11)

                TVOnboardingScreenshotSurface(item: item)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(16)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .padding(16)

                LinearGradient(
                    colors: [Color.white.opacity(0.14), .clear, Color.black.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(16)
                .blendMode(.screen)
            }
            .frame(width: width, height: width * 0.60)
            .shadow(color: .black.opacity(0.42), radius: 36, x: 0, y: 22)

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            Color(red: 0.72, green: 0.75, blue: 0.82)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 64, height: 28)
                .padding(.top, 14)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.94),
                            Color(red: 0.76, green: 0.79, blue: 0.85)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width * 0.28, height: 18)
                .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)
                .padding(.top, 11)
        }
    }
}

private struct TVOnboardingScreenshotSurface: View {
    let item: TVOnboardingItem

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TVOnboardingScreenshotImage(name: item.screenshotName)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(item.zoomScale, anchor: item.zoomAnchor)

                LinearGradient(
                    colors: [Color.black.opacity(0.18), .clear, Color.black.opacity(0.44)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                TVOnboardingScreenOverlay(item: item)
                    .padding(24)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
}

private struct TVOnboardingScreenshotImage: View {
    let name: String

    var body: some View {
        if let screenshot = UIImage(named: name, in: .main, with: nil) {
            Image(uiImage: screenshot)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.04),
                    Color.black.opacity(0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct TVOnboardingScreenOverlay: View {
    let item: TVOnboardingItem

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                overlayLeading
                Spacer(minLength: 24)
                overlayTrailing
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                overlayBottomLeading
                Spacer(minLength: 24)
                overlayBottomTrailing
            }
        }
    }

    @ViewBuilder
    private var overlayLeading: some View {
        switch item.highlight {
        case .home:
            TVOnboardingGlassBadge(icon: "bolt.fill", text: "Fast Resume")
        case .library:
            TVOnboardingGlassNote(
                eyebrow: "Remote First",
                title: "Less scrolling, bigger art",
                icon: "sparkles"
            )
        case .detail:
            EmptyView()
        case .connect:
            TVOnboardingGlassBadge(icon: "tv.badge.wifi", text: "Apple TV Login")
        }
    }

    @ViewBuilder
    private var overlayTrailing: some View {
        switch item.highlight {
        case .home:
            TVOnboardingGlassBadge(icon: "play.fill", text: "Continue Watching")
        case .library:
            TVOnboardingGlassBadge(icon: "rectangle.stack.fill", text: "Fluid Rails")
        case .detail:
            HStack(spacing: 10) {
                TVOnboardingGlassBadge(icon: "bolt.fill", text: "Direct Play")
                TVOnboardingGlassMini(text: "4K")
                TVOnboardingGlassMini(text: "SDH")
            }
        case .connect:
            TVOnboardingGlassBadge(icon: "iphone.and.arrow.forward", text: "Approve on Phone")
        }
    }

    @ViewBuilder
    private var overlayBottomLeading: some View {
        switch item.highlight {
        case .home:
            TVOnboardingGlassNote(
                eyebrow: "Native Jellyfin",
                title: "Jump back in instantly",
                icon: "play.tv.fill"
            )
        case .library:
            TVOnboardingGlassNote(
                eyebrow: "Focus Navigation",
                title: "Browse faster on the couch",
                icon: "hand.tap.fill"
            )
        case .detail:
            TVOnboardingGlassNote(
                eyebrow: "Playback Clarity",
                title: "See the lightning badge before you press play",
                icon: "bolt.fill"
            )
        case .connect:
            TVOnboardingGlassNote(
                eyebrow: "Quick Connect",
                title: "Link ReelFin in seconds",
                icon: "qrcode"
            )
        }
    }

    @ViewBuilder
    private var overlayBottomTrailing: some View {
        switch item.highlight {
        case .home, .library:
            EmptyView()
        case .detail:
            HStack(spacing: 10) {
                TVOnboardingGlassMini(text: "Resume")
                TVOnboardingGlassMini(text: "Cast")
                TVOnboardingGlassMini(text: "More")
            }
        case .connect:
            TVOnboardingGlassMini(text: "Quick Connect")
        }
    }
}

private struct TVOnboardingGlassBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))

            Text(text)
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background {
            Color.clear.reelFinGlassRoundedRect(
                cornerRadius: 18,
                tint: Color.white.opacity(0.06),
                stroke: Color.white.opacity(0.08),
                shadowOpacity: 0.12,
                shadowRadius: 16,
                shadowYOffset: 8
            )
        }
    }
}

private struct TVOnboardingGlassMini: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                Color.clear.reelFinGlassRoundedRect(
                    cornerRadius: 16,
                    tint: Color.white.opacity(0.05),
                    stroke: Color.white.opacity(0.07),
                    shadowOpacity: 0.10,
                    shadowRadius: 14,
                    shadowYOffset: 7
                )
            }
    }
}

private struct TVOnboardingGlassNote: View {
    let eyebrow: String
    let title: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))

                Text(eyebrow.uppercased())
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundStyle(.white.opacity(0.76))

            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: 360, alignment: .leading)
        .background {
            Color.clear.reelFinGlassRoundedRect(
                cornerRadius: 24,
                tint: Color.white.opacity(0.05),
                stroke: Color.white.opacity(0.08),
                shadowOpacity: 0.14,
                shadowRadius: 18,
                shadowYOffset: 10
            )
        }
    }
}
#endif
