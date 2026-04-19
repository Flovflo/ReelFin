import SwiftUI

struct SeasonChipButton: View {
    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #else
    @Environment(\.isFocused) private var isFocused
    #endif

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        #if os(tvOS)
        tvBody
        #else
        iosBody
        #endif
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: tvOS — native Apple TV+ style
    //
    // Custom focus surface to avoid the oversized system Liquid Glass capsule.
    // ─────────────────────────────────────────────────────────────────────────
    #if os(tvOS)
    private var tvBody: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .font(.system(size: 24, weight: isSelected || isFocused ? .semibold : .medium, design: .rounded))
                .foregroundStyle(tvForeground)
                .padding(.horizontal, 26)
                .frame(minHeight: 66)
                .background { tvBackground }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .tvMotionFocus(.chip, isFocused: isFocused, isSelected: isSelected)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .scaleEffect(isFocused ? 1.02 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.26 : 0.12), radius: isFocused ? 18 : 10, x: 0, y: isFocused ? 10 : 6)
        .animation(ReelFinTheme.tvFocusSpring, value: isFocused)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Current season" : "")
    }
    #endif

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: iOS
    // ─────────────────────────────────────────────────────────────────────────
    #if !os(tvOS)
    private var iosBody: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(iosForeground)
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .background { iosBackground }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isFocused ? 1.02 : 1)
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Current season" : "")
    }

    private var iosForeground: Color {
        if isSelected { return Color.black.opacity(0.92) }
        return isFocused ? .white : .white.opacity(0.86)
    }

    private var iosBackground: some View {
        Color.clear.reelFinGlassCapsule(
            interactive: true,
            tint: iosTint,
            stroke: Color.white.opacity(isFocused ? 0.22 : 0.12),
            strokeWidth: 0.8,
            shadowOpacity: isFocused ? 0.16 : 0.08,
            shadowRadius: isFocused ? 12 : 8,
            shadowYOffset: 6
        )
    }
    #endif

    #if os(tvOS)
    private var tvBackground: some View {
        Group {
            if isFocused {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.96))
            } else {
                Color.clear.reelFinGlassCapsule(
                    interactive: true,
                    tint: tvTint,
                    stroke: .clear,
                    strokeWidth: 0,
                    shadowOpacity: 0.10,
                    shadowRadius: 10,
                    shadowYOffset: 5
                )
            }
        }
    }

    private var tvForeground: Color {
        if isFocused {
            return Color.black.opacity(0.90)
        }
        if isSelected {
            return Color.white.opacity(0.98)
        }
        return Color.white.opacity(0.78)
    }

    private var tvTint: Color {
        if isSelected { return Color.white.opacity(0.20) }
        return Color.white.opacity(0.08)
    }
    #else
    private var iosTint: Color {
        if isSelected { return Color.white.opacity(0.24) }
        return isFocused ? Color.white.opacity(0.16) : Color.white.opacity(0.10)
    }
    #endif
}
