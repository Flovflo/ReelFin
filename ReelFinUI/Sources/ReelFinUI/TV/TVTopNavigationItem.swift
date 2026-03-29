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
        Label(destination.title, systemImage: destination.systemImage)
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(labelColor)
            .padding(.horizontal, 24)
            .frame(height: ReelFinTheme.tvTopNavigationItemHeight)
            .frame(minWidth: destination == .search ? 170 : 210)
            .background { highlightBackground }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(isFocused ? 1.02 : (isHighlighted ? 1.01 : 1))
            .offset(y: isHighlighted ? -1 : 0)
            .focusable(true, interactions: .activate)
            .focused(focusedDestination, equals: destination)
            .focused($isFocused)
            .focusEffectDisabled(true)
            .onTapGesture(perform: action)
            .animation(ReelFinTheme.tvFocusSpring, value: isHighlighted)
            .animation(ReelFinTheme.tvFocusSpring, value: isFocused)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityRepresentation { Button(destination.title, action: action) }
    }

    private var labelColor: Color {
        isHighlighted ? appearance.highlightLabelColor : Color.white.opacity(isSelected ? 0.98 : 0.94)
    }

    @ViewBuilder
    private var highlightBackground: some View {
        if isHighlighted {
            selectedCapsule
        }
    }

    @ViewBuilder
    private var selectedCapsule: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.94))
            .overlay {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.20), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isFocused ? 0.24 : 0.18), radius: isFocused ? 14 : 10, x: 0, y: isFocused ? 8 : 6)
            .matchedGeometryEffect(id: "tv-top-nav-highlight", in: highlightNamespace)
    }
}
