import SwiftUI

struct TVTopNavigationItem: View {
    @FocusState private var isFocused: Bool

    let destination: TVRootDestination
    let isHighlighted: Bool
    let isSelected: Bool
    let appearance: TVTopNavigationAppearance
    let highlightNamespace: Namespace.ID
    let focusedDestination: FocusState<TVRootDestination?>.Binding
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: destination.systemImage)
                .font(.system(size: 18, weight: .semibold))

            Text(destination.title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(labelColor)
        .padding(.horizontal, 24)
        .frame(height: ReelFinTheme.tvTopNavigationItemHeight)
        .frame(minWidth: destination == .search ? 170 : 210)
        .background { highlightBackground }
        .contentShape(Capsule(style: .continuous))
        .scaleEffect(isFocused ? 1.03 : 1)
        .shadow(
            color: .black.opacity(isHighlighted ? (isFocused ? 0.18 : 0.10) : 0.04),
            radius: isFocused ? 18 : (isHighlighted ? 10 : 0),
            x: 0,
            y: isFocused ? 8 : 4
        )
        .focusable(true, interactions: .activate)
        .focused(focusedDestination, equals: destination)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onTapGesture(perform: action)
        .animation(ReelFinTheme.tvFocusSpring, value: isFocused)
        .animation(ReelFinTheme.tvFocusSpring, value: isHighlighted)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityRepresentation { Button(destination.title, action: action) }
    }

    private var labelColor: Color {
        isHighlighted ? appearance.highlightLabelColor : Color.white.opacity(isSelected ? 0.98 : 0.94)
    }

    @ViewBuilder
    private var highlightBackground: some View {
        if isHighlighted {
            if #available(tvOS 26.0, *) {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                appearance.highlightBaseColor,
                                appearance.highlightGlowColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .glassEffect(activeGlass, in: .capsule)
                    }
                    .glassEffectID("tv-top-nav-highlight", in: highlightNamespace)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.34), appearance.railStrokeColor.opacity(0.28)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
            } else {
                Capsule(style: .continuous)
                    .fill(appearance.highlightBaseColor.opacity(isFocused ? 1 : 0.92))
            }
        }
    }

    @available(tvOS 26.0, *)
    private var activeGlass: Glass {
        let tint = appearance.highlightGlassTint.opacity(isFocused ? 0.42 : 0.28)
        return Glass.regular.tint(tint).interactive()
    }
}
