import SwiftUI

struct TVTopNavigationBar: View {
    @Binding var selectedDestination: TVRootDestination
    let focusedDestination: FocusState<TVRootDestination?>.Binding

    var body: some View {
        Group {
            if #available(tvOS 26.0, *) {
                GlassEffectContainer(spacing: 10) {
                    navigationItems
                }
            } else {
                navigationItems
            }
        }
        .padding(.horizontal, ReelFinTheme.tvTopNavigationHorizontalPadding)
        .frame(height: ReelFinTheme.tvTopNavigationBarHeight)
        .frame(maxWidth: ReelFinTheme.tvTopNavigationBarMaxWidth)
        .background(backgroundShape)
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 10)
    }

    private var navigationItems: some View {
        HStack(spacing: 10) {
            ForEach(TVRootDestination.allCases, id: \.self) { destination in
                TVTopNavigationItem(
                    destination: destination,
                    isSelected: selectedDestination == destination,
                    focusedDestination: focusedDestination,
                    action: { selectedDestination = destination }
                )
            }
        }
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if #available(tvOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.18))
                .glassEffect(.regular.tint(Color.white.opacity(0.04)), in: .capsule)
        } else {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.34))
        }
    }
}
