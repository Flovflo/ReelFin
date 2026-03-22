import ImageCache
import JellyfinAPI
import PlaybackEngine
import Shared
import SwiftUI
#if os(iOS)
import UIKit
#endif

private enum DetailHeroAction: Hashable {
    case previous
    case play
    case watchlist
    case watched
    case next
}

private struct DetailNavigationContext: Equatable {
    var title: String?
    var items: [MediaItem]

    static let empty = DetailNavigationContext(title: nil, items: [])
}

private let rowContentHorizontalPadding: CGFloat = 6
private let rowContentVerticalPadding: CGFloat = 6

struct DetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel: DetailViewModel
    private let dependencies: ReelFinDependencies

    @State private var playerSession: PlaybackSessionController?
    @State private var showPlayer = false
    @State private var isLoadingPlayback = false
    @State private var hasAnimatedIn = false
    @State private var navigationContext: DetailNavigationContext
    @FocusState private var focusedHeroAction: DetailHeroAction?
    @FocusState private var focusedSeasonID: String?

    init(
        dependencies: ReelFinDependencies,
        item: MediaItem,
        preferredEpisode: MediaItem? = nil,
        contextItems: [MediaItem] = [],
        contextTitle: String? = nil,
        namespace _: Namespace.ID? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: DetailViewModel(
                item: item,
                preferredEpisode: preferredEpisode,
                dependencies: dependencies
            )
        )
        _navigationContext = State(initialValue: DetailNavigationContext(title: contextTitle, items: contextItems))
        self.dependencies = dependencies
    }

    var body: some View {
        GeometryReader { proxy in
            let viewportSize = proxy.size
            let heroHeight = resolvedHeroHeight(for: viewportSize)

            ZStack(alignment: .top) {
                ReelFinTheme.pageGradient
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                        heroSection(heroHeight: heroHeight, viewportSize: viewportSize)

                        supportingContent
                            .padding(.horizontal, horizontalPadding)
                            .padding(.bottom, 96)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .navigationTitle("")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbarBackground(.hidden, for: .navigationBar)
#elseif os(tvOS)
        .toolbar(.hidden, for: .tabBar)
        .preference(key: TVTopNavigationVisibilityPreferenceKey.self, value: false)
#endif
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task {
                await DetailPresentationTelemetry.shared.markDetailVisible(for: viewModel.detail.item.id)
            }
            if !hasAnimatedIn {
                withAnimation(.easeOut(duration: 0.45)) {
                    hasAnimatedIn = true
                }
            }
#if os(tvOS)
            if focusedHeroAction == nil {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    focusedHeroAction = .play
                }
            }
#endif
        }
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .fullScreenCover(isPresented: $showPlayer, onDismiss: handlePlayerDismissal) {
            if let playerSession {
                PlayerView(session: playerSession, item: viewModel.itemToPlay)
            }
        }
    }

    private func heroSection(heroHeight: CGFloat, viewportSize: CGSize) -> some View {
        #if os(tvOS)
        tvHeroSection(heroHeight: heroHeight, viewportSize: viewportSize)
        #else
        ZStack(alignment: .bottomLeading) {
            HeroBackgroundView(
                item: viewModel.detail.item,
                heroHeight: heroHeight,
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline,
                onHeroImageVisible: {
                    Task {
                        await DetailPresentationTelemetry.shared.markHeroVisible(for: viewModel.detail.item.id)
                    }
                }
            )

            HeroMetadataColumn(
                item: viewModel.detail.item,
                preferredSource: viewModel.preferredPlaybackSource,
                playButtonLabel: viewModel.playButtonLabel,
                playbackStatusText: viewModel.playbackStatusText,
                progress: resolvedHeroProgress,
                isLoadingPlayback: isLoadingPlayback || viewModel.isWarmingPlayback,
                isInWatchlist: viewModel.isInWatchlist,
                isWatched: viewModel.detail.item.isPlayed || viewModel.isWatched,
                horizontalPadding: horizontalPadding,
                contentWidth: resolvedMetadataWidth(for: viewportSize),
                animateIn: hasAnimatedIn,
                focusedAction: $focusedHeroAction,
                onPlay: { startPlayback() },
                onToggleWatchlist: viewModel.toggleWatchlist,
                onToggleWatched: viewModel.toggleWatched
            )
            .padding(.top, heroTopPadding)
            .padding(.bottom, heroBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        #endif
    }

#if os(tvOS)
    private func tvHeroSection(heroHeight: CGFloat, viewportSize: CGSize) -> some View {
        let neighbors = heroNeighbors
        let sideWidth = tvHeroSidePreviewWidth(for: viewportSize)

        return HStack(spacing: 18) {
            if let previous = neighbors.previous {
                TVDetailContextPreviewCard(
                    item: previous,
                    edge: .leading,
                    width: sideWidth,
                    height: heroHeight * 0.94,
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline,
                    action: {
                        navigateToDetailItem(previous)
                    }
                )
                .focused($focusedHeroAction, equals: .previous)
            } else {
                Color.clear
                    .frame(width: sideWidth)
                    .allowsHitTesting(false)
            }

            ZStack(alignment: .bottomLeading) {
                HeroBackgroundView(
                    item: viewModel.detail.item,
                    heroHeight: heroHeight,
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline,
                    onHeroImageVisible: {
                        Task {
                            await DetailPresentationTelemetry.shared.markHeroVisible(for: viewModel.detail.item.id)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))

                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.06), location: 0),
                                .init(color: .clear, location: 0.22),
                                .init(color: .clear, location: 0.68),
                                .init(color: .black.opacity(0.12), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)

                HeroMetadataColumn(
                    item: viewModel.detail.item,
                    preferredSource: viewModel.preferredPlaybackSource,
                    playButtonLabel: viewModel.playButtonLabel,
                    playbackStatusText: viewModel.playbackStatusText,
                    progress: resolvedHeroProgress,
                    isLoadingPlayback: isLoadingPlayback || viewModel.isWarmingPlayback,
                    isInWatchlist: viewModel.isInWatchlist,
                    isWatched: viewModel.detail.item.isPlayed || viewModel.isWatched,
                    horizontalPadding: 0,
                    contentWidth: min(viewportSize.width * 0.38, 640),
                    animateIn: hasAnimatedIn,
                    focusedAction: $focusedHeroAction,
                    onPlay: { startPlayback() },
                    onToggleWatchlist: viewModel.toggleWatchlist,
                    onToggleWatched: viewModel.toggleWatched
                )
                .padding(.horizontal, 56)
                .padding(.top, 76)
                .padding(.bottom, 56)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 34, x: 0, y: 22)

            if let next = neighbors.next {
                TVDetailContextPreviewCard(
                    item: next,
                    edge: .trailing,
                    width: sideWidth,
                    height: heroHeight * 0.94,
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline,
                    action: {
                        navigateToDetailItem(next)
                    }
                )
                .focused($focusedHeroAction, equals: .next)
            } else {
                Color.clear
                    .frame(width: sideWidth)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
    }
#endif

    @ViewBuilder
    private var supportingContent: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            if shouldShowSeasonPicker {
                SeasonPickerView(
                    seasons: viewModel.seasons,
                    selectedSeasonID: viewModel.selectedSeason?.id,
                    focusedSeasonID: $focusedSeasonID,
                    onMoveUp: focusHeroPrimaryActionFromSeasonPicker,
                    onSelect: { season in
                        Task {
                            await viewModel.selectSeasonIfNeeded(season)
                        }
                    }
                )
            }

            if viewModel.detail.item.mediaType == .series {
                episodeSection
            } else {
                relatedSection(title: "Related")
            }

            if !viewModel.detail.cast.isEmpty {
                CastRowView(
                    cast: viewModel.detail.cast,
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline
                )
            }

            if viewModel.detail.item.mediaType == .series {
                relatedSection(title: "More Like This")
            }

            if shouldShowSkeleton {
                DetailPageSkeletonView(showsSeasonPicker: viewModel.detail.item.mediaType == .series)
            }

            if let source = viewModel.preferredPlaybackSource {
                FileDetailsSection(source: source)
            }
        }
        .opacity(hasAnimatedIn ? 1 : 0)
        .offset(y: hasAnimatedIn ? 0 : 16)
        .animation(.easeOut(duration: 0.45), value: hasAnimatedIn)
    }

    @ViewBuilder
    private var episodeSection: some View {
        if viewModel.isLoadingEpisodes && viewModel.episodes.isEmpty {
            DetailPageSkeletonView(showsSeasonPicker: false, sectionKind: .episodesOnly)
        } else if !viewModel.episodes.isEmpty {
            DetailRowContainer(
                title: "Episodes",
                subtitle: viewModel.selectedSeason?.name
            ) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: episodeCardSpacing) {
                        ForEach(viewModel.episodes) { episode in
                            EpisodeCardView(
                                episode: episode,
                                width: episodeCardWidth,
                                isSelected: episode.id == viewModel.selectedEpisodeID,
                                onSelect: {
                                    viewModel.prepareEpisodePlayback(episode)
                                    startPlayback(item: episode)
                                },
                                apiClient: dependencies.apiClient,
                                imagePipeline: dependencies.imagePipeline
                            )
                        }
                    }
                    .padding(.horizontal, rowContentHorizontalPadding)
                    .padding(.vertical, rowContentVerticalPadding)
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private func relatedSection(title: String) -> some View {
        if !viewModel.detail.similar.isEmpty {
            RelatedRowView(
                title: title,
                items: viewModel.detail.similar,
                onSelect: { item in
                    navigateToDetailItem(
                        item,
                        context: DetailNavigationContext(title: title, items: viewModel.detail.similar)
                    )
                },
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline
            )
        }
    }

    private var heroNeighbors: (previous: MediaItem?, next: MediaItem?) {
        guard navigationContext.items.count > 1,
              let currentIndex = resolvedContextIndex(for: viewModel.detail.item, items: navigationContext.items) else {
            return (nil, nil)
        }

        let previous = currentIndex > 0 ? navigationContext.items[currentIndex - 1] : nil
        let next = currentIndex < navigationContext.items.count - 1 ? navigationContext.items[currentIndex + 1] : nil
        return (previous, next)
    }

    private func resolvedContextIndex(for item: MediaItem, items: [MediaItem]) -> Int? {
        let targetID = item.id
        return items.firstIndex { candidate in
            candidate.id == targetID || candidate.parentID == targetID
        }
    }

    private func navigateToDetailItem(_ item: MediaItem, context: DetailNavigationContext? = nil) {
        navigationContext = context ?? navigationContext
        hasAnimatedIn = false
        focusedHeroAction = .play
        focusedSeasonID = nil

        let detailItem = makePresentedDetailItem(from: item)
        let preferredEpisode = item.mediaType == .episode ? item : nil
        viewModel.setDetailItem(detailItem, preferredEpisode: preferredEpisode)

        Task {
            let detailItemID = item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
            await DetailPresentationTelemetry.shared.beginNavigation(for: detailItemID)
            await viewModel.load()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.35)) {
                    hasAnimatedIn = true
                }
            }
        }
    }

    private func focusHeroPrimaryActionFromSeasonPicker() {
        focusedSeasonID = nil

        Task { @MainActor in
            focusedHeroAction = .play
        }
    }

    private func makePresentedDetailItem(from item: MediaItem) -> MediaItem {
        guard item.mediaType == .episode, let seriesID = item.parentID else {
            return item
        }

        return MediaItem(
            id: seriesID,
            name: item.seriesName ?? item.name,
            overview: item.overview,
            mediaType: .series,
            year: item.year,
            runtimeTicks: item.runtimeTicks,
            genres: item.genres,
            communityRating: item.communityRating,
            posterTag: item.seriesPosterTag ?? item.posterTag,
            backdropTag: item.backdropTag,
            libraryID: item.libraryID
        )
    }

    private func startPlayback(item: MediaItem? = nil) {
        guard !isLoadingPlayback else { return }
        let session = dependencies.makePlaybackSession()
        let targetItem = item ?? viewModel.itemToPlay

        isLoadingPlayback = true
        playerSession = session

        Task {
            do {
                try await session.load(item: targetItem)
                isLoadingPlayback = false
                showPlayer = true
            } catch {
                isLoadingPlayback = false
                await MainActor.run {
                    viewModel.errorMessage = error.localizedDescription
                    showPlayer = false
                }
            }
        }
    }

    @MainActor
    private func handlePlayerDismissal() {
        playerSession?.stop()
        playerSession = nil
        showPlayer = false
        isLoadingPlayback = false
    }

    private var shouldShowSeasonPicker: Bool {
        viewModel.detail.item.mediaType == .series && viewModel.seasons.count > 1
    }

    private var shouldShowSkeleton: Bool {
        guard viewModel.loadPhase.rawValue < DetailViewModel.LoadPhase.content.rawValue else {
            return false
        }
        guard !viewModel.isLoadingEpisodes else {
            return false
        }
        return viewModel.detail.cast.isEmpty && viewModel.detail.similar.isEmpty && viewModel.episodes.isEmpty
    }

    private var resolvedHeroProgress: Double? {
        if let playbackProgress = viewModel.playbackProgress {
            return playbackProgress.progressRatio
        }
        return viewModel.itemToPlay.playbackProgress
    }

    private var horizontalPadding: CGFloat {
#if os(tvOS)
        return ReelFinTheme.tvSectionHorizontalPadding
#else
        return horizontalSizeClass == .compact ? 24 : 40
#endif
    }

    private var sectionSpacing: CGFloat {
#if os(tvOS)
        return ReelFinTheme.tvSectionSpacing
#else
        return 28
#endif
    }

    private var heroTopPadding: CGFloat {
#if os(tvOS)
        return dynamicTypeSize.isAccessibilitySize ? 176 : 144
#else
        return horizontalSizeClass == .compact ? 120 : 136
#endif
    }

    private var heroBottomPadding: CGFloat {
#if os(tvOS)
        return 64
#else
        return 40
#endif
    }

    private var episodeCardWidth: CGFloat {
#if os(tvOS)
        return 480
#else
        return horizontalSizeClass == .compact ? 330 : 380
#endif
    }

    private var episodeCardSpacing: CGFloat {
#if os(tvOS)
        return 30
#else
        return 16
#endif
    }

    private func resolvedHeroHeight(for viewportSize: CGSize) -> CGFloat {
#if os(tvOS)
        let ratioHeight = viewportSize.height * 0.74
        return min(max(ratioHeight, 760), 980)
#else
        let ratioHeight = viewportSize.height * (horizontalSizeClass == .compact ? 0.64 : 0.68)
        if horizontalSizeClass == .compact {
            return min(max(ratioHeight, 420), 560)
        }
        return min(max(ratioHeight, 520), 700)
#endif
    }

    private func resolvedMetadataWidth(for viewportSize: CGSize) -> CGFloat {
#if os(tvOS)
        return min(viewportSize.width * 0.46, 760)
#else
        return horizontalSizeClass == .compact ? min(viewportSize.width - (horizontalPadding * 2), 540) : 620
#endif
    }

