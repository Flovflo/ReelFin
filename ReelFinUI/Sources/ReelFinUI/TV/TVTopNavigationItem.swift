#if os(tvOS)
import SwiftUI

struct TVTopNavigationItem: View {
    @Environment(\.isFocused) private var isFocused

    let destination: TVRootDestination
    let isHighlighted: Bool
    let isSelected: Bool
    let appearance: TVTopNavigationAppearance
    let highlightNamespace: Namespace.ID
    let focusedDestination: FocusState<TVRootDestination?>.Binding
    let isFocusable: Bool
    let onMoveDown: () -> Void
    let action: () -> Void

    var body: some View {
        Label(destination.title, systemImage: destination.systemImage)
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(labelColor)
            .padding(.horizontal, 18)
            .frame(height: ReelFinTheme.tvTopNavigationItemHeight)
            .frame(minWidth: minimumWidth)
            .background { highlightBackground }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(isFocused ? 1.02 : (isHighlighted ? 1.01 : 1))
            .offset(y: isHighlighted ? -1 : 0)
            .tvMotionFocus(.navItem, isFocused: isFocused, isSelected: isSelected)
            .focusable(isFocusable, interactions: .activate)
            .focused(focusedDestination, equals: destination)
            .focusEffectDisabled(true)
            .onMoveCommand(perform: handleMoveCommand)
            .onTapGesture(perform: action)
            .animation(ReelFinTheme.tvFocusSpring, value: isHighlighted)
            .animation(ReelFinTheme.tvFocusSpring, value: isFocused)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("tv_top_navigation_\(destination.rawValue)")
            .accessibilityValue(isFocused ? "focused" : "unfocused")
            .accessibilityRepresentation {
                Button(destination.title, action: action)
                    .accessibilityIdentifier("tv_top_navigation_\(destination.rawValue)")
                    .accessibilityValue(isFocused ? "focused" : "unfocused")
            }
    }

    private var labelColor: Color {
        isFocused ? appearance.highlightLabelColor : Color.white.opacity(isSelected ? 0.98 : 0.94)
    }

    private var minimumWidth: CGFloat {
        switch destination {
        case .watchNow:
            return 184
        case .search:
            return 150
        case .library:
            return 184
        }
    }

    @ViewBuilder
    private var highlightBackground: some View {
        if isSelected || isFocused {
            selectedCapsule
        }
    }

    @ViewBuilder
    private var selectedCapsule: some View {
        Capsule(style: .continuous)
            .fill(backgroundTint)
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.42 : 0.16), lineWidth: isFocused ? 1 : 0.9)
            }
            .shadow(
                color: .black.opacity(isFocused ? 0.24 : 0.10),
                radius: isFocused ? 14 : 6,
                x: 0,
                y: isFocused ? 8 : 3
            )
            .matchedGeometryEffect(id: "tv-top-nav-highlight", in: highlightNamespace)
    }

    private var backgroundTint: some ShapeStyle {
        if isFocused {
            Color.white.opacity(0.96)
        } else {
            appearance.railTint.color(opacity: isSelected ? 0.20 : 0.12)
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard direction == .down else { return }
        onMoveDown()
    }
}
#endif
