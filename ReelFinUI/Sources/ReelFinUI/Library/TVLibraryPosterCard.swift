#if os(tvOS)
import Shared
import SwiftUI

struct TVLibraryPosterCard: View {
    @FocusState private var isFocused: Bool
    @State private var isActivating = false

    let item: MediaItem
    let dependencies: ReelFinDependencies
    let onFocus: (MediaItem) -> Void
    var onMoveUp: (() -> Void)? = nil
    let onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ReelFinTheme.tvCardMetadataSpacing) {
            PosterCardArtworkView(
                item: item,
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline,
                layoutStyle: .grid
            )
            .clipShape(surfaceShape)

            PosterCardMetadataView(
                item: item,
                layoutStyle: .grid,
                titleLineLimit: 2
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 0)
            .opacity(isFocused ? 1 : 0.74)
        }
        .frame(width: cardContentWidth, alignment: .leading)
        .background { focusSurface }
        .clipShape(surfaceShape)
        .contentShape(surfaceShape)
        .tvMotionFocus(.libraryPoster, isFocused: isFocused)
        .scaleEffect(isActivating ? 1.03 : 1)
        .shadow(
            color: .black.opacity(isFocused ? 0.34 : 0.16),
            radius: isFocused ? 24 : 14,
            x: 0,
            y: isFocused ? 14 : 8
        )
        .focusable(true, interactions: .activate)
        .onMoveCommand(perform: handleMoveCommand)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onTapGesture(perform: handleActivation)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("media_card_button_\(item.id)")
        .onChange(of: isFocused) { _, focused in
            guard focused else { return }
            onFocus(item)
        }
        .animation(TVMotion.focusAnimation, value: isFocused)
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isActivating)
    }

    @ViewBuilder
    private var focusSurface: some View {
        if #available(tvOS 26.0, *) {
            Color.clear
                .glassEffect(
                    Glass.regular
                        .tint(Color.white.opacity(isFocused ? 0.16 : 0.05))
                        .interactive(),
                    in: .rect(cornerRadius: surfaceCornerRadius)
                )
                .overlay {
                    surfaceShape
                        .stroke(surfaceStroke, lineWidth: isFocused ? 1.35 : 0.9)
                }
        } else {
            Color.clear.tvCardSurface(focused: isFocused, cornerRadius: surfaceCornerRadius)
        }
    }

    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
    }

    private var surfaceStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isFocused ? 0.36 : 0.14),
                Color.white.opacity(isFocused ? 0.12 : 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardContentWidth: CGFloat {
        PosterCardMetrics.posterWidth(for: .grid, compact: false)
    }

    private var surfaceCornerRadius: CGFloat {
        24
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard direction == .up else { return }
        onMoveUp?()
    }

    private func handleActivation() {
        guard !isActivating else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
            isActivating = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 105_000_000)
            onSelect(item)
            isActivating = false
        }
    }
}
#endif
