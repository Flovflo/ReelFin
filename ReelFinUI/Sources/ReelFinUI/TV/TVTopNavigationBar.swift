#if os(tvOS)
import SwiftUI

struct TVTopNavigationBar: View {
    private let railInset: CGFloat = 6

    @Namespace private var highlightNamespace
    @State private var visualHighlightedDestination: TVRootDestination?

    @Binding var selectedDestination: TVRootDestination
    let focusedDestination: FocusState<TVRootDestination?>.Binding
    let appearance: TVTopNavigationAppearance
    let onMoveCommand: (TVRootDestination, MoveCommandDirection) -> Void

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
        HStack(spacing: 16) {
            primaryNavigationItems
                .padding(.horizontal, railInset)
                .padding(.vertical, railInset)
                .frame(height: ReelFinTheme.tvTopNavigationBarHeight)
                .background(capsuleRailBackground)
                .overlay(capsuleRailStroke)
                .clipShape(Capsule(style: .continuous))
                .shadow(color: .black.opacity(0.30), radius: 28, x: 0, y: 12)

            isolatedSearchItem
                .padding(railInset)
                .frame(
                    width: ReelFinTheme.tvTopNavigationBarHeight,
                    height: ReelFinTheme.tvTopNavigationBarHeight
                )
                .background(circleRailBackground)
                .overlay(circleRailStroke)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.30), radius: 28, x: 0, y: 12)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var primaryNavigationItems: some View {
        HStack(spacing: 8) {
            ForEach(TVTopNavigationLayout.primaryDestinations, id: \.self) { destination in
                navigationItem(destination)
            }
        }
    }

    private var isolatedSearchItem: some View {
        navigationItem(TVTopNavigationLayout.isolatedDestination, compact: true)
    }

    private func navigationItem(
        _ destination: TVRootDestination,
        compact: Bool = false
    ) -> some View {
        TVTopNavigationItem(
            destination: destination,
            isCompact: compact,
            isHighlighted: renderedHighlightedDestination == destination,
            isSelected: selectedDestination == destination,
            appearance: appearance,
            highlightNamespace: highlightNamespace,
            focusedDestination: focusedDestination,
            onMoveCommand: onMoveCommand,
            action: {
                withAnimation(highlightAnimation) {
                    selectedDestination = destination
                }
            }
        )
    }

    private var capsuleRailBackground: some View {
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

    private var capsuleRailStroke: some View {
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

    private var circleRailBackground: some View {
        Group {
            if #available(tvOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        Glass.regular.tint(appearance.railTint.color(opacity: 0.22)),
                        in: .circle
                    )
            } else {
                Circle().fill(appearance.railTint.color(opacity: 0.18))
            }
        }
    }

    private var circleRailStroke: some View {
        Circle()
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
        .easeOut(duration: 0.16)
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
#endif
