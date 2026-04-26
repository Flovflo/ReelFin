import SwiftUI

struct NativePlayerGlassCircleButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void
    var isProminent = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .frame(width: 64, height: 64)
                .contentShape(Circle())
                .nativePlayerGlassCircle(
                    tint: tint,
                    stroke: Color.white.opacity(isFocused ? 0.18 : 0.08),
                    shadowOpacity: isFocused ? 0.05 : 0.02,
                    shadowRadius: isFocused ? 7 : 3,
                    shadowYOffset: isFocused ? 3 : 1
                )
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .focused($isFocused)
        .nativePlayerFocusChromeDisabled()
        .scaleEffect(isFocused ? 1.025 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isFocused)
        .accessibilityLabel(accessibilityLabel)
    }

    private var tint: Color {
        isFocused ? Color.white.opacity(0.035) : (isProminent ? Color.white.opacity(0.018) : Color.white.opacity(0.012))
    }
}

struct NativePlayerGlassPillButton: View {
    let title: String
    let action: () -> Void
    var isProminent = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, isProminent ? 34 : 26)
                .frame(height: 60)
                .contentShape(Capsule())
                .nativePlayerGlassCapsule(
                    tint: tint,
                    stroke: Color.white.opacity(isFocused ? 0.18 : 0.08),
                    shadowOpacity: isFocused ? 0.05 : 0.02,
                    shadowRadius: isFocused ? 7 : 3,
                    shadowYOffset: isFocused ? 3 : 1
                )
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .focused($isFocused)
        .nativePlayerFocusChromeDisabled()
        .scaleEffect(isFocused ? 1.025 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isFocused)
        .accessibilityLabel(title)
    }

    private var tint: Color {
        isFocused ? Color.white.opacity(0.04) : (isProminent ? Color.white.opacity(0.02) : Color.white.opacity(0.012))
    }
}

private extension View {
    func nativePlayerGlassCapsule(
        tint: Color,
        stroke: Color,
        shadowOpacity: Double,
        shadowRadius: CGFloat,
        shadowYOffset: CGFloat
    ) -> some View {
        modifier(
            NativePlayerGlassCapsuleModifier(
                tint: tint,
                stroke: stroke,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowYOffset: shadowYOffset
            )
        )
    }

    func nativePlayerGlassCircle(
        tint: Color,
        stroke: Color,
        shadowOpacity: Double,
        shadowRadius: CGFloat,
        shadowYOffset: CGFloat
    ) -> some View {
        modifier(
            NativePlayerGlassCircleModifier(
                tint: tint,
                stroke: stroke,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowYOffset: shadowYOffset
            )
        )
    }
}

private struct NativePlayerGlassCapsuleModifier: ViewModifier {
    let tint: Color
    let stroke: Color
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .background { background }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowYOffset)
    }

    @ViewBuilder
    private var background: some View {
        Capsule(style: .continuous)
            .fill(tint)
            .glassEffect(.clear.interactive(), in: .capsule)
    }
}

private struct NativePlayerGlassCircleModifier: ViewModifier {
    let tint: Color
    let stroke: Color
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .background { background }
            .overlay {
                Circle()
                    .stroke(stroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowYOffset)
    }

    @ViewBuilder
    private var background: some View {
        Circle()
            .fill(tint)
            .glassEffect(.clear.interactive(), in: .circle)
    }
}

private extension View {
    @ViewBuilder
    func nativePlayerFocusChromeDisabled() -> some View {
#if os(tvOS)
        self
            .focusEffectDisabled(true)
            .hoverEffectDisabled(true)
#else
        self
#endif
    }
}
