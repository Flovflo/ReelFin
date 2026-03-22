import SwiftUI

struct TVTopNavigationBar: View {
    @Namespace private var highlightNamespace

    @Binding var selectedDestination: TVRootDestination
    let focusedDestination: FocusState<TVRootDestination?>.Binding
    let appearance: TVTopNavigationAppearance

    var body: some View {
        Group {
            if #available(tvOS 26.0, *) {
                GlassEffectContainer(spacing: 8) { navigationItems }
            } else {
                navigationItems
            }
        }
        .padding(.horizontal, ReelFinTheme.tvTopNavigationHorizontalPadding)
        .padding(.vertical, 6)
        .frame(height: ReelFinTheme.tvTopNavigationBarHeight)
        .frame(maxWidth: ReelFinTheme.tvTopNavigationBarMaxWidth)
        .background(railBackground)
        .overlay(railStroke)
        .shadow(color: .black.opacity(0.30), radius: 28, x: 0, y: 12)
    }

    private var navigationItems: some View {
        HStack(spacing: 8) {
            ForEach(TVRootDestination.allCases, id: \.self) { destination in
                TVTopNavigationItem(
                    destination: destination,
                    isHighlighted: highlightedDestination == destination,
                    isSelected: selectedDestination == destination,
                    appearance: appearance,
                    highlightNamespace: highlightNamespace,
                    focusedDestination: focusedDestination,
                    action: { selectedDestination = destination }
                )
            }
        }
        .padding(.horizontal, 8)
        .animation(ReelFinTheme.tvFocusSpring, value: highlightedDestination)
        .animation(ReelFinTheme.tvFocusSpring, value: selectedDestination)
    }

    private var railBackground: some View {
        Group {
            if #available(tvOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        Glass.regular.tint(appearance.railTint.color(opacity: 0.20)),
                        in: .capsule
                    )
            } else {
                Capsule(style: .continuous)
                    .fill(appearance.railTint.color(opacity: 0.18))
            }
        }
    }

    private var railStroke: some View {
        Capsule(style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [appearance.railStrokeColor.opacity(0.90), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var highlightedDestination: TVRootDestination {
        focusedDestination.wrappedValue ?? selectedDestination
    }
}
