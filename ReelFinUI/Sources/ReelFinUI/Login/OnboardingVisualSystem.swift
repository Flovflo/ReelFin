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
                colors: [glow.opacity(0.10), .clear],
                center: .topLeading,
                startRadius: 8,
                endRadius: compact ? 220 : 320
            )
            .blur(radius: 18)
            .offset(x: drift ? 10 : -6, y: compact ? -120 : -170)

            RadialGradient(
                colors: [accent.opacity(0.08), .clear],
                center: .top,
                startRadius: 8,
                endRadius: compact ? 180 : 260
            )
            .blur(radius: compact ? 32 : 40)
            .offset(x: drift ? -28 : -14, y: compact ? 88 : 60)

            LinearGradient(
                colors: [Color.white.opacity(0.015), .clear, Color.black.opacity(0.52)],
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
            .shadow(color: OnboardingPalette.shadow, radius: 14, x: 0, y: 8)
    }

    private var panelStroke: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(OnboardingPalette.panelStroke, lineWidth: 1)
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
                            .regular.tint(Color.accentColor.opacity(0.42)).interactive(),
                            in: .capsule
                        )
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
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
        Group {
            if isLoading {
                ProgressView()
                    .tint(OnboardingPalette.primaryText)
            } else {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(OnboardingPalette.primaryText)
            }
        }
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
                            .frame(width: isActive ? 48 : 20, height: 10)
                            .background {
                                if #available(iOS 26.0, *) {
                                    Color.clear
                                        .glassEffect(
                                            .regular.tint(Color.white.opacity(isActive ? 0.07 : 0.03)).interactive(),
                                            in: .capsule
                                        )
                                } else {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(isActive ? 0.12 : 0.05))
                                }
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(isActive ? 0.92 : 0.24))
                                    .padding(isActive ? 2 : 3)
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(isActive ? 0.14 : 0.08), lineWidth: 1)
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
#endif
