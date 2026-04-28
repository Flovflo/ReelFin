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

#if os(iOS)
private struct IOSDetailCarouselEntry: Identifiable, Equatable {
    let id: String
    let displayItem: MediaItem
    let sourceItem: MediaItem
}
#endif

private let rowContentHorizontalPadding: CGFloat = 6
private let rowContentVerticalPadding: CGFloat = 6

struct DetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel: DetailViewModel
    private let dependencies: ReelFinDependencies

    @State private var playerSession: PlaybackSessionController?
    @State private var showPlayer = false
    @State private var isLoadingPlayback = false
    @State private var hasAnimatedIn = false
    @State private var tvHeroRevealProgress: CGFloat = 0
    @State private var navigationContext: DetailNavigationContext
    @State private var iosSelectedCarouselItemID: String?
    @State private var currentReturnSourceItem: MediaItem
#if os(tvOS)
    @State private var tvScrollRequest: TVDetailScrollRequest?
    @State private var tvScrollRequestID = 0
    @State private var pendingTVFocusTarget: TVDetailFocusTarget?
#endif
    @FocusState private var focusedHeroAction: DetailHeroAction?
    @FocusState private var focusedSeasonID: String?
    private let transitionNamespace: Namespace.ID?
    private let transitionSourceID: String?
    private let onDisplayedSourceItemChange: ((MediaItem) -> Void)?

    init(
        dependencies: ReelFinDependencies,
        item: MediaItem,
        preferredEpisode: MediaItem? = nil,
        contextItems: [MediaItem] = [],
        contextTitle: String? = nil,
        namespace: Namespace.ID? = nil,
        transitionSourceID: String? = nil,
        onDisplayedSourceItemChange: ((MediaItem) -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: DetailViewModel(
                item: item,
                preferredEpisode: preferredEpisode,
                dependencies: dependencies
            )
        )
        _navigationContext = State(initialValue: DetailNavigationContext(title: contextTitle, items: contextItems))
        _iosSelectedCarouselItemID = State(
            initialValue: item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
        )
        _currentReturnSourceItem = State(initialValue: preferredEpisode ?? item)
        self.dependencies = dependencies
        self.transitionNamespace = namespace
        self.transitionSourceID = transitionSourceID
        self.onDisplayedSourceItemChange = onDisplayedSourceItemChange
    }

    var body: some View {
        GeometryReader { proxy in
            let viewportSize = proxy.size
            let safeAreaTop = proxy.safeAreaInsets.top
            let heroHeight = resolvedHeroHeight(for: viewportSize)

#if os(tvOS)
            TVDetailScreen(
                heroHeight: heroHeight,
                horizontalPadding: horizontalPadding,
                sectionSpacing: sectionSpacing,
                forcedHeroCollapseProgress: focusedSeasonID == nil ? nil : 1,
                scrollRequest: tvScrollRequest,
                onScrollRequestCompleted: handleTVScrollRequestCompleted,
                hero: { stageMetrics in
                    heroSection(
                        heroHeight: heroHeight,
                        viewportSize: viewportSize,
                        safeAreaTop: safeAreaTop,
                        tvStageMetrics: stageMetrics
                    )
                },
                supportingContent: {
                    supportingContent
                }
            )
#else
            IOSDetailScreen(
                viewportSize: viewportSize,
                safeAreaTop: safeAreaTop,
                heroHeight: heroHeight,
                horizontalPadding: horizontalPadding,
                sectionSpacing: sectionSpacing,
                entries: iosCarouselEntries,
                currentItemID: viewModel.detail.item.id,
                selectedItemID: $iosSelectedCarouselItemID,
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline,
                onSelectItem: handleIOSCarouselSelection
            ) { stageMetrics in
                iosHeroSection(
                    heroHeight: heroHeight,
                    viewportSize: viewportSize,
                    safeAreaTop: safeAreaTop,
                    stageMetrics: stageMetrics
                )
            } supportingContent: {
                supportingContent
            }
#endif
        }
        .navigationTitle("")
#if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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
            onDisplayedSourceItemChange?(currentReturnSourceItem)
            animateHeroEntryIfNeeded()
#if os(tvOS)
            if focusedHeroAction == nil {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    focusedHeroAction = .play
                }
            }
#endif
        }
        .onChange(of: viewModel.detail.item.id) { _, newValue in
            iosSelectedCarouselItemID = newValue
        }
        .onChange(of: currentReturnSourceItem.id) { _, _ in
            onDisplayedSourceItemChange?(currentReturnSourceItem)
        }
#if os(tvOS)
        .onChange(of: focusedSeasonID) { _, newValue in
            guard newValue != nil else { return }
            completeTVHeroRevealIfNeeded()
        }
#endif
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
                PlayerView(
                    session: playerSession,
                    item: viewModel.itemToPlay,
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline
                )
            }
        }
        .modifier(DetailZoomTransitionModifier(namespace: transitionNamespace, sourceID: transitionSourceID))
    }

    private func heroSection(
        heroHeight: CGFloat,
        viewportSize: CGSize,
        safeAreaTop: CGFloat,
        tvStageMetrics: TVDetailStageMetrics = .resting
    ) -> some View {
        #if os(tvOS)
        tvHeroSection(
            heroHeight: heroHeight,
            viewportSize: viewportSize,
            safeAreaTop: safeAreaTop,
            stageMetrics: tvStageMetrics
        )
        #else
        iosHeroSection(
            heroHeight: heroHeight,
            viewportSize: viewportSize,
            safeAreaTop: safeAreaTop,
            stageMetrics: .resting
        )
        #endif
    }

#if os(iOS)
    private func iosHeroSection(
        heroHeight: CGFloat,
        viewportSize: CGSize,
        safeAreaTop: CGFloat,
        stageMetrics: IOSDetailStageMetrics
    ) -> some View {
        let artworkBleed = stageMetrics.artworkBleed

        return ZStack {
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
            .padding(.horizontal, artworkBleed)
            .offset(y: stageMetrics.backgroundOffset)

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.06), location: 0.0),
                    .init(color: Color.black.opacity(0.18), location: 0.22),
                    .init(color: Color.black.opacity(0.44), location: 0.50),
                    .init(color: Color.black.opacity(0.84), location: 0.78),
                    .init(color: Color.black, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            IOSDetailHeroContent(
                item: viewModel.detail.item,
                playbackItem: viewModel.itemToPlay,
                preferredSource: viewModel.preferredPlaybackSource,
                optimizationStatus: viewModel.playbackOptimizationStatus,
                playButtonLabel: viewModel.primaryPlayButtonLabel,
                playbackStatusText: viewModel.playbackStatusText,
                progress: resolvedHeroProgress,
                isLoadingPlayback: Self.showsBlockingPlaybackPreparation(
                    isLoadingPlayback: isLoadingPlayback,
                    isBackgroundWarmingPlayback: viewModel.isWarmingPlayback
                ),
                isInWatchlist: viewModel.isInWatchlist,
                isWatched: viewModel.primaryPlaybackItemIsWatched,
                contentWidth: resolvedMetadataWidth(for: viewportSize),
                horizontalPadding: horizontalPadding,
                safeAreaTop: safeAreaTop,
                bottomPadding: heroBottomPadding + 10 - stageMetrics.bottomPaddingCompression,
                collapseProgress: stageMetrics.topInsetProgress,
                animateIn: hasAnimatedIn,
                prefersNativeZoomTransition: prefersNativeZoomTransition,
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline,
                onBack: { dismiss() },
                onPlay: { startPlayback() },
                onToggleWatchlist: viewModel.toggleWatchlist,
                onToggleWatched: viewModel.toggleWatched
            )
            .opacity(stageMetrics.heroContentOpacity)
            .scaleEffect(stageMetrics.heroContentScale, anchor: .top)
        }
        .frame(maxWidth: .infinity)
        .frame(height: stageMetrics.heroContentHeight(for: heroHeight))
    }
#endif

