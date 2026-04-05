import SwiftUI

struct TVTopNavigationBar: View {
    private let railInset: CGFloat = 6

    @Namespace private var highlightNamespace
    @State private var visualHighlightedDestination: TVRootDestination?

    @Binding var selectedDestination: TVRootDestination
    let focusedDestination: FocusState<TVRootDestination?>.Binding
    let appearance: TVTopNavigationAppearance

    var body: some View {
        barContent
        .onAppear { syncVisualHighlight(animated: false) }
        .onChange(of: focusedDestination.wrappedValue) { _, _ in
            syncVisualHighlight()
        }
        .onChange(of: selectedDestination) { _, _ in
            syncVisualHighlight()
        }
        .animation(.easeInOut(duration: 0.32), value: appearance)
    }

    private var barContent: some View {
        navigationItems
            .padding(.horizontal, railInset)
            .padding(.vertical, railInset)
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: ReelFinTheme.tvTopNavigationBarHeight)
            .background(railBackground)
            .overlay(railStroke)
            .clipShape(Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.30), radius: 28, x: 0, y: 12)
    }

    private var navigationItems: some View {
        HStack(spacing: 8) {
            ForEach(TVRootDestination.allCases, id: \.self) { destination in
                TVTopNavigationItem(
                    destination: destination,
                    isHighlighted: renderedHighlightedDestination == destination,
                    isSelected: selectedDestination == destination,
                    appearance: appearance,
                    highlightNamespace: highlightNamespace,
                    focusedDestination: focusedDestination,
                    action: {
                        withAnimation(highlightAnimation) {
                            selectedDestination = destination
                        }
                    }
                )
            }
        }
    }

    private var railBackground: some View {
        Group {
            if #available(tvOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        Glass.regular.tint(appearance.railTint.color(opacity: 0.22)),
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

    private var renderedHighlightedDestination: TVRootDestination {
        visualHighlightedDestination ?? focusedDestination.wrappedValue ?? selectedDestination
    }

    private var highlightAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0.10)
    }

    private func syncVisualHighlight(animated: Bool = true) {
        let target = focusedDestination.wrappedValue ?? selectedDestination
        guard visualHighlightedDestination != target else { return }
        if animated {
            withAnimation(highlightAnimation) {
                visualHighlightedDestination = target
            }
        } else {
            visualHighlightedDestination = target
        }
    }
}
