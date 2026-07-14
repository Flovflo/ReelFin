#if os(tvOS)
import Shared
import SwiftUI

struct TVLibraryPosterCard: View {
    @State private var isActivating = false

    let item: MediaItem
    let dependencies: ReelFinDependencies
    let isFocused: Bool
    var namespace: Namespace.ID? = nil
    var transitionSourceID: String? = nil
    let onFocus: (MediaItem) -> Void
    var onMoveUp: (() -> Void)? = nil
    let onSelect: (MediaItem) -> Void

    var body: some View {
        Button(action: handleActivation) {
            VStack(alignment: .leading, spacing: ReelFinTheme.tvCardMetadataSpacing) {
                PosterCardArtworkView(
                    item: item,
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline,
                    layoutStyle: .grid,
                    namespace: namespace,
                    transitionSourceID: transitionSourceID
                )
                .clipShape(surfaceShape)

                PosterCardMetadataView(
                    item: item,
                    layoutStyle: .grid,
                    titleLineLimit: 2
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
                .opacity(isFocused ? 1 : 0.74)
            }
            .frame(width: cardContentWidth, alignment: .leading)
            .background { focusSurface }
            .clipShape(surfaceShape)
            .contentShape(surfaceShape)
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .tvMotionFocus(.libraryPoster, isFocused: isFocused)
        .scaleEffect(isActivating ? TVFocusGeometry.libraryActivationScale : 1)
        .shadow(
            color: .black.opacity(isFocused ? TVFocusGeometry.focusedShadowOpacity : 0.16),
            radius: isFocused ? TVFocusGeometry.focusedShadowRadius : 28,
            x: 0,
            y: isFocused ? TVFocusGeometry.focusedShadowY : 16
        )
        .onMoveCommand(perform: handleMoveCommand)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("media_card_button_\(item.id)")
        .onChange(of: isFocused) { _, focused in
            guard focused else { return }
            onFocus(item)
        }
        .animation(.easeOut(duration: 0.12), value: isActivating)
    }

    @ViewBuilder
    private var focusSurface: some View {
        if #available(tvOS 26.0, *) {
            // Liquid Glass ONLY on the focused cell: interactive glass is a live backdrop-sampling
            // layer, and one per visible grid cell made whole library pages heavy. Resting cells
            // get a cheap fill + stroke that reads identically from the couch.
            if isFocused {
                Color.clear
                    .glassEffect(
                        Glass.regular
                            .tint(Color.white.opacity(0.18)),
                        in: .rect(cornerRadius: surfaceCornerRadius)
                    )
                    .overlay {
                        surfaceShape
                            .stroke(surfaceStroke, lineWidth: TVFocusGeometry.focusedStrokeWidth)
                    }
            } else {
                surfaceShape
                    .fill(Color.white.opacity(0.05))
                    .overlay {
                        surfaceShape
                            .stroke(surfaceStroke, lineWidth: 0.9)
                    }
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
                Color.white.opacity(isFocused ? TVFocusGeometry.focusedStrokeOpacity : 0.14),
                Color.white.opacity(isFocused ? 0.12 : 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardContentWidth: CGFloat {
        240
    }

    private var surfaceCornerRadius: CGFloat {
        26
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard direction == .up else { return }
        onMoveUp?()
    }

    private func handleActivation() {
        guard !isActivating else { return }
        withAnimation(.easeOut(duration: 0.10)) {
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