#if os(tvOS)
    private func tvHeroSection(
        heroHeight: CGFloat,
        viewportSize: CGSize,
        safeAreaTop _: CGFloat,
        stageMetrics: TVDetailStageMetrics
    ) -> some View {
        let neighbors = heroNeighbors
        let sideWidth = stageMetrics.sidePreviewWidth(for: tvHeroSidePreviewWidth(for: viewportSize))
        let heroContentWidth = stageMetrics.heroContentWidth(for: resolvedMetadataWidth(for: viewportSize))
        let heroCornerRadius = stageMetrics.heroCornerRadius
        let heroHeightValue = stageMetrics.heroHeight(for: heroHeight)
        let revealProgress = prefersNativeZoomTransition ? 1 : tvHeroRevealProgress
        let revealScaleX = 0.94 + (revealProgress * 0.06)
        let revealScaleY = 0.965 + (revealProgress * 0.035)
        let revealOpacity = 0.76 + (revealProgress * 0.24)
        let revealLift = (1 - revealProgress) * 34

        return HStack(spacing: stageMetrics.heroSpacing) {
            if let previous = neighbors.previous {
                TVDetailContextPreviewCard(
                    item: previous,
                    edge: .leading,
                    width: sideWidth,
                    height: stageMetrics.sidePreviewHeight(for: heroHeight),
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline,
                    isEnabled: stageMetrics.previewInteractionEnabled,
                    visibility: stageMetrics.previewVisibility,
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
                .clipShape(RoundedRectangle(cornerRadius: heroCornerRadius, style: .continuous))
                .scaleEffect(x: stageMetrics.heroBackgroundScaleX, y: stageMetrics.heroBackgroundScaleY, anchor: .center)
                .offset(y: stageMetrics.heroLift)

                RoundedRectangle(cornerRadius: heroCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.08), location: 0),
                                .init(color: .clear, location: 0.20),
                                .init(color: .clear, location: 0.52),
                                .init(color: .black.opacity(0.32 + (0.18 * stageMetrics.collapseProgress)), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.08), location: 0.42),
                        .init(color: .black.opacity(0.42), location: 0.74),
                        .init(color: .black.opacity(0.78), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: heroCornerRadius, style: .continuous))
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)

                    HeroMetadataColumn(
                        item: viewModel.detail.item,
                        preferredSource: viewModel.preferredPlaybackSource,
                        optimizationStatus: viewModel.playbackOptimizationStatus,
                        playButtonLabel: viewModel.primaryPlayButtonLabel,
                        playbackStatusText: viewModel.playbackStatusText,
                        progress: resolvedHeroProgress,
                        isLoadingPlayback: Self.showsBlockingPlaybackPreparation(
                            isLoadingPlayback: isLoadingPlayback,
                            isBackgroundWarmingPlayback: viewModel.isWarmingPlayback
                        ),
                        isInWatchlist: viewModel.isInWatchlist,
                        isWatched: viewModel.primaryPlaybackItemIsWatched,
                        horizontalPadding: 0,
                        contentWidth: max(heroContentWidth, 420),
                        animateIn: hasAnimatedIn,
                        prefersNativeZoomTransition: prefersNativeZoomTransition,
                        focusedAction: $focusedHeroAction,
                        onPlay: { startPlayback() },
                        onToggleWatchlist: viewModel.toggleWatchlist,
                        onToggleWatched: viewModel.toggleWatched
                    )
                    .padding(.horizontal, stageMetrics.heroHorizontalInset)
                    .padding(.bottom, stageMetrics.heroBottomInset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: heroHeightValue)
            .scaleEffect(x: revealScaleX, y: revealScaleY, anchor: .center)
            .opacity(revealOpacity)
            .offset(y: revealLift)
            .clipShape(RoundedRectangle(cornerRadius: heroCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: heroCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(stageMetrics.heroStrokeOpacity), lineWidth: 1)
            }
            .shadow(color: .black.opacity(stageMetrics.heroShadowOpacity), radius: stageMetrics.heroShadowRadius, x: 0, y: stageMetrics.heroShadowYOffset)

            if let next = neighbors.next {
                TVDetailContextPreviewCard(
                    item: next,
                    edge: .trailing,
                    width: sideWidth,
                    height: stageMetrics.sidePreviewHeight(for: heroHeight),
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline,
                    isEnabled: stageMetrics.previewInteractionEnabled,
                    visibility: stageMetrics.previewVisibility,
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
        .padding(.horizontal, stageMetrics.heroOuterHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: heroHeightValue)
        .focusSection()
        .animation(.smooth(duration: 0.26, extraBounce: 0.02), value: stageMetrics.collapseProgress)
        .animation(.smooth(duration: 0.52, extraBounce: 0.04), value: revealProgress)
        .onChange(of: stageMetrics.previewInteractionEnabled) { _, isEnabled in
            guard !isEnabled, focusedHeroAction == .previous || focusedHeroAction == .next else { return }
            focusedHeroAction = .play
        }
    }
#endif

    @ViewBuilder
    private var supportingContent: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            #if os(tvOS)
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
                .id(TVDetailScrollTarget.seasons)
            }
            #endif

            if viewModel.detail.item.mediaType == .series {
                #if os(tvOS)
                episodeSection
                    .id(TVDetailScrollTarget.episodes)
                #else
                episodeSection
                #endif
            } else {
                relatedSection(
                    title: "Related",
                    onMoveUp: focusHeroPrimaryActionFromDetailRow
                )
            }

            if !viewModel.detail.cast.isEmpty {
                CastRowView(
                    cast: viewModel.detail.cast,
                    onMoveUp: castRowMoveUpAction,
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline
                )
            }

            if viewModel.detail.item.mediaType == .series {
                relatedSection(
                    title: "More Like This",
                    onMoveUp: moreLikeThisMoveUpAction
                )
            }

            if shouldShowSkeleton {
                DetailPageSkeletonView(showsSeasonPicker: viewModel.detail.item.mediaType == .series)
            }

            if let source = viewModel.preferredPlaybackSource {
                FileDetailsSection(source: source)
            }
        }
        .opacity(hasAnimatedIn ? 1 : 0)
        .offset(y: hasAnimatedIn ? 0 : supportingContentEntryOffset)
    }

    @ViewBuilder
    private var episodeSection: some View {
        if viewModel.isLoadingEpisodes && viewModel.episodes.isEmpty {
            DetailPageSkeletonView(showsSeasonPicker: false, sectionKind: .episodesOnly)
        } else if !viewModel.episodes.isEmpty {
            #if os(tvOS)
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
                                onSetWatched: { isPlayed in
                                    viewModel.setEpisodeWatched(episode, isPlayed: isPlayed)
                                },
                                onMoveUp: focusAboveEpisodes,
                                apiClient: dependencies.apiClient,
                                imagePipeline: dependencies.imagePipeline
                            )
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, rowContentHorizontalPadding)
                    .padding(.vertical, rowContentVerticalPadding)
                }
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
            }
            #else
            VStack(alignment: .leading, spacing: 18) {
                IOSSeasonHeaderMenu(
                    title: viewModel.selectedSeason?.name ?? "Season 1",
                    seasons: viewModel.seasons,
                    selectedSeasonID: viewModel.selectedSeason?.id,
                    onSelect: { season in
                        Task {
                            await viewModel.selectSeasonIfNeeded(season)
                        }
                    }
                )

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
                                onSetWatched: { isPlayed in
                                    viewModel.setEpisodeWatched(episode, isPlayed: isPlayed)
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
            #endif
        }
    }

    @ViewBuilder
    private func relatedSection(title: String, onMoveUp: (() -> Void)? = nil) -> some View {
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
                onMoveUp: onMoveUp,
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline
            )
        }
    }

#if os(iOS)
    private var iosCarouselEntries: [IOSDetailCarouselEntry] {
        var entries: [IOSDetailCarouselEntry] = []
        var seenDisplayIDs: Set<String> = []
        let sourceItems = navigationContext.items.isEmpty ? [currentCarouselSourceItem] : navigationContext.items

        for sourceItem in sourceItems {
            let displayItem = makePresentedDetailItem(from: sourceItem)
            guard seenDisplayIDs.insert(displayItem.id).inserted else { continue }
            entries.append(
                IOSDetailCarouselEntry(
                    id: displayItem.id,
                    displayItem: displayItem.id == viewModel.detail.item.id ? viewModel.detail.item : displayItem,
                    sourceItem: sourceItem
                )
            )
        }

        if let currentIndex = entries.firstIndex(where: { $0.id == viewModel.detail.item.id }) {
            entries[currentIndex] = IOSDetailCarouselEntry(
                id: viewModel.detail.item.id,
                displayItem: viewModel.detail.item,
                sourceItem: entries[currentIndex].sourceItem
            )
        } else {
            entries.insert(
                IOSDetailCarouselEntry(
                    id: viewModel.detail.item.id,
                    displayItem: viewModel.detail.item,
                    sourceItem: currentCarouselSourceItem
                ),
                at: 0
            )
        }

        return entries
    }

    private var currentCarouselSourceItem: MediaItem {
        if viewModel.detail.item.mediaType == .series, viewModel.itemToPlay.mediaType == .episode {
            return viewModel.itemToPlay
        }
        return viewModel.detail.item
    }
#endif

    private var heroNeighbors: (previous: MediaItem?, next: MediaItem?) {
        let navigationState = DetailNeighborNavigationState(
            currentItem: viewModel.detail.item,
            contextItems: navigationContext.items
        )
        guard navigationState.contextItems.count > 1 else {
            return (nil, nil)
        }

        return (navigationState.previousItem, navigationState.nextItem)
    }

#if os(iOS)
    private func handleIOSCarouselSelection(_ entry: IOSDetailCarouselEntry) {
        guard entry.id != viewModel.detail.item.id else { return }
        navigateToDetailItem(entry.sourceItem)
    }
#endif

    private func navigateToDetailItem(_ item: MediaItem, context: DetailNavigationContext? = nil) {
        let targetItemID = item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
        navigationContext = context ?? navigationContext
#if os(tvOS)
        tvHeroRevealProgress = 0
#endif
        hasAnimatedIn = false
#if os(iOS)
        iosSelectedCarouselItemID = targetItemID
#endif
        currentReturnSourceItem = item
        focusedHeroAction = .play
        focusedSeasonID = nil

        let detailItem = makePresentedDetailItem(from: item)
        let preferredEpisode = item.mediaType == .episode ? item : nil
        viewModel.setDetailItem(detailItem, preferredEpisode: preferredEpisode)

        Task {
            await DetailPresentationTelemetry.shared.beginNavigation(for: targetItemID)
            await viewModel.load()
            await MainActor.run {
                animateHeroEntryIfNeeded()
            }
        }
    }

    @MainActor
    private func animateHeroEntryIfNeeded() {
        if !hasAnimatedIn {
            withAnimation(detailEntryAnimation) {
                hasAnimatedIn = true
            }
        }

#if os(tvOS)
        guard !prefersNativeZoomTransition else {
            tvHeroRevealProgress = 1
            return
        }

        guard tvHeroRevealProgress < 1 else { return }
        withAnimation(.smooth(duration: 0.52, extraBounce: 0.04)) {
            tvHeroRevealProgress = 1
        }
#endif
    }

    private var prefersNativeZoomTransition: Bool {
        if #available(iOS 18.0, tvOS 18.0, *) {
            return transitionNamespace != nil && transitionSourceID == currentReturnSourceItem.id
        }
        return false
    }

    private var detailEntryAnimation: Animation {
        prefersNativeZoomTransition
            ? .easeOut(duration: 0.24)
            : TVMotion.contentFadeAnimation
    }

    private var supportingContentEntryOffset: CGFloat {
        prefersNativeZoomTransition ? 0 : 16
    }

