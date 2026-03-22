#if os(tvOS)
import SwiftUI

struct TVLibraryPillButton: View {
    @FocusState private var isFocused: Bool

    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
            }

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
        }
        .font(.system(size: 21, weight: .semibold, design: .rounded))
        .foregroundStyle(isFocused || isSelected ? Color.black.opacity(0.92) : Color.white.opacity(0.92))
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .compositingGroup()
        .background { background }
        .contentShape(Capsule(style: .continuous))
        .scaleEffect(isFocused ? 1.04 : 1)
        .focusable(true, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onTapGesture(perform: action)
        .animation(ReelFinTheme.tvFocusSpring, value: isFocused)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityRepresentation { Button(title, action: action) }
    }

    private var background: some View {
        Capsule(style: .continuous)
            .fill(baseFill)
            .background { glassLayer }
            .overlay {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(isFocused || isSelected ? 0.14 : 0.06), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(isFocused ? 0.18 : 0.10),
                radius: isFocused ? 18 : 10,
                x: 0,
                y: isFocused ? 8 : 4
            )
    }

    private var baseFill: LinearGradient {
        let activeOpacity = isFocused ? 0.96 : 0.88
        let selectedOpacity = isSelected ? 0.78 : 0.14
        let upper = isFocused || isSelected ? Color.white.opacity(activeOpacity) : Color.white.opacity(selectedOpacity)
        let lower = isFocused || isSelected ? Color.white.opacity(activeOpacity - 0.10) : Color.white.opacity(0.08)
        return LinearGradient(colors: [upper, lower], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder
    private var glassLayer: some View {
        if #available(tvOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.clear)
                .glassEffect(
                    Glass.regular.tint(Color.white.opacity(isFocused ? 0.16 : (isSelected ? 0.12 : 0.08))).interactive(),
                    in: .capsule
                )
        }
    }

    private var strokeColor: Color {
        Color.white.opacity(isFocused ? 0.26 : (isSelected ? 0.18 : 0.10))
    }
}
#endif