#if os(tvOS)
    private func tvHeroSidePreviewWidth(for viewportSize: CGSize) -> CGFloat {
        min(max(viewportSize.width * 0.1, 126), 160)
    }
#endif
}

private struct HeroBackgroundView: View {
    let item: MediaItem
    let heroHeight: CGFloat
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let onHeroImageVisible: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                fallbackGradient

                ambientArtwork(size: proxy.size)
                sharpArtwork(size: proxy.size)

                overlayGradients
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(height: heroHeight)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private func ambientArtwork(size: CGSize) -> some View {
        CachedRemoteImage(
            itemID: backdropItemID,
            type: preferredImageType,
            width: preferredWidth(for: size, multiplier: 1.05),
            quality: 54,
            contentMode: .fill,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
        .frame(width: size.width * 1.08, height: size.height * 1.08)
        .scaleEffect(1.03)
        .blur(radius: 28)
        .saturation(1.04)
        .opacity(0.24)
    }

    private func sharpArtwork(size: CGSize) -> some View {
        CachedRemoteImage(
            itemID: backdropItemID,
            type: preferredImageType,
            width: preferredWidth(for: size, multiplier: 1.18),
            quality: 82,
            contentMode: .fill,
            apiClient: apiClient,
            imagePipeline: imagePipeline,
            onImageLoaded: onHeroImageVisible
        )
        .frame(width: size.width, height: size.height)
        .scaleEffect(1.02)
        .opacity(0.94)
    }

    private var fallbackGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.08),
                    Color(red: 0.02, green: 0.03, blue: 0.05),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 720
            )
        }
    }

    private var overlayGradients: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.72), location: 0),
                    .init(color: Color.black.opacity(0.52), location: 0.22),
                    .init(color: Color.black.opacity(0.12), location: 0.5),
                    .init(color: .clear, location: 0.76)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.28), location: 0),
                    .init(color: .clear, location: 0.18),
                    .init(color: .clear, location: 0.52),
                    .init(color: Color.black.opacity(0.90), location: 0.88),
                    .init(color: Color.black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.40), location: 0),
                    .init(color: .clear, location: 0.16)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.black.opacity(0.12), location: 0.55),
                    .init(color: Color.black.opacity(0.74), location: 0.86),
                    .init(color: Color.black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var backdropItemID: String {
        if item.mediaType == .episode, let parentID = item.parentID {
            return parentID
        }
        return item.id
    }

    private var preferredImageType: JellyfinImageType {
        item.backdropTag == nil ? .primary : .backdrop
    }

    private func preferredWidth(for size: CGSize, multiplier: CGFloat) -> Int {
        min(Int((max(size.width, 1) * multiplier).rounded(.up)), 2_200)
    }
}