#if os(tvOS)
    @MainActor
    private func completeTVHeroRevealIfNeeded() {
        guard !prefersNativeZoomTransition else {
            tvHeroRevealProgress = 1
            return
        }

        guard tvHeroRevealProgress < 1 else { return }

        withAnimation(.smooth(duration: 0.18, extraBounce: 0.02)) {
            tvHeroRevealProgress = 1
        }
    }
#endif

    private func focusHeroPrimaryActionFromSeasonPicker() {
#if os(tvOS)
        focusHeroPrimaryActionFromDetailRow()
#else
        focusedSeasonID = nil

        Task { @MainActor in
            focusedHeroAction = .play
        }
#endif
    }

    private func focusAboveEpisodes() {
#if os(tvOS)
        // Keep a deterministic path back to the hero so tvOS never traps focus in the episode rail.
        let targetSeasonID = viewModel.selectedSeason?.id ?? viewModel.seasons.first?.id

        if shouldShowSeasonPicker, let targetSeasonID {
            requestTVFocus(.season(targetSeasonID), scrollTarget: .seasons)
        } else {
            focusHeroPrimaryActionFromDetailRow()
        }
#endif
    }

#if os(tvOS)
    private var castRowMoveUpAction: (() -> Void)? {
        let hasEarlierFocusableRow: Bool
        if viewModel.detail.item.mediaType == .series {
            hasEarlierFocusableRow = shouldShowSeasonPicker || !viewModel.episodes.isEmpty
        } else {
            hasEarlierFocusableRow = !viewModel.detail.similar.isEmpty
        }

        return hasEarlierFocusableRow ? nil : { focusHeroPrimaryActionFromDetailRow() }
    }

    private var moreLikeThisMoveUpAction: (() -> Void)? {
        let hasEarlierFocusableRow = shouldShowSeasonPicker
            || !viewModel.episodes.isEmpty
            || !viewModel.detail.cast.isEmpty
        return hasEarlierFocusableRow ? nil : { focusHeroPrimaryActionFromDetailRow() }
    }

    @MainActor
    private func focusHeroPrimaryActionFromDetailRow() {
        focusedSeasonID = nil
        requestTVFocus(.heroPrimary, scrollTarget: .hero)
    }

    @MainActor
    private func requestTVFocus(_ focusTarget: TVDetailFocusTarget, scrollTarget: TVDetailScrollTarget) {
        pendingTVFocusTarget = focusTarget
        tvScrollRequestID += 1
        tvScrollRequest = TVDetailScrollRequest(id: tvScrollRequestID, target: scrollTarget)
    }

    @MainActor
    private func handleTVScrollRequestCompleted(_ request: TVDetailScrollRequest) {
        guard tvScrollRequest == request else { return }
        tvScrollRequest = nil
        applyTVFocusTarget(pendingTVFocusTarget)
        pendingTVFocusTarget = nil
    }

    @MainActor
    private func applyTVFocusTarget(_ target: TVDetailFocusTarget?) {
        switch target {
        case .heroPrimary:
            focusedSeasonID = nil
            focusedHeroAction = .play
        case let .season(seasonID):
            focusedHeroAction = nil
            focusedSeasonID = seasonID
        case nil:
            break
        }
    }
#else
    private func focusHeroPrimaryActionFromDetailRow() {}
    private var castRowMoveUpAction: (() -> Void)? { nil }
    private var moreLikeThisMoveUpAction: (() -> Void)? { nil }
#endif

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
        let startPosition: PlaybackStartPosition = item == nil
            ? viewModel.primaryPlaybackStartPosition
            : .resumeIfAvailable
        let nextEpisodeQueue = targetItem.mediaType == .episode ? viewModel.nextEpisodes(after: targetItem) : []

#if os(iOS)
        OrientationManager.shared.prepareLandscapeForPlayerCoverPresentation()
#endif
        isLoadingPlayback = true
        playerSession = session
        setPlayerCoverPresented(true)

        Task { @MainActor in
            await Task.yield()
            do {
                try await session.load(
                    item: targetItem,
                    upNextEpisodes: nextEpisodeQueue,
                    startPosition: startPosition
                )
                isLoadingPlayback = false
            } catch {
                isLoadingPlayback = false
                playerSession = nil
                viewModel.errorMessage = error.localizedDescription
                setPlayerCoverPresented(false)
            }
        }
    }

    static func showsBlockingPlaybackPreparation(
        isLoadingPlayback: Bool,
        isBackgroundWarmingPlayback: Bool
    ) -> Bool {
        _ = isBackgroundWarmingPlayback
        return isLoadingPlayback
    }

    @MainActor
    private func handlePlayerDismissal() {
        let stoppedProgress = playerSession?.stop()
        if let stoppedProgress {
            viewModel.applyStoppedPlaybackProgress(stoppedProgress)
        }
        playerSession = nil
        setPlayerCoverPresented(false)
        isLoadingPlayback = false
    }

    private func setPlayerCoverPresented(_ isPresented: Bool) {
#if os(iOS)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showPlayer = isPresented
        }
#else
        showPlayer = isPresented
#endif
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
        return horizontalSizeClass == .compact ? 20 : 36
#endif
    }

    private var sectionSpacing: CGFloat {
#if os(tvOS)
        return ReelFinTheme.tvSectionSpacing
#else
        return 18
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
        return horizontalSizeClass == .compact ? 308 : 360
#endif
    }

    private var episodeCardSpacing: CGFloat {
#if os(tvOS)
        return 30
#else
        return 14
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
        return horizontalSizeClass == .compact ? min(viewportSize.width - (horizontalPadding * 2), 640) : 700
#endif
    }

#if os(tvOS)
    private func tvHeroSidePreviewWidth(for viewportSize: CGSize) -> CGFloat {
        min(max(viewportSize.width * 0.1, 126), 160)
    }
#endif
}

private struct DetailZoomTransitionModifier: ViewModifier {
    let namespace: Namespace.ID?
    let sourceID: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace, let sourceID {
            if #available(iOS 18.0, tvOS 18.0, *) {
                content.navigationTransition(.zoom(sourceID: "poster-\(sourceID)", in: namespace))
            } else {
                content
            }
        } else {
            content
        }
    }
}

#if os(tvOS)
private enum TVDetailScrollTarget: Hashable {
    case hero
    case seasons
    case episodes

    var anchor: UnitPoint {
        switch self {
        case .hero:
            return .top
        case .seasons, .episodes:
            return .center
        }
    }
}

private struct TVDetailScrollRequest: Equatable {
    let id: Int
    let target: TVDetailScrollTarget
}

private enum TVDetailFocusTarget: Equatable {
    case heroPrimary
    case season(String)
}

private struct TVDetailScrollSnapshot: Equatable {
    var offsetY: CGFloat = 0
    var topInset: CGFloat = 0
}

private struct TVDetailStageMetrics: Equatable {
    private let normalizedProgress: CGFloat
    let collapseProgress: CGFloat

    static let resting = TVDetailStageMetrics()

    init(
        snapshot: TVDetailScrollSnapshot = .init(),
        heroHeight: CGFloat = 1,
        topTriggerDistance: CGFloat = 1,
        forcedCollapseProgress: CGFloat? = nil
    ) {
        let rawProgress: CGFloat

        if let forcedCollapseProgress {
            rawProgress = min(max(forcedCollapseProgress, 0), 1)
        } else {
            let effectiveOffset = max(0, snapshot.offsetY + snapshot.topInset - 14)
            rawProgress = min(max(effectiveOffset / max(topTriggerDistance, 1), 0), 1)
        }

        collapseProgress = rawProgress
        normalizedProgress = rawProgress * rawProgress * (3 - (2 * rawProgress))
    }

    func sidePreviewWidth(for baseWidth: CGFloat) -> CGFloat {
        max(baseWidth * (1 - normalizedProgress), 0)
    }

    func sidePreviewHeight(for heroHeight: CGFloat) -> CGFloat {
        heroHeight * (0.94 - (normalizedProgress * 0.06))
    }

    func heroHeight(for baseHeight: CGFloat) -> CGFloat {
        baseHeight + (normalizedProgress * 28)
    }

    func heroContentWidth(for baseWidth: CGFloat) -> CGFloat {
        baseWidth + (normalizedProgress * 260)
    }

    var heroOuterHorizontalPadding: CGFloat { 28 * (1 - normalizedProgress) }
    var heroSpacing: CGFloat { 18 - (normalizedProgress * 18) }
    var heroHorizontalInset: CGFloat { 50 - (normalizedProgress * 18) }
    var heroBottomInset: CGFloat { 44 - (normalizedProgress * 10) }
    var heroCornerRadius: CGFloat { 44 - (normalizedProgress * 22) }
    var heroBackgroundScaleX: CGFloat { 1 + (normalizedProgress * 0.08) }
    var heroBackgroundScaleY: CGFloat { 1 + (normalizedProgress * 0.03) }
    var heroLift: CGFloat { -16 * normalizedProgress }
    var heroStrokeOpacity: Double { 0.12 - (normalizedProgress * 0.08) }
    var heroShadowOpacity: Double { 0.48 - (normalizedProgress * 0.14) }
    var heroShadowRadius: CGFloat { 40 - (normalizedProgress * 14) }
    var heroShadowYOffset: CGFloat { 24 - (normalizedProgress * 8) }
    var previewVisibility: Double { 1 - Double(normalizedProgress) }
    var previewInteractionEnabled: Bool { collapseProgress < 0.08 }
}

private struct TVDetailScreen<Hero: View, Supporting: View>: View {
    let heroHeight: CGFloat
    let horizontalPadding: CGFloat
    let sectionSpacing: CGFloat
    let forcedHeroCollapseProgress: CGFloat?
    let scrollRequest: TVDetailScrollRequest?
    let onScrollRequestCompleted: (TVDetailScrollRequest) -> Void
    @ViewBuilder let hero: (TVDetailStageMetrics) -> Hero
    @ViewBuilder let supportingContent: () -> Supporting

