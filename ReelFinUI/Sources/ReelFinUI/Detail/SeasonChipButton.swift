import SwiftUI

struct SeasonChipButton: View {
    #if os(iOS)
    @Environment(\.isFocused) private var isFocused
    #endif

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
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
            .foregroundStyle(foregroundColor)
            .frame(minWidth: minimumWidth, minHeight: buttonHeight)
            .padding(.horizontal, horizontalPadding)
            .contentShape(Capsule())
#if os(iOS)
            .background(backgroundColor, in: Capsule())
#endif
        }
        #if os(tvOS)
        .tint(isSelected ? .white : .gray)
        .buttonStyle(.glass)
        #else
        .buttonStyle(.plain)
        #endif
#if os(iOS)
        .shadow(color: .black.opacity(isFocused ? 0.24 : 0.10), radius: isFocused ? 14 : 8, x: 0, y: 6)
        .scaleEffect(isFocused ? 1.02 : 1)
#endif
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Current season" : "")
#if os(iOS)
        .animation(.easeOut(duration: 0.16), value: isFocused)
#endif
    }

    private var foregroundColor: Color {
        #if os(tvOS)
        return isSelected ? Color.black.opacity(0.90) : Color.white.opacity(0.92)
        #else
        if isSelected {
            return Color.black.opacity(0.90)
        }
        return isFocused ? Color.white : Color.white.opacity(0.86)
        #endif
    }

    #if os(iOS)
    private var backgroundColor: Color {
        if isSelected {
            return Color.white
        }
        return isFocused ? Color.white.opacity(0.18) : Color.white.opacity(0.10)
    }
    #endif

    private var minimumWidth: CGFloat {
#if os(tvOS)
        return 160
#else
        return 0
#endif
    }

    private var buttonHeight: CGFloat {
#if os(tvOS)
        return 54
#else
        return 44
#endif
    }

    private var horizontalPadding: CGFloat {
#if os(tvOS)
        return 24
#else
        return 16
#endif
    }
}