#if os(tvOS)
private struct TVDetailContextPreviewCard: View {
    @FocusState private var isFocused: Bool

    let item: MediaItem
    let edge: HorizontalEdge
    let width: CGFloat
    let height: CGFloat
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let action: () -> Void

    var body: some View {
        ZStack(alignment: overlayAlignment) {
            CachedRemoteImage(
                itemID: previewItemID,
                type: previewImageType,
                width: Int(width * 3),
                quality: 84,
                contentMode: .fill,
                apiClient: apiClient,
                imagePipeline: imagePipeline
            )
            .frame(width: width, height: height)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.38), location: 0.0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.58),
                    .init(color: .black.opacity(0.78), location: 1.0)
                ],
                startPoint: edge == .leading ? .leading : .trailing,
                endPoint: edge == .leading ? .trailing : .leading
            )

            VStack(alignment: edge == .leading ? .leading : .trailing, spacing: 10) {
                Image(systemName: edge == .leading ? "chevron.left.circle.fill" : "chevron.right.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))

                Text(previewTitle)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .minimumScaleFactor(0.88)
                    .multilineTextAlignment(edge == .leading ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = previewSubtitle {
                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(2)
                        .multilineTextAlignment(edge == .leading ? .leading : .trailing)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: overlayAlignment)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .scaleEffect(isFocused ? 1.05 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.34 : 0.22), radius: isFocused ? 24 : 14, x: 0, y: isFocused ? 16 : 10)
        .focusable(true, interactions: .activate)
        .onTapGesture(perform: action)
        .focusEffectDisabled(true)
        .focused($isFocused)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isFocused)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Open \(previewTitle)")
    }

    private var overlayAlignment: Alignment {
        edge == .leading ? .bottomLeading : .bottomTrailing
    }

    private var previewItemID: String {
        if item.mediaType == .episode, let parentID = item.parentID {
            return parentID
        }
        return item.id
    }

    private var previewImageType: JellyfinImageType {
        item.backdropTag == nil ? .primary : .backdrop
    }

    private var previewTitle: String {
        if item.mediaType == .episode {
            return item.seriesName ?? item.name
        }
        return item.name
    }

    private var previewSubtitle: String? {
        if item.mediaType == .episode,
           let season = item.parentIndexNumber,
           let episode = item.indexNumber {
            return "S\(season) E\(episode)"
        }

        if let year = item.year {
            return String(year)
        }

        return item.genres.first
    }
}
#endif