    @State private var scrollSnapshot = TVDetailScrollSnapshot()

    var body: some View {
        let metrics = TVDetailStageMetrics(
            snapshot: scrollSnapshot,
            heroHeight: heroHeight,
            topTriggerDistance: max(heroHeight * 0.30, 1),
            forcedCollapseProgress: forcedHeroCollapseProgress
        )

        ZStack(alignment: .top) {
            TVDetailAmbientBackground()
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                        hero(metrics)
                            .padding(.top, 20)
                            .id(TVDetailScrollTarget.hero)

                        supportingContent()
                            .padding(.horizontal, horizontalPadding)
                            .padding(.bottom, 96)
                    }
                }
                .onScrollGeometryChange(for: TVDetailScrollSnapshot.self) { geometry in
                    TVDetailScrollSnapshot(
                        offsetY: geometry.contentOffset.y,
                        topInset: geometry.contentInsets.top
                    )
                } action: { _, newValue in
                    scrollSnapshot = newValue
                }
                .onChange(of: scrollRequest) { _, request in
                    guard let request else { return }
                    scroll(to: request, using: proxy)
                }
            }
        }
    }

    private func scroll(to request: TVDetailScrollRequest, using proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(request.target, anchor: request.target.anchor)
        }

        Task { @MainActor in
            await Task.yield()
            onScrollRequestCompleted(request)
        }
    }
}

