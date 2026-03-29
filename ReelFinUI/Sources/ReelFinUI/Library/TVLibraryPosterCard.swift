#if os(tvOS)
import Shared
import SwiftUI

struct TVLibraryPosterCard: View {
    @FocusState private var isFocused: Bool

    let item: MediaItem
    let dependencies: ReelFinDependencies
    let onFocus: (MediaItem) -> Void
    let onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ReelFinTheme.tvCardMetadataSpacing) {
            PosterCardArtworkView(
                item: item,
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline,
                layoutStyle: .grid
            )
            .tvFocusElevation(focused: isFocused, cornerRadius: ReelFinTheme.cardCornerRadius)

            PosterCardMetadataView(
                item: item,
                layoutStyle: .grid,
                titleLineLimit: 2
            )
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
            .opacity(isFocused ? 1 : 0.74)
        }
        .padding(10)
        .background { focusSurface }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .scaleEffect(isFocused ? 1.02 : 1)
        .focusable(true, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onTapGesture { onSelect(item) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("media_card_button_\(item.id)")
        .onChange(of: isFocused) { _, focused in
            guard focused else { return }
            onFocus(item)
        }
        .animation(ReelFinTheme.tvFocusSpring, value: isFocused)
    }

    @ViewBuilder
    private var focusSurface: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
    }
}
#endif