private struct HeroMetadataColumn: View {
    let item: MediaItem
    let preferredSource: MediaSource?
    let playButtonLabel: String
    let playbackStatusText: String?
    let progress: Double?
    let isLoadingPlayback: Bool
    let isInWatchlist: Bool
    let isWatched: Bool
    let horizontalPadding: CGFloat
    let contentWidth: CGFloat
    let animateIn: Bool
    let focusedAction: FocusState<DetailHeroAction?>.Binding
    let onPlay: () -> Void
    let onToggleWatchlist: () -> Void
    let onToggleWatched: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            metadataEyebrow

            Text(item.name)
                .font(titleFont)
                .foregroundStyle(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let subtitleText {
                Text(subtitleText)
                    .font(.system(size: subtitleFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HeroMetadataLine(
                primaryText: metadataSummary,
                badges: heroBadges
            )

            if let playbackStatusText, !playbackStatusText.isEmpty {
                Text(playbackStatusText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
            }

            if let progress, progress > 0 {
                HeroProgressView(progress: progress)
            }

            PrimaryActionsRow(
                playButtonLabel: playButtonLabel,
                isLoadingPlayback: isLoadingPlayback,
                isInWatchlist: isInWatchlist,
                isWatched: isWatched,
                focusedAction: focusedAction,
                onPlay: onPlay,
                onToggleWatchlist: onToggleWatchlist,
                onToggleWatched: onToggleWatched
            )

            if let overview = item.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: overviewFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 22)
        .animation(.easeOut(duration: 0.45), value: animateIn)
    }

    private var metadataEyebrow: some View {
        HStack(spacing: 10) {
            HeroEyebrowBadge(text: item.mediaType.detailDisplayName)

            if let airDayBadge, !airDayBadge.isEmpty {
                HeroEyebrowBadge(text: airDayBadge)
            }
        }
    }

    private var metadataSummary: String {
        var values: [String] = []
        if let year = item.year {
            values.append(String(year))
        }
        if let runtime = item.runtimeDisplayText {
            values.append(runtime)
        }
        if let rating = item.communityRating {
            values.append(String(format: "%.1f", rating))
        }
        if !item.genres.isEmpty {
            values.append(item.genres.prefix(2).joined(separator: " • "))
        }
        return values.joined(separator: "  ·  ")
    }

    private var heroBadges: [String] {
        var values: [String] = []

        if item.has4K {
            values.append("4K")
        }
        if item.hasDolbyVision {
            values.append("Dolby Vision")
        }
        if let audioBadge {
            values.append(audioBadge)
        }
        if item.hasClosedCaptions || ((preferredSource?.subtitleTracks.count ?? 0) > 0) {
            values.append("Subtitles")
        }
        if isWatched {
            values.append("Watched")
        }

        return values
    }

    private var airDayBadge: String? {
        guard let airDays = item.airDays, !airDays.isEmpty else { return nil }
        if airDays.count == 1 {
            return "New episode every \(airDays[0])"
        }
        return "New episodes \(airDays.joined(separator: ", "))"
    }

    private var subtitleText: String? {
        if item.mediaType == .episode, let seriesName = item.seriesName {
            return seriesName
        }
        if item.mediaType == .series, !item.genres.isEmpty {
            return item.genres.prefix(2).joined(separator: " · ")
        }
        return nil
    }

    private var audioBadge: String? {
        guard let preferredSource else { return nil }
        if let audioChannels = preferredSource.audioChannels {
            switch audioChannels {
            case 6:
                return "5.1"
            case 7, 8:
                return "7.1"
            case 2:
                return "Stereo"
            default:
                break
            }
        }

        if let codec = preferredSource.audioCodec?.uppercased(), !codec.isEmpty {
            return codec
        }

        return nil
    }

    private var titleFont: Font {
#if os(tvOS)
        return .system(size: item.name.count > 26 ? 70 : 84, weight: .bold, design: .rounded)
#else
        return .system(size: item.name.count > 32 ? 38 : 48, weight: .bold, design: .rounded)
#endif
    }

    private var subtitleFontSize: CGFloat {
#if os(tvOS)
        return 26
#else
        return 20
#endif
    }

    private var overviewFontSize: CGFloat {
#if os(tvOS)
        return 22
#else
        return 17
#endif
    }
}

private struct PrimaryActionsRow: View {
    let playButtonLabel: String
    let isLoadingPlayback: Bool
    let isInWatchlist: Bool
    let isWatched: Bool
    let focusedAction: FocusState<DetailHeroAction?>.Binding
    let onPlay: () -> Void
    let onToggleWatchlist: () -> Void
    let onToggleWatched: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            HeroPrimaryButton(
                title: playButtonLabel,
                isLoading: isLoadingPlayback,
                action: onPlay
            )
            .focused(focusedAction, equals: .play)

            HeroSecondaryButton(
                title: isInWatchlist ? "In Watchlist" : "Watchlist",
                systemImage: isInWatchlist ? "checkmark" : "plus",
                isActive: isInWatchlist,
                action: onToggleWatchlist
            )
            .focused(focusedAction, equals: .watchlist)

            HeroSecondaryButton(
                title: isWatched ? "Watched" : "Mark Watched",
                systemImage: isWatched ? "eye.fill" : "eye",
                isActive: isWatched,
                action: onToggleWatched
            )
            .focused(focusedAction, equals: .watched)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct HeroPrimaryButton: View {
    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #else
    @Environment(\.isFocused) private var isFocused
    #endif

    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
#if os(tvOS)
        HStack(spacing: 12) {
            if isLoading {
                ProgressView()
                Text("Preparing")
            } else {
                Image(systemName: "play.fill")
                Text(title)
            }
        }
        .font(.system(size: 24, weight: .semibold, design: .rounded))
        .foregroundStyle(isFocused ? Color.black.opacity(0.92) : .white)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .frame(minWidth: 318)
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .background(backgroundFill, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.22 : 0.12), lineWidth: 1)
        }
        .contentShape(Capsule(style: .continuous))
        .scaleEffect(isFocused ? 1.04 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.34 : 0.16), radius: isFocused ? 22 : 10, x: 0, y: isFocused ? 12 : 6)
        .focusable(!isLoading, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onTapGesture(perform: action)
        .disabled(isLoading)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isFocused)
        .accessibilityAddTraits(.isButton)
#else
        buttonContent
#endif
    }

