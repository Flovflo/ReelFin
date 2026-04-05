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
        Text(title)
            .font(.system(size: 24, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected || isFocused ? Color.black.opacity(0.92) : Color.white.opacity(0.72))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background { tvBackground }
            .contentShape(Capsule(style: .continuous))
            .tvMotionFocus(.chip, isFocused: isFocused, isSelected: isSelected)
            .focusable(true, interactions: .activate)
            .focused($isFocused)
            .focusEffectDisabled(true)
            .onTapGesture(perform: action)
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
            if #available(tvOS 26.0, *) {
                Capsule(style: .continuous)
                    .fill(isFocused || isSelected ? Color.white.opacity(0.08) : .clear)
                    .glassEffect(
                        Glass.regular
                            .tint(tvTint)
                            .interactive(),
                        in: .capsule
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(isFocused ? 0.26 : (isSelected ? 0.16 : 0.10)), lineWidth: 1)
                    }
            } else {
                Color.clear.reelFinGlassCapsule(
                    interactive: true,
                    tint: tvTint,
                    stroke: Color.white.opacity(isFocused ? 0.26 : (isSelected ? 0.16 : 0.10)),
                    shadowOpacity: isFocused ? 0.18 : 0.10,
                    shadowRadius: isFocused ? 18 : 10,
                    shadowYOffset: isFocused ? 8 : 4
                )
            }
        }
    }

    private var tvTint: Color {
        if isFocused { return Color.white.opacity(0.26) }
        if isSelected { return Color.white.opacity(0.18) }
        return Color.white.opacity(0.06)
    }
    #else
    private var iosTint: Color {
        if isSelected { return Color.white.opacity(0.24) }
        return isFocused ? Color.white.opacity(0.16) : Color.white.opacity(0.10)
    }
    #endif
}
