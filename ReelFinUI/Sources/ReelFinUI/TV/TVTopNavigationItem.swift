#if os(tvOS)
import SwiftUI

struct TVTopNavigationItem: View {
    @FocusState private var isFocused: Bool

    let destination: TVRootDestination
    let isCompact: Bool
    let isHighlighted: Bool
    let isSelected: Bool
    let appearance: TVTopNavigationAppearance
    let highlightNamespace: Namespace.ID
    let focusedDestination: FocusState<TVRootDestination?>.Binding
    let onMoveCommand: (TVRootDestination, MoveCommandDirection) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(labelColor)
                .frame(
                    width: isCompact ? ReelFinTheme.tvTopNavigationItemHeight : nil,
                    height: ReelFinTheme.tvTopNavigationItemHeight
                )
                .frame(minWidth: isCompact ? nil : minimumWidth)
                .background { highlightBackground }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .scaleEffect(isFocused ? 1.02 : (isHighlighted ? 1.01 : 1))
        .tvMotionFocus(.navItem, isFocused: isFocused, isSelected: isSelected)
        .focused(focusedDestination, equals: destination)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .onMoveCommand { direction in
            guard direction == .up || direction == .down else { return }
            onMoveCommand(destination, direction)
        }
        .animation(ReelFinTheme.tvFocusSpring, value: isHighlighted)
        .animation(ReelFinTheme.tvFocusSpring, value: isFocused)
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var label: some View {
        if isCompact {
            Image(systemName: destination.systemImage)
                .font(.system(size: 25, weight: .semibold))
        } else {
            Label(destination.title, systemImage: destination.systemImage)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 24)
        }
    }

    private var labelColor: Color {
        isHighlighted ? appearance.highlightLabelColor : Color.white.opacity(isSelected ? 0.98 : 0.94)
    }

    private var minimumWidth: CGFloat {
        switch destination {
        case .watchNow:
            return 210
        case .search:
            return 170
        case .library:
            return 210
        }
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
                    .stroke(Color.white.opacity(isFocused ? 0.42 : 0.20), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(isFocused ? 0.24 : 0.18),
                radius: 14,
                x: 0,
                y: 8
            )
            .matchedGeometryEffect(id: "tv-top-nav-highlight", in: highlightNamespace)
    }
}
#endif
