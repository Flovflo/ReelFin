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
        .tvMotionFocus(.libraryPoster, isFocused: isFocused)
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
    }

    @ViewBuilder
    private var focusSurface: some View {
        Color.clear.tvCardSurface(focused: isFocused, cornerRadius: 24)
    }
}
#endif
