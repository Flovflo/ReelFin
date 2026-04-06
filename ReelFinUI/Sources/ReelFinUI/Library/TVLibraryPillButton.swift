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
                    .symbolRenderingMode(.monochrome)
            }

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
        }
        .font(.system(size: 21, weight: .semibold, design: .rounded))
        .foregroundStyle(labelColor)
        .padding(.horizontal, 24)
        .frame(minHeight: 60)
        .background { highlightBackground }
        .contentShape(Capsule(style: .continuous))
        .scaleEffect(isFocused ? 1.02 : 1)
        .focusable(true, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onTapGesture(perform: action)
        .animation(ReelFinTheme.tvFocusSpring, value: isFocused)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityRepresentation { Button(title, action: action) }
    }

    private var labelColor: Color {
        isHighlighted ? Color.black.opacity(0.92) : Color.white.opacity(0.94)
    }

    @ViewBuilder
    private var highlightBackground: some View {
        Color.clear.reelFinGlassCapsule(
            interactive: true,
            tint: backgroundTint,
            stroke: borderColor,
            strokeWidth: isFocused ? 1.2 : 1,
            shadowOpacity: isFocused ? 0.22 : 0.12,
            shadowRadius: isFocused ? 16 : 10,
            shadowYOffset: isFocused ? 9 : 5
        )
    }

    private var isHighlighted: Bool {
        isFocused || isSelected
    }

    private var backgroundTint: Color {
        if isFocused {
            return Color.white.opacity(0.32)
        }
        if isSelected {
            return Color.white.opacity(0.22)
        }
        return Color.white.opacity(0.05)
    }

    private var borderColor: Color {
        if isFocused {
            return Color.white.opacity(0.32)
        }
        if isSelected {
            return Color.white.opacity(0.18)
        }
        return Color.white.opacity(0.10)
    }
}
#endif
