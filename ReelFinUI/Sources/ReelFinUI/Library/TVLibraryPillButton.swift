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
        .scaleEffect(isFocused ? 1.01 : 1)
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
        if isHighlighted {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.94))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                }
                .shadow(color: .black.opacity(isFocused ? 0.22 : 0.16), radius: isFocused ? 14 : 10, x: 0, y: isFocused ? 8 : 6)
        }
    }

    private var isHighlighted: Bool {
        isFocused || isSelected
    }
}
#endif