    #if os(tvOS)
    private var backgroundFill: Color {
        isFocused ? .white : Color.white.opacity(0.14)
    }
    #endif

    #if os(iOS)
    private var buttonContent: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .tint(.black)
                    Text("Preparing")
                } else {
                    Image(systemName: "play.fill")
                    Text(title)
                }
            }
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.black.opacity(0.92))
            .frame(minWidth: 220, minHeight: 58)
            .padding(.horizontal, 20)
            .background(Color.white, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(isFocused ? 0.36 : 0.22), radius: isFocused ? 24 : 14, x: 0, y: isFocused ? 12 : 8)
            .scaleEffect(isFocused ? 1.035 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }
    #endif
}

private struct HeroSecondaryButton: View {
    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #else
    @Environment(\.isFocused) private var isFocused
    #endif

    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
#if os(tvOS)
        Label(title, systemImage: systemImage)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(isFocused ? 0.96 : 0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.86)
            .frame(minWidth: 180)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(backgroundFill, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(isFocused ? 1.035 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.28 : 0.14), radius: isFocused ? 18 : 10, x: 0, y: isFocused ? 10 : 6)
            .focusable(true, interactions: .activate)
            .focused($isFocused)
            .focusEffectDisabled(true)
            .onTapGesture(perform: action)
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isFocused)
            .accessibilityAddTraits(.isButton)
