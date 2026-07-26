#if os(tvOS)
import SwiftUI

struct TVLibraryPillButton: View {
    @Environment(\.tvTopNavigationFocusAction) private var requestTopNavigationFocus
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var isFocused: Bool

    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    var topNavigationDestination: TVRootDestination? = nil
    var allowsTopNavigationRedirect = true
    var focusedControl: FocusState<TVLibraryControlFocus?>.Binding? = nil
    var focusID: TVLibraryControlFocus? = nil
    let action: () -> Void

    var body: some View {
        focusableContent
    }

    private var labelColor: Color {
        if controlPresentation == .opaque {
            return ReelFinTheme.editorialPrimaryText
        }
        return isHighlighted ? Color.black.opacity(0.92) : Color.white.opacity(0.94)
    }

    @ViewBuilder
    private var highlightBackground: some View {
        switch controlPresentation {
        case .interactiveGlass:
            Color.clear
                .glassEffect(
                    Glass.regular.tint(backgroundTint).interactive(),
                    in: .capsule
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(borderColor, lineWidth: isFocused ? 1.2 : 1)
                }
                .shadow(
                    color: .black.opacity(isFocused ? 0.22 : 0.12),
                    radius: isFocused ? 16 : 10,
                    x: 0,
                    y: isFocused ? 9 : 5
                )
        case .opaque:
            Capsule(style: .continuous)
                .fill(ReelFinTheme.editorialOpaqueFallback)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            Color.white.opacity(isHighlighted ? 0.44 : 0.28),
                            lineWidth: isFocused ? 1.4 : 1.2
                        )
                }
                .shadow(
                    color: .black.opacity(isFocused ? 0.22 : 0.12),
                    radius: isFocused ? 16 : 10,
                    x: 0,
                    y: isFocused ? 9 : 5
                )
        case .passiveGlass:
            Color.clear
                .glassEffect(
                    Glass.regular.tint(backgroundTint),
                    in: .capsule
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(borderColor, lineWidth: isFocused ? 1.2 : 1)
                }
        }
    }

    private var controlPresentation: EditorialGlassPresentation {
        EditorialGlassRole.compactControl.presentation(
            reduceTransparency: reduceTransparency
        )
    }

    private var isHighlighted: Bool {
        isFocused || isSelected
    }

    private var backgroundTint: Color {
        if isFocused && isSelected {
            return Color.white.opacity(0.96)
        }
        if isSelected {
            return Color.white.opacity(0.88)
        }
        if isFocused {
            return Color.white.opacity(0.38)
        }
        return ReelFinTheme.editorialGlassTint
    }

    private var borderColor: Color {
        if isFocused && isSelected {
            return Color.white.opacity(0.44)
        }
        if isSelected {
            return Color.white.opacity(0.30)
        }
        if isFocused {
            return Color.white.opacity(0.32)
        }
        return Color.white.opacity(0.10)
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard direction == .up, allowsTopNavigationRedirect, let topNavigationDestination else { return }
        requestTopNavigationFocus?(topNavigationDestination)
    }

    @ViewBuilder
    private var focusableContent: some View {
        if let focusedControl, let focusID {
            content
                .focused(focusedControl, equals: focusID)
        } else {
            content
        }
    }

    private var content: some View {
        Button(action: action) {
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
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .scaleEffect(isFocused ? 1.02 : 1)
        .onMoveCommand(perform: handleMoveCommand)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .animation(ReelFinTheme.tvFocusSpring, value: isFocused)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
