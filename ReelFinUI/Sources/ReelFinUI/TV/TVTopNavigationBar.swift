import SwiftUI

struct TVTopNavigationBar: View {
    @Namespace private var highlightNamespace

    @Binding var selectedDestination: TVRootDestination
    let focusedDestination: FocusState<TVRootDestination?>.Binding

    var body: some View {
        Group {
            if #available(tvOS 26.0, *) {
                GlassEffectContainer(spacing: 10) { navigationItems }
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
                    highlightNamespace: highlightNamespace,
                    focusedDestination: focusedDestination,
                    action: { selectedDestination = destination }
                )
            }
        }
        .padding(.horizontal, 8)
    }

    private var railBackground: some View {
        Color.clear
            .reelFinGlassCapsule(
                tint: Color(red: 0.79, green: 0.60, blue: 0.26).opacity(0.22),
                stroke: Color.white.opacity(0.14),
                shadowOpacity: 0,
                shadowRadius: 0,
                shadowYOffset: 0
            )
    }

    private var railStroke: some View {
        Capsule(style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
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