#else
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: buttonFontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .frame(minHeight: buttonHeight)
            .padding(.horizontal, horizontalPadding)
            .background(backgroundFill, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(borderColor, lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(isFocused ? 0.28 : 0.14), radius: isFocused ? 18 : 10, x: 0, y: isFocused ? 10 : 6)
            .scaleEffect(isFocused ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.16), value: isFocused)
#endif
    }



    #if os(tvOS)
    private var backgroundFill: Color {
        if isFocused { return Color.white.opacity(0.18) }
        if isActive { return Color.white.opacity(0.14) }
        return Color.white.opacity(0.08)
    }

    private var borderColor: Color {
        isFocused ? Color.white.opacity(0.28) : Color.white.opacity(isActive ? 0.18 : 0.10)
    }
    #endif

    #if os(iOS)
    private var backgroundFill: Color {
        isFocused ? Color.white.opacity(0.22) : Color.white.opacity(0.12)
    }

    private var borderColor: Color {
        isFocused ? Color.white.opacity(0.36) : Color.white.opacity(0.14)
    }

    private var buttonHeight: CGFloat { 54 }
    private var horizontalPadding: CGFloat { 16 }
    private var buttonFontSize: CGFloat { 16 }
    #endif
}

private struct HeroMetadataLine: View {
    let primaryText: String
    let badges: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !primaryText.isEmpty {
                Text(primaryText)
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !badges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(badges, id: \.self) { badge in
                            HeroInlineBadge(text: badge)
                        }
                    }
                }
            }
        }
    }

    private var fontSize: CGFloat {
#if os(tvOS)
        return 20
#else
        return 15
#endif
    }
}

private struct HeroEyebrowBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.10), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            }
    }

    private var fontSize: CGFloat {
#if os(tvOS)
        return 13
#else
        return 11
#endif
    }
}

private struct HeroInlineBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            }
    }

    private var fontSize: CGFloat {
#if os(tvOS)
        return 15
#else
        return 12
#endif
    }
}

private struct HeroProgressView: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white)
                            .frame(width: proxy.size.width * CGFloat(progress))
                    }
            }
            .frame(height: 6)

            Text("Progress \(Int(progress * 100))%")
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: 280, alignment: .leading)
    }

    private var fontSize: CGFloat {
#if os(tvOS)
        return 16
#else
        return 13
#endif
    }
}

private struct SeasonPickerView: View {
    #if os(tvOS)
    @FocusState private var isFocusBridgeActive: Bool
    #endif

    let seasons: [MediaItem]
    let selectedSeasonID: String?
    let focusedSeasonID: FocusState<String?>.Binding
    let onMoveUp: () -> Void
    let onSelect: (MediaItem) -> Void

    var body: some View {
        DetailRowContainer(
            title: "Seasons",
            subtitle: seasons.first(where: { $0.id == selectedSeasonID })?.name
        ) {
            #if os(tvOS)
            Color.white
                .opacity(0.001)
                .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10)
                .focusable()
                .focused($isFocusBridgeActive)
                .focusEffectDisabled(true)
                .onChange(of: isFocusBridgeActive) { _, isFocused in
                    guard isFocused else { return }
                    focusedSeasonID.wrappedValue = selectedSeasonID ?? seasons.first?.id
                }
                .onMoveCommand { direction in
                    guard direction == .up else { return }
                    onMoveUp()
                }
            #endif

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: chipSpacing) {
                    ForEach(seasons) { season in
                        SeasonChipButton(
                            title: season.name,
                            isSelected: season.id == selectedSeasonID,
                            action: {
                                onSelect(season)
                            }
                        )
                        .focused(focusedSeasonID, equals: season.id)
                        #if os(tvOS)
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            onMoveUp()
                        }
                        #endif
                    }
                }
                .padding(.horizontal, rowContentHorizontalPadding)
                .padding(.vertical, rowContentVerticalPadding)
            }
            .scrollClipDisabled()
        }
    }

    private var chipSpacing: CGFloat {
        #if os(tvOS)
        return 14
        #else
        return 12
        #endif
    }
}

