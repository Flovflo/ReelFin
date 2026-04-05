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
            .offset(y: isHighlighted ? -1 : 0)
            .tvMotionFocus(.navItem, isFocused: isFocused, isSelected: isSelected)
            .focusable(true, interactions: .activate)
            .focused(focusedDestination, equals: destination)
            .focused($isFocused)
            .focusEffectDisabled(true)
            .onTapGesture(perform: action)
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
            .fill(Color.white.opacity(isSelected ? 0.94 : 0.82))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.42 : 0.18), lineWidth: 1)
            }
    }
}
