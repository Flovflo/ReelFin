#if os(iOS)
import SwiftUI

struct OnboardingGlassGroup<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(
        spacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

struct OnboardingBackgroundView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let accent: Color
    let glow: Color
    let compact: Bool

    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [OnboardingPalette.backgroundTop, OnboardingPalette.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [glow.opacity(0.12), .clear],
                center: .topLeading,
                startRadius: 12,
                endRadius: compact ? 240 : 340
            )
            .blur(radius: 22)
            .offset(x: drift ? 16 : -10, y: compact ? -128 : -176)

            RadialGradient(
                colors: [accent.opacity(0.10), .clear],
                center: .top,
                startRadius: 12,
                endRadius: compact ? 220 : 300
            )
            .blur(radius: compact ? 40 : 54)
            .offset(x: drift ? -36 : -18, y: compact ? 92 : 74)

            AngularGradient(
                colors: [Color.white.opacity(0.10), .clear, accent.opacity(0.06), .clear],
                center: .topTrailing,
                angle: .degrees(drift ? 230 : 180)
            )
            .blur(radius: compact ? 70 : 92)
            .offset(x: compact ? 140 : 220, y: compact ? -180 : -240)

            LinearGradient(
                colors: [Color.white.opacity(0.018), .clear, Color.black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            drift = true
        }
        .animation(
            reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 14).repeatForever(autoreverses: true),
            value: drift
        )
    }
}

struct TemplateOnboardingBackgroundView: View {
    let compact: Bool

    var body: some View {
        Color.black
            .ignoresSafeArea()
    }
}

struct GlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let tint: Color
    let padding: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = 30,
        tint: Color = OnboardingPalette.panelTint,
        padding: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay { panelStroke }
            .shadow(color: OnboardingPalette.shadow, radius: 16, x: 0, y: 10)
    }

    private var panelStroke: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(OnboardingPalette.panelStroke, lineWidth: 1)
    }
}

struct OnboardingEyebrowChip: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.3)
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular.tint(tint.opacity(0.06)), in: .capsule)
                } else {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            }
    }
}

struct PremiumCTAButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    init(
        title: String,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(action: action) {
                    label
                }
                .buttonStyle(.plain)
                .background {
                    Color.clear
                        .glassEffect(
                            .regular.tint(OnboardingPalette.glowWhite.opacity(0.18)).interactive(),
                            in: .capsule
                        )
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.9)
                }
            } else {
                Button(action: action) {
                    label
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
        }
        .disabled(!isEnabled || isLoading)
    }

    private var label: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .tint(OnboardingPalette.primaryText)
            } else {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))

                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
            }
        }
        .foregroundStyle(OnboardingPalette.primaryText)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .contentShape(Capsule(style: .continuous))
        .opacity(isEnabled ? 1 : 0.72)
    }
}

struct CustomPageProgress: View {
    let currentPage: Int
    let pageCount: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(0 ..< pageCount, id: \.self) { index in
                    let isActive = currentPage == index

                    Button {
                        onSelect(index)
                    } label: {
                        Capsule(style: .continuous)
                            .fill(.clear)
                            .frame(width: isActive ? 52 : 20, height: 10)
                            .background {
                                if #available(iOS 26.0, *) {
                                    Color.clear
                                        .glassEffect(
                                            .regular.tint(Color.white.opacity(isActive ? 0.08 : 0.03)).interactive(),
                                            in: .capsule
                                        )
                                } else {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(isActive ? 0.12 : 0.05))
                                }
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(isActive ? 0.94 : 0.22))
                                    .padding(isActive ? 2 : 3)
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(isActive ? 0.16 : 0.08), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Page \(index + 1)")
                }
            }

            Spacer(minLength: 12)

            Text("\(currentPage + 1) / \(pageCount)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingPalette.secondaryText.opacity(0.9))
                .monospacedDigit()
        }
        .accessibilityIdentifier("onboarding_progress")
    }
}

struct ChromeCircleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OnboardingPalette.primaryText)
            .frame(width: 44, height: 44)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular.interactive(), in: .circle)
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.16, extraBounce: 0),
                value: configuration.isPressed
            )
    }
}

struct ChromeTextButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(OnboardingPalette.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.16, extraBounce: 0),
                value: configuration.isPressed
            )
    }
}
#endif