private struct CastRowView: View {
    let cast: [PersonCredit]
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    var body: some View {
        DetailRowContainer(title: "Cast") {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(cast) { person in
                        #if os(tvOS)
                        TVCastRowItem(
                            person: person,
                            itemWidth: itemWidth,
                            nameFontSize: nameFontSize,
                            roleFontSize: roleFontSize,
                            apiClient: apiClient,
                            imagePipeline: imagePipeline
                        )
                        #else
                        VStack(spacing: 10) {
                            CastAvatarView(
                                person: person,
                                apiClient: apiClient,
                                imagePipeline: imagePipeline
                            )

                            Text(person.name)
                                .font(.system(size: nameFontSize, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: itemWidth)

                            if let role = person.role, !role.isEmpty {
                                Text(role)
                                    .font(.system(size: roleFontSize, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.56))
                                    .lineLimit(1)
                                    .frame(width: itemWidth)
                            }
                        }
                        .frame(width: itemWidth)
                        .accessibilityElement(children: .combine)
                        #endif
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, rowContentHorizontalPadding)
                .padding(.vertical, rowContentVerticalPadding)
            }
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var itemWidth: CGFloat {
#if os(tvOS)
        return 116
#else
        return 96
#endif
    }

    private var nameFontSize: CGFloat {
#if os(tvOS)
        return 16
#else
        return 13
#endif
    }

    private var roleFontSize: CGFloat {
#if os(tvOS)
        return 14
#else
        return 11
#endif
    }
}

#if os(tvOS)
private struct TVCastRowItem: View {
    @FocusState private var isFocused: Bool

    let person: PersonCredit
    let itemWidth: CGFloat
    let nameFontSize: CGFloat
    let roleFontSize: CGFloat
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    var body: some View {
        VStack(spacing: 10) {
            CastAvatarView(
                person: person,
                apiClient: apiClient,
                imagePipeline: imagePipeline
            )

            Text(person.name)
                .font(.system(size: nameFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: itemWidth)

            if let role = person.role, !role.isEmpty {
                Text(role)
                    .font(.system(size: roleFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .frame(width: itemWidth)
            }
        }
        .frame(width: itemWidth)
        .scaleEffect(isFocused ? 1.04 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.30 : 0.16), radius: isFocused ? 20 : 10, x: 0, y: isFocused ? 10 : 5)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled(true)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isFocused)
        .accessibilityElement(children: .combine)
    }
}
#endif

private struct CastAvatarView: View {
    let person: PersonCredit
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                }

            if person.primaryImageTag != nil {
                CachedRemoteImage(
                    itemID: person.id,
                    type: .primary,
                    width: 220,
                    quality: 78,
                    contentMode: .fill,
                    apiClient: apiClient,
                    imagePipeline: imagePipeline
                )
                .clipShape(Circle())
            } else {
                Text(initials(for: person.name))
                    .font(.system(size: monogramSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(width: avatarSize, height: avatarSize)
    }

    private var avatarSize: CGFloat {
#if os(tvOS)
        return 88
#else
        return 74
#endif
    }

    private var monogramSize: CGFloat {
#if os(tvOS)
        return 28
#else
        return 24
#endif
    }

    private func initials(for name: String) -> String {
        name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
    }
}

private struct RelatedRowView: View {
    let title: String
    let items: [MediaItem]
    let onSelect: (MediaItem) -> Void
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    var body: some View {
        DetailRowContainer(title: title) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(items) { item in
                        #if os(tvOS)
                        TVRelatedRowItem(
                            item: item,
                            apiClient: apiClient,
                            imagePipeline: imagePipeline,
                            action: { onSelect(item) }
                        )
                        #else
                        Button {
                            onSelect(item)
                        } label: {
                            PosterCardView(
                                item: item,
                                apiClient: apiClient,
                                imagePipeline: imagePipeline,
                                layoutStyle: .row,
                                focusStyle: .subtle,
                                titleLineLimit: 2
                            )
                        }
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, rowContentHorizontalPadding)
                .padding(.vertical, rowContentVerticalPadding)
            }
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

#if os(tvOS)
private struct TVRelatedRowItem: View {
    @FocusState private var isFocused: Bool

    let item: MediaItem
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PosterCardArtworkView(
                item: item,
                apiClient: apiClient,
                imagePipeline: imagePipeline,
                layoutStyle: .row,
                focusStyle: .subtle
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isFocused ? .white : .white.opacity(0.92))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: titleBlockHeight, alignment: .topLeading)

                if let year = item.year {
                    Text(String(year))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(isFocused ? 0.68 : 0.48))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            .frame(height: metadataBlockHeight, alignment: .topLeading)
        }
        .frame(width: relatedCardWidth, alignment: .leading)
        .scaleEffect(isFocused ? 1.045 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.34 : 0.18), radius: isFocused ? 26 : 12, x: 0, y: isFocused ? 16 : 8)
        .focusable(true, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onTapGesture(perform: action)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isFocused)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var relatedCardWidth: CGFloat {
        220
    }

    private var titleBlockHeight: CGFloat {
        64
    }

    private var metadataBlockHeight: CGFloat {
        96
    }
}
#endif

private struct DetailPageSkeletonView: View {
    enum SectionKind {
        case full
        case episodesOnly
    }

    let showsSeasonPicker: Bool
    let sectionKind: SectionKind

    init(showsSeasonPicker: Bool, sectionKind: SectionKind = .full) {
        self.showsSeasonPicker = showsSeasonPicker
        self.sectionKind = sectionKind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if showsSeasonPicker && sectionKind == .full {
                DetailRowContainer(title: "Seasons") {
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 132, height: 48)
                                .overlay(ShimmerView())
                        }
                    }
                }
            }

