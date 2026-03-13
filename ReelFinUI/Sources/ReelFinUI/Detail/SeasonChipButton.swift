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
            .foregroundStyle(isFocused ? .white : (isSelected ? .white : .white.opacity(0.55)))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isFocused ? 0.16 : (isSelected ? 0.10 : 0.04)))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.28 : (isSelected ? 0.14 : 0.08)), lineWidth: 1)
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(isFocused ? 1.04 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.28 : 0.12), radius: isFocused ? 20 : 8, x: 0, y: isFocused ? 10 : 4)
            .focusable(true, interactions: .activate)
            .focused($isFocused)
            .focusEffectDisabled(true)
            .onTapGesture(perform: action)
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isFocused)
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
            .background(iosBackground, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(isFocused ? 0.36 : 0.14), lineWidth: 0.8)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isFocused ? 1.02 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.24 : 0.10), radius: isFocused ? 14 : 8, x: 0, y: 6)
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Current season" : "")
    }

    private var iosForeground: Color {
        if isSelected { return Color.black.opacity(0.90) }
        return isFocused ? .white : .white.opacity(0.86)
    }

    private var iosBackground: Color {
        if isSelected { return .white }
        return isFocused ? Color.white.opacity(0.18) : Color.white.opacity(0.10)
    }
    #endif
}