private struct TVDetailAmbientBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.020, green: 0.024, blue: 0.038),
                    Color(red: 0.010, green: 0.012, blue: 0.022),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [ReelFinTheme.onboardingViolet.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 620
            )
            .blur(radius: 34)
            .offset(x: 80, y: -120)

            LinearGradient(
                colors: [Color.white.opacity(0.04), .clear, Color.black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

#else
private struct TVDetailStageMetrics: Equatable {
    static let resting = TVDetailStageMetrics()
}
#endif

#if os(iOS)
private struct IOSDetailScrollSnapshot: Equatable {
    var offsetY: CGFloat = 0
    var topInset: CGFloat = 0
}

private struct IOSDetailStageMetrics: Equatable {
    private let normalizedProgress: CGFloat
    let topInsetProgress: CGFloat

    static let resting = IOSDetailStageMetrics()

    init(snapshot: IOSDetailScrollSnapshot = .init(), heroHeight: CGFloat = 1, topTriggerDistance: CGFloat = 1) {
        let effectiveOffset = max(0, snapshot.offsetY + snapshot.topInset - 10)
        topInsetProgress = min(max(effectiveOffset / max(topTriggerDistance, 1), 0), 1)
        let travelDistance = max(heroHeight * 0.54, 1)
        let rawProgress = min(max(effectiveOffset / travelDistance, 0), 1)
        normalizedProgress = rawProgress * rawProgress * (3 - (2 * rawProgress))
    }

    func heroContentHeight(for heroHeight: CGFloat) -> CGFloat {
        max(heroHeight - (normalizedProgress * 24), heroHeight * 0.95)
    }

    func previewCardHeight(for heroHeight: CGFloat) -> CGFloat {
        heroHeight * (0.90 - (topInsetProgress * 0.08))
    }

    func stageHeight(for heroHeight: CGFloat) -> CGFloat {
        max(heroContentHeight(for: heroHeight), previewCardHeight(for: heroHeight)) + (24 - (topInsetProgress * 4))
    }

    var artworkBleed: CGFloat { -6 * normalizedProgress }
    var backgroundOffset: CGFloat { -28 * normalizedProgress }
    var heroLift: CGFloat { -14 * topInsetProgress }
    var selectedCardScaleX: CGFloat { 1 }
    var selectedCardScaleY: CGFloat { 1 - (normalizedProgress * 0.04) }
    var bottomPaddingCompression: CGFloat { 1.5 * normalizedProgress }
    var topCornerRadius: CGFloat { 32 - (topInsetProgress * 8) }
    var bottomCornerRadius: CGFloat { 42 - (normalizedProgress * 10) }
    var previewCornerRadius: CGFloat { 34 + (10 * normalizedProgress) }
    var shadowRadius: CGFloat { 30 - (10 * topInsetProgress) }
    var shadowYOffset: CGFloat { 24 - (8 * topInsetProgress) }
    var selectedStrokeOpacity: Double { 0.14 * (1 - (topInsetProgress * 0.92)) }
    var selectedShadowOpacity: Double { 0.38 - (topInsetProgress * 0.22) }
    var headerBlurOpacity: Double { Double(topInsetProgress) }
    var headerShadeOpacity: Double { 0.08 + Double(topInsetProgress * 0.18) }
    var heroContentOpacity: Double { 1 }
    var heroContentScale: CGFloat { 1 }
    var contentBridgeLift: CGFloat { 2 * topInsetProgress }
}

private struct IOSDetailScreen<SelectedCard: View, Supporting: View>: View {
    let viewportSize: CGSize
    let safeAreaTop: CGFloat
    let heroHeight: CGFloat
    let horizontalPadding: CGFloat
    let sectionSpacing: CGFloat
    let entries: [IOSDetailCarouselEntry]
    let currentItemID: String
    @Binding var selectedItemID: String?
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let onSelectItem: (IOSDetailCarouselEntry) -> Void
    @ViewBuilder let selectedCard: (IOSDetailStageMetrics) -> SelectedCard
    @ViewBuilder let supportingContent: () -> Supporting

    @State private var scrollSnapshot = IOSDetailScrollSnapshot()
    @State private var lastAlignedCarouselItemID: String?
    @State private var carouselScrollPositionID: String?

    var body: some View {
        let metrics = IOSDetailStageMetrics(
            snapshot: scrollSnapshot,
            heroHeight: heroHeight,
            topTriggerDistance: stageTopInset
        )
        let contentSpacing = max(sectionSpacing - metrics.contentBridgeLift, 8)

        ZStack(alignment: .top) {
            Color.black
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: contentSpacing) {
                    topStage(metrics: metrics)

                    supportingContent()
                        .padding(.top, -metrics.contentBridgeLift)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, 96)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .ignoresSafeArea(edges: .top)
            .onScrollGeometryChange(for: IOSDetailScrollSnapshot.self) { geometry in
                IOSDetailScrollSnapshot(
                    offsetY: geometry.contentOffset.y,
                    topInset: geometry.contentInsets.top
                )
            } action: { _, newValue in
                scrollSnapshot = newValue
            }

            compactHeader(metrics: metrics)
        }
        .onAppear {
            if selectedItemID == nil {
                selectedItemID = currentItemID
            }
            if carouselScrollPositionID == nil {
                carouselScrollPositionID = currentItemID
            }
        }
        .onChange(of: currentItemID) { _, newValue in
            selectedItemID = newValue
            carouselScrollPositionID = newValue
        }
        .onChange(of: carouselScrollPositionID) { _, newValue in
            guard let acceptedID = IOSDetailCarouselLayout.acceptedSelectionID(
                currentItemID: currentItemID,
                proposedItemID: newValue,
                topInsetProgress: metrics.topInsetProgress
            ) else {
                carouselScrollPositionID = currentItemID
                return
            }
            guard let entry = entries.first(where: { $0.id == acceptedID }) else { return }
            selectedItemID = acceptedID
            onSelectItem(entry)
        }
    }

    private func topStage(metrics: IOSDetailStageMetrics) -> some View {
        GeometryReader { proxy in
            let cardWidth = resolvedCardWidth(for: proxy.size.width)
            let sideInset = resolvedSideInset(for: proxy.size.width, cardWidth: cardWidth)
            let animatedSideInset = sideInset * (1 - metrics.topInsetProgress)
            let expandedCardWidth = min(
                cardWidth + ((proxy.size.width - cardWidth) * metrics.topInsetProgress),
                proxy.size.width
            )
            let allowsHorizontalSelection = IOSDetailCarouselLayout.allowsHorizontalSelection(
                topInsetProgress: metrics.topInsetProgress
            )
            let neighborPreviewOpacity = IOSDetailCarouselLayout.neighborPreviewOpacity(
                topInsetProgress: metrics.topInsetProgress
            )

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 18) {
                        ForEach(entries) { entry in
                            IOSDetailTopCarouselCard(
                                entry: entry,
                                currentItemID: currentItemID,
                                heroHeight: heroHeight,
                                cardWidth: cardWidth,
                                expandedCardWidth: expandedCardWidth,
                                metrics: metrics,
                                topInsetProgress: metrics.topInsetProgress,
                                neighborPreviewOpacity: neighborPreviewOpacity,
                                apiClient: apiClient,
                                imagePipeline: imagePipeline
                            ) {
                                selectedCard(metrics)
                            }
                            .id(entry.id)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, animatedSideInset)
                .padding(.vertical, 8)
                .onAppear {
                    alignCarouselIfNeeded(
                        to: selectedItemID ?? currentItemID,
                        using: proxy
                    )
                }
                .onChange(of: currentItemID) { _, newValue in
                    alignCarouselIfNeeded(to: newValue, using: proxy)
                }
                .onChange(of: entries.map(\.id)) { _, _ in
                    alignCarouselIfNeeded(
                        to: selectedItemID ?? currentItemID,
                        using: proxy,
                        force: true
                    )
                }
                .scrollClipDisabled()
                .scrollDisabled(!allowsHorizontalSelection)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $carouselScrollPositionID)
            }
            .accessibilityIdentifier("detail_ios_top_carousel")
        }
        .frame(height: metrics.stageHeight(for: heroHeight))
        .padding(.top, stageTopInset)
    }

    private func compactHeader(metrics: IOSDetailStageMetrics) -> some View {
        VStack(spacing: 0) {
            ZStack {
                TransparentBlurView(style: .systemUltraThinMaterial)
                    .opacity(metrics.headerBlurOpacity)

                LinearGradient(
                    colors: [
                        Color.black.opacity(metrics.headerShadeOpacity),
                        Color.black.opacity(metrics.headerShadeOpacity * 0.62),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .mask {
                LinearGradient(
                    colors: [.black, .black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: safeAreaTop + 78)
            .accessibilityIdentifier("detail_ios_blur_header")
            .allowsHitTesting(false)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var stageTopInset: CGFloat {
        min(max(safeAreaTop * 0.66, 40), 60)
    }

    private func resolvedCardWidth(for availableWidth: CGFloat) -> CGFloat {
        IOSDetailCarouselLayout.cardWidth(
            for: availableWidth,
            minimumPadding: horizontalPadding,
            viewportWidth: viewportSize.width
        )
    }

    private func resolvedSideInset(for availableWidth: CGFloat, cardWidth: CGFloat) -> CGFloat {
        IOSDetailCarouselLayout.sideInset(
            for: availableWidth,
            cardWidth: cardWidth,
            minimumPadding: horizontalPadding,
            viewportWidth: viewportSize.width
        )
    }

    private func alignCarouselIfNeeded(
        to itemID: String,
        using proxy: ScrollViewProxy,
        force: Bool = false
    ) {
        guard force || lastAlignedCarouselItemID != itemID else { return }
        lastAlignedCarouselItemID = itemID

        Task { @MainActor in
            await Task.yield()
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(itemID, anchor: .leading)
            }
        }
    }
}

private struct IOSDetailTopCarouselCard<SelectedContent: View>: View {
    let entry: IOSDetailCarouselEntry
    let currentItemID: String
    let heroHeight: CGFloat
    let cardWidth: CGFloat
    let expandedCardWidth: CGFloat
    let metrics: IOSDetailStageMetrics
    let topInsetProgress: CGFloat
    let neighborPreviewOpacity: Double
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    @ViewBuilder let selectedContent: () -> SelectedContent

    var body: some View {
        let selected = isSelected

        ZStack(alignment: .bottomLeading) {
            Color.black

            HeroBackgroundView(
                item: entry.displayItem,
                heroHeight: cardHeight,
                apiClient: apiClient,
                imagePipeline: imagePipeline,
                onHeroImageVisible: nil
            )
            .padding(.horizontal, selected ? metrics.artworkBleed : 0)
            .offset(y: selected ? metrics.backgroundOffset : 0)

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.08), location: 0),
                    .init(color: Color.black.opacity(0.22), location: 0.24),
                    .init(color: Color.black.opacity(0.54), location: 0.56),
                    .init(color: Color.black.opacity(0.88), location: 0.84),
                    .init(color: Color.black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if selected {
                selectedContent()
            } else {
                previewOverlay
            }
        }
        .frame(width: resolvedCardWidth, height: cardHeight)
        .clipShape(cardShape)
        .overlay {
            cardShape
                .stroke(
                    Color.white.opacity(selected ? metrics.selectedStrokeOpacity : 0.10),
                    lineWidth: selected ? 1 : 0.8
                )
        }
        .shadow(
            color: .black.opacity(selected ? metrics.selectedShadowOpacity : 0.22),
            radius: selected ? metrics.shadowRadius : 18,
            x: 0,
            y: selected ? metrics.shadowYOffset : 12
        )
        .scaleEffect(
            x: selected ? metrics.selectedCardScaleX : 0.94,
            y: selected ? metrics.selectedCardScaleY : 0.94,
            anchor: .top
        )
        .opacity(selected ? 1 : neighborPreviewOpacity)
        .allowsHitTesting(selected || neighborPreviewOpacity > 0.98)
        .offset(y: selected ? metrics.heroLift : 18 + (topInsetProgress * 12))
        .accessibilityIdentifier("detail_top_card_\(entry.id)")
        .accessibilityElement(children: .contain)
    }

    private var isSelected: Bool {
        entry.id == currentItemID
    }

    private var resolvedCardWidth: CGFloat {
        isSelected ? expandedCardWidth : cardWidth
    }

    private var cardHeight: CGFloat {
        if isSelected {
            return metrics.heroContentHeight(for: heroHeight)
        }
        return metrics.previewCardHeight(for: heroHeight)
    }

    private var cardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isSelected ? metrics.topCornerRadius : metrics.previewCornerRadius,
            bottomLeadingRadius: isSelected ? metrics.bottomCornerRadius : metrics.previewCornerRadius + 4,
            bottomTrailingRadius: isSelected ? metrics.bottomCornerRadius : metrics.previewCornerRadius + 4,
            topTrailingRadius: isSelected ? metrics.topCornerRadius : metrics.previewCornerRadius,
            style: .continuous
        )
    }

    private var previewOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(previewKicker.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.66))

            Spacer(minLength: 0)

            Text(entry.displayItem.name)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.88)

            if !previewMetadata.isEmpty {
                Text(previewMetadata)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var previewKicker: String {
        switch entry.displayItem.mediaType {
        case .movie:
            return "Movie"
        case .series:
            return "Series"
        case .episode:
            return "Episode"
        case .season:
            return "Season"
        case .unknown:
            return "Details"
        }
    }

    private var previewMetadata: String {
        var values: [String] = []

        if let year = entry.displayItem.year {
            values.append(String(year))
        }

        if !entry.displayItem.genres.isEmpty {
            values.append(contentsOf: entry.displayItem.genres.prefix(2))
        }

        return values.joined(separator: " · ")
    }
}

#endif

private enum HeroMetadataLayout {
    case leading
    case centered
}

#if os(iOS)
private struct IOSDetailHeroContent: View {
    let item: MediaItem
    let playbackItem: MediaItem
    let preferredSource: MediaSource?
    let optimizationStatus: ApplePlaybackOptimizationStatus?
    let playButtonLabel: String
    let playbackStatusText: String?
    let progress: Double?
    let isLoadingPlayback: Bool
    let isInWatchlist: Bool
    let isWatched: Bool
    let contentWidth: CGFloat
    let horizontalPadding: CGFloat
    let safeAreaTop: CGFloat
    let bottomPadding: CGFloat
    let collapseProgress: CGFloat
    let animateIn: Bool
    let prefersNativeZoomTransition: Bool
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let onBack: () -> Void
    let onPlay: () -> Void
    let onToggleWatchlist: () -> Void
    let onToggleWatched: () -> Void

    @State private var isSynopsisExpanded = false
    @State private var isDownloadAvailabilityAlertPresented = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Spacer(minLength: heroTopSpacer)

            VStack(spacing: contentStackSpacing) {
                identityBlock
                    .frame(maxWidth: .infinity)

                detailBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: min(contentWidth, 720), alignment: .center)
        }
        .padding(.top, safeAreaTop + topChromeOffset - (collapseProgress * 4))
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : entryOffset)
        .animation(entryAnimation, value: animateIn)
        .alert("Downloads coming soon", isPresented: $isDownloadAvailabilityAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Offline downloads are not available yet. This feature will arrive in a future update.")
        }
        .onChange(of: item.id) { _, _ in
            resetSynopsisExpansion()
        }
        .onChange(of: playbackItem.id) { _, _ in
            resetSynopsisExpansion()
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            IOSHeroChromeCircleButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Back",
                diameter: isCompactHeroLayout ? 44 : 50,
                action: onBack
            )

            Spacer()

            HStack(spacing: 0) {
                IOSHeroChromeBarButton(
                    systemImage: "arrow.down",
                    accessibilityLabel: "Download",
                    controlWidth: isCompactHeroLayout ? 38 : 44,
                    controlHeight: isCompactHeroLayout ? 27 : 30
                ) {
                    isDownloadAvailabilityAlertPresented = true
                }

                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: isCompactHeroLayout ? 15 : 18)

                ShareLink(
                    item: shareText,
                    preview: SharePreview(item.name)
                ) {
                    IOSHeroChromeBarGlyph(
                        systemImage: "square.and.arrow.up",
                        accessibilityLabel: "Share",
                        controlWidth: isCompactHeroLayout ? 38 : 44,
                        controlHeight: isCompactHeroLayout ? 27 : 30
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, isCompactHeroLayout ? 8 : 10)
            .padding(.vertical, isCompactHeroLayout ? 6 : 8)
            .reelFinGlassCapsule(
                interactive: true,
                tint: Color.white.opacity(0.16),
                stroke: Color.white.opacity(0.16),
                shadowOpacity: 0.18,
                shadowRadius: 16,
                shadowYOffset: 8
            )
        }
    }

    private var identityBlock: some View {
        VStack(spacing: identityBlockSpacing) {
            IOSDetailHeroTitleView(
                item: item,
                apiClient: apiClient,
                imagePipeline: imagePipeline
            )
            .frame(maxWidth: 540)

            HStack(spacing: 10) {
                Text(subtitleText)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .multilineTextAlignment(.center)

                if optimizationStatus == .optimized {
                    IOSHeroAccessoryBadge(systemImage: "tv")
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: isCompactHeroLayout ? 12 : 14) {
                IOSDetailHeroPrimaryButton(
                    title: iosPlayButtonLabel,
                    isLoading: isLoadingPlayback,
                    minHeight: isCompactHeroLayout ? 48 : 56,
                    fontSize: isCompactHeroLayout ? 15.5 : 17,
                    action: onPlay
                )
                .frame(maxWidth: isCompactHeroLayout ? 236 : 272)

                IOSDetailHeroRoundActionButton(
                    systemImage: isWatched ? "eye.fill" : "eye",
                    accessibilityLabel: isWatched ? "Mark Unwatched" : "Mark Watched",
                    accessibilityIdentifier: "detail_watched_button",
                    accessibilityValue: isWatched ? "watched" : "not_watched",
                    isActive: isWatched,
                    size: isCompactHeroLayout ? 48 : 56,
                    action: onToggleWatched
                )

                IOSDetailHeroRoundActionButton(
                    systemImage: isInWatchlist ? "heart.fill" : "heart",
                    accessibilityLabel: isInWatchlist ? "Unlike" : "Like",
                    accessibilityIdentifier: "detail_favorite_button",
                    accessibilityValue: isInWatchlist ? "liked" : "not_liked",
                    isActive: isInWatchlist,
                    size: isCompactHeroLayout ? 48 : 56,
                    action: onToggleWatchlist
                )
            }
            .frame(maxWidth: min(contentWidth, isCompactHeroLayout ? 388 : 424))

            resumeProgressBlock
        }
    }

    @ViewBuilder
    private var resumeProgressBlock: some View {
        if hasResumeProgressInfo {
            VStack(spacing: isCompactHeroLayout ? 5 : 8) {
                if let playbackStatusText, !playbackStatusText.isEmpty {
                    Text(playbackStatusText)
                        .font(.system(size: isCompactHeroLayout ? 13.5 : 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.84))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let progress, progress >= 0.01 {
                    HeroProgressView(
                        progress: min(max(progress, 0), 1),
                        centered: true
                    )
                }
            }
            .frame(maxWidth: min(contentWidth, isCompactHeroLayout ? 320 : 360))
            .accessibilityElement(children: .combine)
        }
    }

    private var detailBlock: some View {
        VStack(alignment: .leading, spacing: detailBlockSpacing) {
            if let synopsisText, !synopsisText.isEmpty {
                VStack(alignment: .leading, spacing: isCompactHeroLayout ? 6 : 10) {
                    summaryText(synopsisText)
                        .font(.system(size: synopsisFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(synopsisLineLimit)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: synopsisMaximumHeight,
                            alignment: .topLeading
                        )
                        .clipped()
                        .layoutPriority(0)

                    if synopsisNeedsExpansion {
                        Button(isSynopsisExpanded ? "LESS" : "MORE") {
                            withAnimation(.easeOut(duration: 0.18)) {
                                isSynopsisExpanded.toggle()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: isCompactHeroLayout ? 12 : 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, isCompactHeroLayout ? 13 : 15)
                        .padding(.vertical, isCompactHeroLayout ? 7 : 9)
                        .background(Color.white.opacity(0.14), in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            footerRow
                .layoutPriority(2)
        }
    }

    private var entryAnimation: Animation {
        prefersNativeZoomTransition
            ? .easeOut(duration: 0.24)
            : .easeOut(duration: 0.45)
    }

    private var entryOffset: CGFloat {
        prefersNativeZoomTransition ? 0 : 22
    }

    @ViewBuilder
    private func summaryText(_ overview: String) -> some View {
        if let episodeHeading {
            Text("\(Text(episodeHeading).bold()): \(overview)")
        } else {
            Text(overview)
        }
    }

    private var footerRow: some View {
        VStack(alignment: .leading, spacing: isCompactHeroLayout ? 8 : 12) {
            if optimizationStatus != nil || !footerPrimaryText.isEmpty || !badgeLabels.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: isCompactHeroLayout ? 8 : 10) {
                        if !footerPrimaryText.isEmpty {
                            Text(footerPrimaryText)
                                .font(.system(size: isCompactHeroLayout ? 14 : 15, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                        }

                        if let optimizationStatus {
                            HeroInlineSymbolBadge(
                                systemImage: optimizationStatus.symbolName,
                                tint: optimizationStatus.iconTint,
                                accessibilityLabel: optimizationStatus.accessibilityLabel
                            )
                        }

                        ForEach(badgeLabels, id: \.self) { badge in
                            HeroInlineBadge(text: badge)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: isCompactHeroLayout ? 8 : 10) {
                            if !footerPrimaryText.isEmpty {
                                Text(footerPrimaryText)
                                    .font(.system(size: isCompactHeroLayout ? 14 : 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .lineLimit(1)
                            }

                            if let optimizationStatus {
                                HeroInlineSymbolBadge(
                                    systemImage: optimizationStatus.symbolName,
                                    tint: optimizationStatus.iconTint,
                                    accessibilityLabel: optimizationStatus.accessibilityLabel
                                )
                            }

                            ForEach(badgeLabels, id: \.self) { badge in
                                HeroInlineBadge(text: badge)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
        }
    }

    private var shareText: String {
        if item.mediaType == .series, playbackItem.id != item.id {
            return "\(item.name) • \(playbackItem.name)"
        }
        return item.name
    }

    private var subtitleText: String {
        var values: [String] = []

        switch item.mediaType {
        case .series:
            values.append("TV Show")
        case .movie:
            values.append("Movie")
        case .episode:
            values.append("Episode")
        case .season:
            values.append("Season")
        case .unknown:
            break
        }

        if !item.genres.isEmpty {
            values.append(contentsOf: item.genres.prefix(2))
        }

        return values.joined(separator: " · ")
    }

    private var iosPlayButtonLabel: String {
        return playButtonLabel
    }

    private var episodeHeading: String? {
        guard item.mediaType == .series || playbackItem.mediaType == .episode else { return nil }

        var values: [String] = []
        if let season = playbackItem.parentIndexNumber, let episode = playbackItem.indexNumber {
            values.append("S\(season), E\(episode)")
        }
        values.append(playbackItem.name)
        return values.joined(separator: " · ")
    }

    private var synopsisText: String? {
        if item.mediaType == .series, playbackItem.id != item.id {
            return playbackItem.overview ?? item.overview
        }
        return item.overview ?? playbackItem.overview
    }

    private var synopsisNeedsExpansion: Bool {
        guard let synopsisText else { return false }
        return IOSDetailSynopsisLayout.needsExpansion(synopsisText, contentWidth: resolvedSynopsisContentWidth)
    }

    private var hasResumeProgressInfo: Bool {
        playbackStatusText?.isEmpty == false || (progress ?? 0) > 0
    }

    private var footerPrimaryText: String {
        let metadataItem = item.mediaType == .series ? playbackItem : item
        var values: [String] = []

        if let year = metadataItem.year ?? item.year {
            values.append(String(year))
        }

        if let runtimeText = runtimeFooterText(for: metadataItem) {
            values.append(runtimeText)
        }

        return values.joined(separator: " · ")
    }

    private var badgeLabels: [String] {
        var values: [String] = []
        let metadataItem = item.mediaType == .series ? playbackItem : item

        if metadataItem.has4K || item.has4K || preferredSource?.isLikely4K == true {
            values.append("4K")
        }
        if metadataItem.hasDolbyVision || item.hasDolbyVision {
            values.append("Dolby Vision")
        }
        if isLikelyAtmos {
            values.append("Dolby Atmos")
        }
        if metadataItem.hasClosedCaptions || item.hasClosedCaptions {
            values.append("CC")
        }
        if (preferredSource?.subtitleTracks.count ?? 0) > 1 {
            values.append("SDH")
        }

        return values
    }

    private var isLikelyAtmos: Bool {
        let audioProfile = (preferredSource?.audioProfile ?? "").lowercased()
        let audioLayout = (preferredSource?.audioChannelLayout ?? "").lowercased()
        return audioProfile.contains("atmos") || audioLayout.contains("atmos")
    }

    private func runtimeFooterText(for item: MediaItem) -> String? {
        guard let runtimeMinutes = item.runtimeMinutes else { return nil }
        return "\(runtimeMinutes) min"
    }

    private var isCompactHeroLayout: Bool {
        contentWidth < IOSDetailSynopsisLayout.compactContentWidthThreshold
    }

    private var heroTopSpacer: CGFloat {
        if isCompactHeroLayout {
            return max(8, 18 - (collapseProgress * 8))
        }
        return max(20, 36 - (collapseProgress * 16))
    }

    private var contentStackSpacing: CGFloat {
        if isCompactHeroLayout {
            return max(10, 16 - (collapseProgress * 4))
        }
        return max(18, 24 - (collapseProgress * 6))
    }

    private var identityBlockSpacing: CGFloat {
        if isCompactHeroLayout {
            return max(9, 13 - (collapseProgress * 4))
        }
        return max(14, 18 - (collapseProgress * 5))
    }

    private var detailBlockSpacing: CGFloat {
        if isCompactHeroLayout {
            return max(7, 10 - (collapseProgress * 3))
        }
        return max(12, 16 - (collapseProgress * 4))
    }

    private var synopsisFontSize: CGFloat {
        isCompactHeroLayout ? 15.5 : 17
    }

    private var topChromeOffset: CGFloat {
        isCompactHeroLayout ? 22 : 18
    }

    private var synopsisLineLimit: Int {
        IOSDetailSynopsisLayout.lineLimit(
            isExpanded: isSynopsisExpanded,
            contentWidth: resolvedSynopsisContentWidth
        )
    }

    private var synopsisMaximumHeight: CGFloat {
        IOSDetailSynopsisLayout.maximumHeight(
            fontSize: synopsisFontSize,
            lineLimit: synopsisLineLimit
        )
    }

    private var resolvedSynopsisContentWidth: CGFloat {
        min(contentWidth, 720)
    }

    private func resetSynopsisExpansion() {
        isSynopsisExpanded = false
    }
}

private struct IOSDetailHeroTitleView: View {
    let item: MediaItem
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    @State private var logoImage: UIImage?

    var body: some View {
        ZStack {
            titleText
                .opacity(logoImage == nil ? 1 : 0)

            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 94)
                    .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: 540, minHeight: 74)
        .transaction { transaction in
            transaction.animation = nil
        }
        .task(id: item.id) {
            await loadLogo(for: item.id)
        }
    }

    private var titleText: some View {
        Text(item.name)
            .font(.system(size: item.name.count > 16 ? 42 : 48, weight: .black, design: .rounded))
            .tracking(item.name.count <= 8 ? 6 : 2)
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.44), radius: 18, x: 0, y: 8)
    }

    private func loadLogo(for itemID: String) async {
        logoImage = nil

        guard let url = await apiClient.imageURL(for: itemID, type: .logo, width: 900, quality: 92) else {
            return
        }
        guard !Task.isCancelled else { return }

        if let cached = await imagePipeline.cachedImage(for: url) {
            guard !Task.isCancelled else { return }
            logoImage = TransparentImageCropper.readableLogoImage(from: cached)
            return
        }

        do {
            let downloaded = try await imagePipeline.image(for: url)
            guard !Task.isCancelled else { return }
            logoImage = TransparentImageCropper.readableLogoImage(from: downloaded)
        } catch {}
    }
}

private struct IOSHeroChromeCircleButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let diameter: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: max(18, diameter * 0.42), weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: diameter, height: diameter)
                .reelFinGlassCircle(
                    interactive: true,
                    tint: Color.white.opacity(0.16),
                    stroke: Color.white.opacity(0.16),
                    shadowOpacity: 0.18,
                    shadowRadius: 16,
                    shadowYOffset: 8
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct IOSHeroChromeBarButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let controlWidth: CGFloat
    let controlHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: max(17, controlHeight * 0.58), weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: controlWidth, height: controlHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct IOSHeroChromeBarGlyph: View {
    let systemImage: String
    let accessibilityLabel: String
    let controlWidth: CGFloat
    let controlHeight: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: max(17, controlHeight * 0.58), weight: .semibold))
            .foregroundStyle(.white.opacity(0.94))
            .frame(width: controlWidth, height: controlHeight)
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct IOSDetailHeroPrimaryButton: View {
    @Environment(\.isFocused) private var isFocused

    let title: String
    let isLoading: Bool
    let minHeight: CGFloat
    let fontSize: CGFloat
    let action: () -> Void

    var body: some View {
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
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.black.opacity(0.92))
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 18)
            .background(Color.white, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(isFocused ? 0.34 : 0.20), radius: isFocused ? 20 : 12, x: 0, y: isFocused ? 10 : 6)
            .scaleEffect(isFocused ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

private struct IOSDetailHeroRoundActionButton: View {
    @Environment(\.isFocused) private var isFocused

    let systemImage: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let accessibilityValue: String
    let isActive: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: size, height: size)
                .background(backgroundFill, in: Circle())
                .overlay {
                    Circle()
                        .stroke(borderColor, lineWidth: 0.9)
                }
                .shadow(color: .black.opacity(isFocused ? 0.24 : 0.14), radius: isFocused ? 16 : 10, x: 0, y: isFocused ? 8 : 5)
                .scaleEffect(isFocused ? 1.03 : 1)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue(Text(accessibilityValue))
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }

    private var backgroundFill: Color {
        if isFocused {
            return Color.white.opacity(0.22)
        }
        return isActive ? Color.white.opacity(0.18) : Color.white.opacity(0.11)
    }

    private var borderColor: Color {
        isFocused ? Color.white.opacity(0.34) : Color.white.opacity(isActive ? 0.20 : 0.12)
    }
}

private struct IOSHeroAccessoryBadge: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.84))
            .frame(width: 26, height: 26)
            .background(Color.white.opacity(0.10), in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
            }
    }
}

private struct IOSSeasonHeaderMenu: View {
    let title: String
    let seasons: [MediaItem]
    let selectedSeasonID: String?
    let onSelect: (MediaItem) -> Void

    var body: some View {
        Group {
            if seasons.count > 1 {
                Menu {
                    ForEach(seasons) { season in
                        if season.id == selectedSeasonID {
                            Button {
                                onSelect(season)
                            } label: {
                                Label(season.name, systemImage: "checkmark")
                            }
                        } else {
                            Button(season.name) {
                                onSelect(season)
                            }
                        }
                    }
                } label: {
                    headerLabel
                }
            } else {
                headerLabel
            }
        }
    }

    private var headerLabel: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Image(systemName: "chevron.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
#endif

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
            width: preferredWidth(for: size, profile: .heroBackdropLow),
            quality: ArtworkRequestProfile.heroBackdropLow.quality,
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
            width: preferredWidth(for: size, profile: .heroBackdropHigh),
            quality: ArtworkRequestProfile.heroBackdropHigh.quality,
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

    private func preferredWidth(for _: CGSize, profile: ArtworkRequestProfile) -> Int {
        min(profile.width, 2_200)
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
    let isEnabled: Bool
    let visibility: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.16 : 0.08), lineWidth: 1)
            }
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .disabled(!isEnabled)
        .opacity((isFocused ? 1 : 0.88) * visibility)
        .scaleEffect((isFocused ? 1.04 : 0.98) - ((1 - visibility) * 0.08))
        .shadow(color: .black.opacity(isFocused ? 0.34 : 0.18), radius: isFocused ? 24 : 14, x: 0, y: isFocused ? 16 : 10)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .focused($isFocused)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isFocused)
        .animation(.smooth(duration: 0.30, extraBounce: 0.02), value: visibility)
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
    let optimizationStatus: ApplePlaybackOptimizationStatus?
    let playButtonLabel: String
    let playbackStatusText: String?
    let progress: Double?
    let isLoadingPlayback: Bool
    let isInWatchlist: Bool
    let isWatched: Bool
    let horizontalPadding: CGFloat
    let contentWidth: CGFloat
    let animateIn: Bool
    let prefersNativeZoomTransition: Bool
    let focusedAction: FocusState<DetailHeroAction?>.Binding
    let onPlay: () -> Void
    let onToggleWatchlist: () -> Void
    let onToggleWatched: () -> Void
    var layout: HeroMetadataLayout = .leading

    var body: some View {
        VStack(alignment: columnAlignment, spacing: verticalSpacing) {
            if shouldShowMetadataEyebrow {
                metadataEyebrow
            }

            Text(item.name)
                .font(titleFont)
                .foregroundStyle(.white)
                .lineLimit(3)
                .multilineTextAlignment(multilineTextAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .accessibilityAddTraits(.isHeader)

            if let subtitleText {
                Text(subtitleText)
                    .font(.system(size: subtitleFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(multilineTextAlignment)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
            }

            HeroMetadataLine(
                primaryText: metadataSummary,
                badges: heroBadges,
                centered: layout == .centered
            )

            if let playbackStatusText, !playbackStatusText.isEmpty {
                Text(playbackStatusText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .multilineTextAlignment(multilineTextAlignment)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
            }

            if let progress, progress > 0 {
                HeroProgressView(progress: progress, centered: layout == .centered)
            }

            PrimaryActionsRow(
                playButtonLabel: playButtonLabel,
                isLoadingPlayback: isLoadingPlayback,
                isInWatchlist: isInWatchlist,
                isWatched: isWatched,
                centered: layout == .centered,
                focusedAction: focusedAction,
                onPlay: onPlay,
                onToggleWatchlist: onToggleWatchlist,
                onToggleWatched: onToggleWatched
            )

            if let overview = item.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: overviewFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(overviewLineLimit)
                    .multilineTextAlignment(multilineTextAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
            }
        }
        .frame(maxWidth: contentWidth, alignment: frameAlignment)
        .padding(.horizontal, horizontalPadding)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : entryOffset)
        .animation(entryAnimation, value: animateIn)
    }

    private var entryAnimation: Animation {
        prefersNativeZoomTransition
            ? .easeOut(duration: 0.24)
            : .easeOut(duration: 0.45)
    }

    private var entryOffset: CGFloat {
        prefersNativeZoomTransition ? 0 : 22
    }

    private var metadataEyebrow: some View {
        HStack(spacing: 10) {
            if layout == .leading {
                HeroEyebrowBadge(text: item.mediaType.detailDisplayName)
            }

            if let airDayBadge, !airDayBadge.isEmpty {
                HeroEyebrowBadge(text: airDayBadge)
            }

            if let optimizationStatus {
                ApplePlaybackDetailBadge(status: optimizationStatus)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
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
        if layout == .leading, !item.genres.isEmpty {
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
        if layout == .centered {
            return centeredSubtitleText
        }
        if item.mediaType == .episode, let seriesName = item.seriesName {
            return seriesName
        }
        if item.mediaType == .series, !item.genres.isEmpty {
            return item.genres.prefix(2).joined(separator: " · ")
        }
        return nil
    }

    private var centeredSubtitleText: String? {
        var values: [String] = []

        switch item.mediaType {
        case .series:
            values.append("TV Show")
        case .movie:
            values.append("Movie")
        case .episode:
            if let season = item.parentIndexNumber, let episode = item.indexNumber {
                values.append("S\(season), E\(episode)")
            } else {
                values.append("Episode")
            }
        case .season:
            values.append("Season")
        case .unknown:
            break
        }

        if item.mediaType == .episode, let seriesName = item.seriesName, !seriesName.isEmpty {
            values.append(seriesName)
        } else if !item.genres.isEmpty {
            values.append(item.genres.prefix(2).joined(separator: " · "))
        }

        return values.isEmpty ? nil : values.joined(separator: " · ")
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
        let baseSize: CGFloat
        if layout == .centered {
            baseSize = item.name.count > 26 ? 68 : 80
        } else {
            baseSize = item.name.count > 26 ? 62 : 74
        }
        return .system(size: baseSize, weight: .bold, design: .rounded)
#else
        let baseSize: CGFloat = layout == .centered ? (item.name.count > 22 ? 46 : 58) : (item.name.count > 32 ? 38 : 48)
        return .system(size: baseSize, weight: .bold, design: .rounded)
#endif
    }

    private var subtitleFontSize: CGFloat {
#if os(tvOS)
        return 26
#else
        return layout == .centered ? 18 : 20
#endif
    }

    private var overviewFontSize: CGFloat {
#if os(tvOS)
        return 22
#else
        return layout == .centered ? 18 : 17
#endif
    }

    private var columnAlignment: HorizontalAlignment {
        layout == .centered ? .center : .leading
    }

    private var frameAlignment: Alignment {
        layout == .centered ? .center : .leading
    }

    private var multilineTextAlignment: TextAlignment {
        layout == .centered ? .center : .leading
    }

    private var overviewLineLimit: Int {
        layout == .centered ? 3 : 4
    }

    private var verticalSpacing: CGFloat {
#if os(tvOS)
        return layout == .centered ? 18 : 16
#else
        return layout == .centered ? 16 : 18
#endif
    }

    private var shouldShowMetadataEyebrow: Bool {
        if layout == .leading {
            return true
        }
        return (airDayBadge?.isEmpty == false) || optimizationStatus != nil
    }
}

private struct PrimaryActionsRow: View {
    let playButtonLabel: String
    let isLoadingPlayback: Bool
    let isInWatchlist: Bool
    let isWatched: Bool
    let centered: Bool
    let focusedAction: FocusState<DetailHeroAction?>.Binding
    let onPlay: () -> Void
    let onToggleWatchlist: () -> Void
    let onToggleWatched: () -> Void

    var body: some View {
#if os(tvOS)
        tvActionsRow
#else
        HStack(spacing: 18) {
            HeroPrimaryButton(
                title: playButtonLabel,
                isLoading: isLoadingPlayback,
                action: onPlay
            )
            .focused(focusedAction, equals: .play)

            HeroIconActionButton(
                systemImage: isInWatchlist ? "checkmark" : "plus",
                accessibilityLabel: isInWatchlist ? "In Watchlist" : "Add to Watchlist",
                isActive: isInWatchlist,
                action: onToggleWatchlist
            )
            .focused(focusedAction, equals: .watchlist)

            HeroIconActionButton(
                systemImage: isWatched ? "checkmark" : "eye",
                accessibilityLabel: isWatched ? "Marked Watched" : "Mark Watched",
                isActive: isWatched,
                action: onToggleWatched
            )
            .focused(focusedAction, equals: .watched)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .accessibilityElement(children: .contain)
#endif
    }

#if os(tvOS)
    private var tvActionsRow: some View {
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
        .defaultFocus(focusedAction, .play)
        .accessibilityElement(children: .contain)
    }
#endif
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
        if #available(tvOS 26.0, *) {
            tvOS26Button
        } else {
            legacyTVButton
        }
#else
        buttonContent
#endif
    }

    #if os(tvOS)
    @available(tvOS 26.0, *)
    private var tvOS26Button: some View {
        Button {
            guard !isLoading else { return }
            action()
        } label: {
            primaryLabel
                .frame(width: 318, height: 78)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.glass(Glass.clear.tint(Color.white.opacity(0.025))))
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .focused($isFocused)
        .accessibilityAddTraits(.isButton)
    }

    private var legacyTVButton: some View {
        Button {
            guard !isLoading else { return }
            action()
        } label: {
            primaryLabel
                .foregroundStyle(primaryButtonForeground)
                .frame(minWidth: 318, minHeight: 78)
                .padding(.horizontal, 26)
                .background { primaryButtonBackground }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .scaleEffect(isFocused ? 1.03 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.30 : 0.16), radius: isFocused ? 24 : 12, x: 0, y: isFocused ? 14 : 8)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isFocused)
        .accessibilityAddTraits(.isButton)
    }

    private var primaryLabel: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView()
                Text("Preparing")
            } else {
                Image(systemName: "play.fill")
                Text(title)
            }
        }
        .font(.system(size: 19, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var primaryButtonForeground: Color {
        .white.opacity(isFocused ? 0.98 : 0.92)
    }

    private var primaryButtonBackground: some View {
        Group {
            if isFocused {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.98))
            } else {
                Color.clear.reelFinGlassCapsule(
                    interactive: true,
                    tint: Color.white.opacity(0.18),
                    stroke: .clear,
                    strokeWidth: 0,
                    shadowOpacity: 0.12,
                    shadowRadius: 12,
                    shadowYOffset: 6
                )
            }
        }
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
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(.black.opacity(0.92))
            .frame(minWidth: 278, minHeight: 68)
            .padding(.horizontal, 28)
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

#if os(iOS)
private struct HeroIconActionButton: View {
    @Environment(\.isFocused) private var isFocused

    let systemImage: String
    let accessibilityLabel: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: 68, height: 68)
                .background(backgroundFill, in: Circle())
                .overlay {
                    Circle()
                        .stroke(borderColor, lineWidth: 0.9)
                }
                .shadow(color: .black.opacity(isFocused ? 0.26 : 0.14), radius: isFocused ? 18 : 12, x: 0, y: isFocused ? 10 : 6)
                .scaleEffect(isFocused ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }

    private var backgroundFill: Color {
        if isFocused {
            return Color.white.opacity(0.22)
        }
        return isActive ? Color.white.opacity(0.18) : Color.white.opacity(0.11)
    }

    private var borderColor: Color {
        isFocused ? Color.white.opacity(0.34) : Color.white.opacity(isActive ? 0.20 : 0.12)
    }
}
#endif

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
        if #available(tvOS 26.0, *) {
            tvOS26Button
        } else {
            legacyTVButton
        }
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
    @available(tvOS 26.0, *)
    private var tvOS26Button: some View {
        Button(action: action) {
            buttonLabel
                .foregroundStyle(.white.opacity(isFocused ? 0.98 : 0.90))
                .frame(width: 206, height: 72)
                .background { secondaryGlassBackground }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .scaleEffect(isFocused ? 1.035 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isFocused)
        .accessibilityAddTraits(.isButton)
    }

    @available(tvOS 26.0, *)
    private var secondaryGlassBackground: some View {
        Color.clear
            .glassEffect(
                Glass.regular
                    .tint(Color.white.opacity(isActive ? 0.045 : 0.032))
                    .interactive(),
                in: .capsule
            )
    }

    private var legacyTVButton: some View {
        Button(action: action) {
            buttonLabel
                .foregroundStyle(buttonForeground)
                .frame(minWidth: 196, minHeight: 72)
                .padding(.horizontal, 20)
                .background { buttonBackground }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .scaleEffect(isFocused ? 1.03 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.24 : 0.12), radius: isFocused ? 18 : 10, x: 0, y: isFocused ? 10 : 6)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isFocused)
        .accessibilityAddTraits(.isButton)
    }

    private var buttonLabel: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.86)
    }

    private var buttonForeground: Color {
        .white.opacity(isFocused ? 0.98 : 0.90)
    }

    private var buttonBackground: some View {
        Group {
            if isFocused {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.96))
            } else {
                Color.clear.reelFinGlassCapsule(
                    interactive: true,
                    tint: backgroundTint,
                    stroke: .clear,
                    strokeWidth: 0,
                    shadowOpacity: 0.10,
                    shadowRadius: 10,
                    shadowYOffset: 5
                )
            }
        }
    }

    private var backgroundTint: Color {
        if isActive { return Color.white.opacity(0.18) }
        return Color.white.opacity(0.09)
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
    var centered: Bool = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 12) {
            if !primaryText.isEmpty {
                Text(primaryText)
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .multilineTextAlignment(centered ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            }

            if !badges.isEmpty {
                if centered {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            ForEach(badges, id: \.self) { badge in
                                HeroInlineBadge(text: badge)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(badges, id: \.self) { badge in
                                    HeroInlineBadge(text: badge)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
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
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
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
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundFill, in: badgeShape)
            .overlay {
                badgeShape
                    .stroke(borderColor, lineWidth: 0.8)
            }
    }

    private var fontSize: CGFloat {
#if os(tvOS)
        return 15
#else
        return 12
#endif
    }

    private var horizontalPadding: CGFloat {
#if os(tvOS)
        return 10
#else
        return 9
#endif
    }

    private var verticalPadding: CGFloat {
#if os(tvOS)
        return 6
#else
        return 5
#endif
    }

    private var backgroundFill: Color {
#if os(tvOS)
        return Color.white.opacity(0.08)
#else
        return Color.white.opacity(0.06)
#endif
    }

    private var borderColor: Color {
#if os(tvOS)
        return Color.white.opacity(0.12)
#else
        return Color.white.opacity(0.22)
#endif
    }

    private var badgeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }
}

private struct HeroInlineSymbolBadge: View {
    let systemImage: String
    let tint: Color
    let accessibilityLabel: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundFill, in: badgeShape)
            .overlay {
                badgeShape
                    .stroke(borderColor, lineWidth: 0.8)
            }
            .accessibilityLabel(accessibilityLabel)
    }

    private var fontSize: CGFloat {
#if os(tvOS)
        return 15
#else
        return 12
#endif
    }

    private var horizontalPadding: CGFloat {
#if os(tvOS)
        return 10
#else
        return 9
#endif
    }

    private var verticalPadding: CGFloat {
#if os(tvOS)
        return 6
#else
        return 5
#endif
    }

    private var backgroundFill: Color {
#if os(tvOS)
        return Color.white.opacity(0.08)
#else
        return Color.white.opacity(0.06)
#endif
    }

    private var borderColor: Color {
#if os(tvOS)
        return tint.opacity(0.20)
#else
        return tint.opacity(0.28)
#endif
    }

    private var badgeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }
}

private struct HeroProgressView: View {
    let progress: Double
    var centered: Bool = false

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
        .frame(maxWidth: 280, alignment: centered ? .center : .leading)
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
                #if os(tvOS)
                .defaultFocus(focusedSeasonID, selectedSeasonID ?? seasons.first?.id)
                #endif
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
    let onMoveUp: (() -> Void)?
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
                            onMoveUp: onMoveUp,
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
    let onMoveUp: (() -> Void)?
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
        .hoverEffectDisabled(true)
        .onMoveCommand { direction in
            guard direction == .up else { return }
            onMoveUp?()
        }
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
    let onMoveUp: (() -> Void)?
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
                            onMoveUp: onMoveUp,
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
    let onMoveUp: (() -> Void)?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .scaleEffect(isFocused ? 1.045 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.34 : 0.18), radius: isFocused ? 26 : 12, x: 0, y: isFocused ? 16 : 8)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .onMoveCommand { direction in
            guard direction == .up else { return }
            onMoveUp?()
        }
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
        .focusSection()
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