            DetailRowContainer(title: "Episodes") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                                .frame(width: skeletonCardWidth, height: skeletonCardHeight)
                                .overlay(ShimmerView())
                        }
                    }
                }
            }

            if sectionKind == .full {
                DetailRowContainer(title: "Cast") {
                    HStack(spacing: 18) {
                        ForEach(0..<6, id: \.self) { _ in
                            VStack(spacing: 12) {
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 88, height: 88)
                                    .overlay(ShimmerView().clipShape(Circle()))

                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 84, height: 14)
                                    .overlay(ShimmerView())
                            }
                        }
                    }
                }
            }
        }
    }

    private var skeletonCardWidth: CGFloat {
#if os(tvOS)
        return 470
#else
        return 330
#endif
    }

    private var skeletonCardHeight: CGFloat {
        skeletonCardWidth * 0.56 + 130
    }
}

private struct DetailRowContainer<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: subtitleFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, containerVerticalPadding)
        #if os(tvOS)
        .padding(.horizontal, rowContentHorizontalPadding)
        #endif
    }

    private var titleFontSize: CGFloat {
#if os(tvOS)
        return 24
#else
        return 20
#endif
    }

    private var subtitleFontSize: CGFloat {
#if os(tvOS)
        return 18
#else
        return 15
#endif
    }

    private var contentSpacing: CGFloat {
        #if os(tvOS)
        return 20
        #else
        return 16
        #endif
    }

    private var containerVerticalPadding: CGFloat {
        #if os(tvOS)
        return 8
        #else
        return 0
        #endif
    }
}

private struct FileDetailsSection: View {
    let source: MediaSource

    var body: some View {
        DetailRowContainer(title: "File Details") {
            #if os(tvOS)
            fileDetailsContent
            #else
            fileDetailsContent
                .padding(22)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                }
            #endif
        }
    }

    private var fileDetailsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let fileName {
                Text(fileName)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
                if let codec = codecSummary {
                    fileMetric(label: "Codec", value: codec)
                }
                if let resolution = resolutionSummary {
                    fileMetric(label: "Resolution", value: resolution)
                }
                if let frameRate = frameRateSummary {
                    fileMetric(label: "Frame Rate", value: frameRate)
                }
                if let bitrate = formattedBitrate {
                    fileMetric(label: "Bitrate", value: bitrate)
                }
                if let size = formattedFileSize {
                    fileMetric(label: "Size", value: size)
                }
            }
        }
        #if os(tvOS)
        .padding(.vertical, 4)
        #endif
    }

    private var fileName: String? {
        if let path = source.filePath, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return source.name.isEmpty ? nil : source.name
    }

    private var codecSummary: String? {
        let video = source.videoCodec?.uppercased()
        let audio = source.audioCodec?.uppercased()
        let values = [video, audio].compactMap { $0 }.filter { !$0.isEmpty }
        return values.isEmpty ? nil : values.joined(separator: " / ")
    }

    private var resolutionSummary: String? {
        guard let width = source.videoWidth, let height = source.videoHeight else { return nil }
        return "\(width)x\(height)"
    }

    private var frameRateSummary: String? {
        guard let frameRate = source.videoFrameRate, frameRate > 0 else { return nil }
        return String(format: "%.2f fps", frameRate)
    }

    private var formattedBitrate: String? {
        guard let bitrate = source.bitrate, bitrate > 0 else { return nil }
        return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
    }

    private var formattedFileSize: String? {
        guard let fileSize = source.fileSize, fileSize > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 140), spacing: 14, alignment: .leading),
            GridItem(.flexible(minimum: 140), spacing: 14, alignment: .leading)
        ]
    }

    private func fileMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))

            Text(value)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension MediaType {
    var detailDisplayName: String {
        switch self {
        case .movie:
            return "Movie"
        case .series:
            return "Series"
        case .episode:
            return "Episode"
        case .season:
            return "Season"
        case .unknown:
            return "Title"
        }
    }
}

private extension MediaItem {
    static var detailPreviewSample: MediaItem {
        MediaItem(
            id: "detail-preview",
            name: "A Very Long Movie Title Designed To Validate Wrapping Across Small Screens",
            overview: """
            This overview intentionally contains enough text to validate wrapping behavior on compact devices and large Dynamic Type sizes. It should remain fully readable, never clipped on the left or right, and naturally scroll when the content is taller than the viewport.
            """,
            mediaType: .movie,
            year: 2026,
            runtimeTicks: Int64(130 * 60 * 10_000_000),
            genres: ["Sci-Fi", "Drama"],
            communityRating: 8.4,
            posterTag: "poster",
            backdropTag: "backdrop",
            libraryID: "movies"
        )
    }
}

#Preview("Detail - iPhone") {
    NavigationStack {
        DetailView(
            dependencies: ReelFinPreviewFactory.dependencies(),
            item: .detailPreviewSample
        )
    }
}

#Preview("Detail - Accessibility") {
    NavigationStack {
        DetailView(
            dependencies: ReelFinPreviewFactory.dependencies(),
            item: .detailPreviewSample
        )
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
#Preview("Detail - Apple TV", traits: .fixedLayout(width: 1920, height: 1080)) {
    NavigationStack {
        DetailView(
            dependencies: ReelFinPreviewFactory.dependencies(),
            item: MediaItem(
                id: "series-continue-1",
                name: "Continue Series",
                overview: "A mock series container for continue watching playback resolution.",
                mediaType: .series,
                year: 2025,
                runtimeTicks: Int64(48 * 60 * 10_000_000),
                genres: ["Drama", "Thriller"],
                communityRating: 8.3,
                posterTag: "poster",
                backdropTag: "backdrop",
                libraryID: "shows"
            )
        )
    }
    .preferredColorScheme(.dark)
}
