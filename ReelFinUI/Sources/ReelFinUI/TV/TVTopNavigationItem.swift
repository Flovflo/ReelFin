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
        Group {
            if #available(tvOS 26.0, *) {
                modernButton
            } else {
                legacyButton
            }
        }
    }

    private var baseButton: some View {
        Button(action: action) {
            Label(destination.title, systemImage: destination.systemImage)
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .padding(.horizontal, 24)
                .frame(height: ReelFinTheme.tvTopNavigationItemHeight)
                .frame(minWidth: destination == .search ? 170 : 210)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .focused(focusedDestination, equals: destination)
        .focusEffectDisabled(true)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @available(tvOS 26.0, *)
    @ViewBuilder
    private var modernButton: some View {
        if isHighlighted {
            baseButton
                .glassEffect(
                    Glass.regular.tint(appearance.highlightGlassTint).interactive(),
                    in: .capsule
                )
                .glassEffectID("tv-top-nav-highlight", in: highlightNamespace)
        } else {
            baseButton
                .foregroundStyle(Color.white.opacity(isSelected ? 0.98 : 0.94))
        }
    }

    @ViewBuilder
    private var legacyButton: some View {
        if isHighlighted {
            baseButton
                .foregroundStyle(appearance.highlightLabelColor)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.92))
                }
        } else {
            baseButton
                .foregroundStyle(Color.white.opacity(isSelected ? 0.98 : 0.94))
        }
    }
}
