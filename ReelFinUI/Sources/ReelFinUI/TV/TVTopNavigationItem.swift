import SwiftUI

struct TVTopNavigationItem: View {
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
            .focusable(true, interactions: .activate)
            .focused(focusedDestination, equals: destination)
            .focusEffectDisabled(true)
            .onTapGesture(perform: action)
            .animation(ReelFinTheme.tvFocusSpring, value: isHighlighted)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityRepresentation { Button(destination.title, action: action) }
    }

    private var labelColor: Color {
        isHighlighted ? appearance.highlightLabelColor : Color.white.opacity(isSelected ? 0.98 : 0.94)
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
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
                .matchedGeometryEffect(id: "tv-top-nav-highlight", in: highlightNamespace)
        }
    }
}
