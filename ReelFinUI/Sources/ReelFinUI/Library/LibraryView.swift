import Shared
import SwiftUI

#if os(tvOS)
private enum TVLibraryWarmupScope {
    static let focus = "library.focus"
}
#endif

struct LibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.reelFinDisplayDensity) private var displayDensity
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Namespace private var posterNamespace
#if os(tvOS)
    @FocusState private var focusedControl: TVLibraryControlFocus?
    @FocusState private var focusedLibraryItemID: String?
#endif
    @State private var viewModel: LibraryViewModel
    private let dependencies: ReelFinDependencies
    @State private var warmupTask: Task<Void, Never>?
    @State private var selectedDetailTransitionSourceID: String?
#if os(tvOS)
    @State private var allowsControlBarTopNavigation = true
    @State private var controlBarNavigationUnlockTask: Task<Void, Never>?
    @State private var savedSelectedPosterID: String?
    @State private var tvOpeningArtworkItem: MediaItem?
    @State private var tvOpeningArtworkVisible = false
    @State private var tvDetailFocusRequest = 0
    @State private var detailPresentation = TVDetailPresentationCoordinator()
    @State private var detailPresentationVisualState = TVDetailPresentationVisualState.opening
#endif

    init(dependencies: ReelFinDependencies) {
        _viewModel = State(initialValue: LibraryViewModel(dependencies: dependencies))
        self.dependencies = dependencies
    }

    var body: some View {
        ZStack {
            ReelFinTheme.pageGradient.ignoresSafeArea()
#if os(tvOS)
            libraryContent
                .disabled(detailPresentation.keepsDetailMounted)
                .scaleEffect(detailPresentationVisualState == .presented ? 0.982 : 1)
                .opacity(detailPresentationVisualState == .presented ? 0.34 : 1)
                .overlay {
                    Color.black.opacity(detailPresentationVisualState == .presented ? 0.45 : 0)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

            tvInlineDetailPresentation
#else
            libraryContent
#endif
        }
        .navigationDestination(
            isPresented: nativeDetailNavigationBinding
        ) {
            if let item = viewModel.selectedItem {
                DetailView(
                    dependencies: dependencies,
                    item: item,
                    namespace: posterNamespace,
                    transitionSourceID: selectedDetailTransitionSourceID
                )
            }
        }
        .onDisappear {
            warmupTask?.cancel()
#if os(tvOS)
            controlBarNavigationUnlockTask?.cancel()
            if let coordinator = dependencies.tvFocusWarmupCoordinator {
                Task {
                    await coordinator.cancel(scope: TVLibraryWarmupScope.focus)
                }
            }
#endif
        }
        .task {
            await viewModel.loadInitial()
        }
        .onChange(of: viewModel.searchQuery) { _, _ in
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if !Task.isCancelled {
                    await viewModel.searchChanged()
                }
            }
        }
        .onChange(of: viewModel.selectedFilter) { _, _ in
            Task { await viewModel.loadInitial() }
        }
        .onChange(of: viewModel.sortMode) { _, _ in
            Task { await viewModel.loadInitial() }
        }
#if os(tvOS)
        .toolbar(.hidden, for: .navigationBar)
        .preference(key: TVTopNavigationAppearancePreferenceKey.self, value: .neutral)
#elseif os(iOS) && !targetEnvironment(macCatalyst)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }

    @ViewBuilder
    private var libraryContent: some View {
#if os(tvOS)
        GeometryReader { proxy in
            libraryContent(topRowItemIDs: tvTopRowItemIDs(containerWidth: proxy.size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
#else
        GeometryReader { proxy in
            libraryContent(
                topRowItemIDs: [],
                posterGridLayout: iosPosterGridLayout(containerWidth: proxy.size.width)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
#endif
    }

    private func libraryContent(
        topRowItemIDs: Set<String>,
        posterGridLayout: PosterGridLayout? = nil
    ) -> some View {
#if os(tvOS)
        VStack(spacing: 14) {
            topBar

            libraryScrollContent(topRowItemIDs: topRowItemIDs)
            .focusSection()
        }
#else
        StickyBlurHeader(
            maxBlurRadius: 12,
            fadeExtension: 88,
            tintOpacityTop: 0.48,
            tintOpacityMiddle: 0.18
        ) { _ in
            iosTopBar
                .padding(.top, stickyHeaderTopPadding)
                .padding(.bottom, 14)
                .accessibilityIdentifier("library_sticky_blur_header")
        } content: {
            libraryGridContent(
                topRowItemIDs: topRowItemIDs,
                gridColumns: posterGridLayout?.gridItems,
                cardWidth: posterGridLayout?.cardWidth
            )
        }
#endif
    }

    private func libraryScrollContent(topRowItemIDs: Set<String>) -> some View {
        ScrollView(showsIndicators: false) {
            libraryGridContent(topRowItemIDs: topRowItemIDs)
        }
        .contentMargins(
            .top,
            TVLibraryFocusLayout.firstRowTopReserve(cardWidth: 240, scale: 1.06),
            for: .scrollContent
        )
    }

    private func libraryGridContent(
        topRowItemIDs: Set<String>,
        gridColumns: [GridItem]? = nil,
        cardWidth: CGFloat? = nil
    ) -> some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: gridColumns ?? columns, spacing: gridSpacing) {
                ForEach(viewModel.items) { item in
#if os(tvOS)
                    TVLibraryPosterCard(
                        item: item,
                        dependencies: dependencies,
                        namespace: posterNamespace,
                        transitionSourceID: LibraryCardTransitionSource.id(itemID: item.id),
                        onFocus: { focusedItem in
                            focusedLibraryItemID = focusedItem.id
                            handleFocusedItem(focusedItem)
                        },
                        onMoveUp: topRowItemIDs.contains(item.id) ? focusPreferredControlBar : nil,
                        onSelect: { selectedItem in
                            presentTVDetail(selectedItem)
                        }
                    )
                    .focused($focusedLibraryItemID, equals: item.id)
                    .onAppear {
                        handleVisibleItem(item)
                    }
#else
                    VStack(alignment: .leading, spacing: displayDensity.scaledSpacing(10)) {
                        Button {
                            selectedDetailTransitionSourceID = LibraryCardTransitionSource.id(itemID: item.id)
                            let detailItemID = item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
                            Task {
                                await DetailPresentationTelemetry.shared.beginNavigation(for: detailItemID)
                            }
                            viewModel.select(item: item)
                        } label: {
                            PosterCardArtworkView(
                                item: item,
                                apiClient: dependencies.apiClient,
                                imagePipeline: dependencies.imagePipeline,
                                layoutStyle: .grid,
                                namespace: posterNamespace,
                                transitionSourceID: LibraryCardTransitionSource.id(itemID: item.id),
                                preferredWidth: cardWidth
                            )
                        }
                        .accessibilityIdentifier("media_card_button_\(item.id)")
                        .buttonStyle(.plain)

                        PosterCardMetadataView(
                            item: item,
                            layoutStyle: .grid,
                            preferredWidth: cardWidth
                        )
                    }
                    .onAppear {
                        handleVisibleItem(item)
                    }
#endif
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 24)

            if viewModel.isLoadingPage {
                ProgressView()
                    .tint(.white)
                    .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var topBar: some View {
#if os(tvOS)
        tvTopBar
#else
        iosTopBar
#endif
    }

#if os(tvOS)
    private var tvTopBar: some View {
        TVLibraryControlBar(
            selectedFilter: viewModel.selectedFilter,
            sortMode: viewModel.sortMode,
            focusedControl: $focusedControl,
            allowsTopNavigationRedirect: allowsControlBarTopNavigation,
            onFilterChange: setTVFilter,
            onSortToggle: toggleTVSortMode
        )
    }
#endif

    // MARK: - iOS top bar: full search bar + filter chips

    private var iosTopBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Library")
                    .reelFinTitleStyle()
                Spacer()

                Menu {
                    Picker("Sort", selection: $viewModel.sortMode) {
                        ForEach(LibraryViewModel.SortMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.white.opacity(0.98))
                        .background {
                            libraryCircleBackground()
                        }
                }
            }

            HStack(spacing: 10) {
                filterChip(title: "Movies", filter: .movie)
                filterChip(title: "Shows", filter: .series)
                Spacer()
            }

            TextField(
                "",
                text: $viewModel.searchQuery,
                prompt: Text("Search your library")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            )
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled(true)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .padding(.horizontal, 16)
                .frame(height: 52)
                .foregroundStyle(.white.opacity(0.98))
                .background {
                    librarySearchBackground()
                }
        }
        .padding(.horizontal, horizontalPadding)
    }

    private func filterChip(title: String, filter: MediaType) -> some View {
        let isActive = viewModel.selectedFilter == filter

        return Button {
            viewModel.selectedFilter = filter
        } label: {
            Text(title)
                .font(.system(size: chipFontSize, weight: .bold, design: .rounded))
                .frame(minWidth: 82)
                .padding(.horizontal, chipHPad)
                .padding(.vertical, chipVPad)
                .foregroundStyle(isActive ? Color.black.opacity(0.92) : Color.white.opacity(0.98))
                .shadow(color: .black.opacity(isActive ? 0.10 : 0.24), radius: isActive ? 1 : 2, y: 1)
                .background {
                    libraryFilterBackground(isActive: isActive)
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func libraryCircleBackground() -> some View {
        if #available(iOS 26.0, tvOS 26.0, *) {
            Circle()
                .fill(Color.white.opacity(0.10))
                .overlay {
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
                .glassEffect(.clear.interactive(), in: .circle)
                .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 5)
        } else {
            Color.clear.reelFinGlassCircle(
                interactive: true,
                tint: Color.black.opacity(0.22),
                stroke: Color.white.opacity(0.14),
                shadowOpacity: 0.14,
                shadowRadius: 12,
                shadowYOffset: 5
            )
        }
    }

    @ViewBuilder
    private func librarySearchBackground() -> some View {
        if #available(iOS 26.0, tvOS 26.0, *) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
                .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 18))
                .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 6)
        } else {
            Color.clear.reelFinGlassRoundedRect(
                cornerRadius: 18,
                interactive: true,
                tint: Color.black.opacity(0.22),
                stroke: Color.white.opacity(0.14),
                shadowOpacity: 0.14,
                shadowRadius: 14,
                shadowYOffset: 6
            )
        }
    }

    @ViewBuilder
    private func libraryFilterBackground(isActive: Bool) -> some View {
        if #available(iOS 26.0, tvOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(isActive ? Color.white.opacity(0.90) : Color.white.opacity(0.10))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            isActive ? Color.white.opacity(0.28) : Color.white.opacity(0.16),
                            lineWidth: 1
                        )
                }
                .glassEffect(.clear.interactive(), in: .capsule)
                .shadow(color: .black.opacity(isActive ? 0.08 : 0.10), radius: isActive ? 10 : 8, x: 0, y: 4)
        } else {
            Color.clear.reelFinGlassCapsule(
                interactive: true,
                tint: isActive ? Color.white.opacity(0.22) : Color.black.opacity(0.22),
                stroke: Color.white.opacity(isActive ? 0.20 : 0.14),
                shadowOpacity: isActive ? 0.15 : 0.10,
                shadowRadius: isActive ? 12 : 8,
                shadowYOffset: 4
            )
        }
    }

    @ViewBuilder
    private func glassGroup<Content: View>(
        spacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 26.0, tvOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }

    private var stickyHeaderTopPadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 12
    }

    private var columns: [GridItem] {
#if os(tvOS)
        return [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 32)]
#else
        let width = PosterCardMetrics.posterWidth(
            for: .grid,
            compact: horizontalSizeClass == .compact,
            displayDensity: displayDensity
        )
        return [GridItem(.adaptive(minimum: width, maximum: width), spacing: gridSpacing)]
#endif
    }

    private var gridSpacing: CGFloat {
#if os(tvOS)
        return 40
#else
        return displayDensity.scaledSpacing(horizontalSizeClass == .compact ? 12 : 16)
#endif
    }

    private var horizontalPadding: CGFloat {
#if os(tvOS)
        return 56
#else
        return displayDensity.scaledSpacing(horizontalSizeClass == .compact ? 12 : 22)
#endif
    }

    private func iosPosterGridLayout(containerWidth: CGFloat) -> PosterGridLayout {
        PosterGridLayout(
            containerWidth: containerWidth,
            horizontalPadding: horizontalPadding,
            spacing: gridSpacing,
            minimumCardWidth: PosterCardMetrics.posterWidth(
                for: .grid,
                compact: horizontalSizeClass == .compact,
                displayDensity: displayDensity
            )
        )
    }

    private var chipFontSize: CGFloat {
#if os(tvOS)
        return 18
#else
        return displayDensity.scaledTextSize(15)
#endif
    }

    private var chipHPad: CGFloat {
#if os(tvOS)
        return 20
#else
        return displayDensity.scaledSpacing(14)
#endif
    }

    private var chipVPad: CGFloat {
#if os(tvOS)
        return 12
#else
        return displayDensity.scaledSpacing(9)
#endif
    }

    private func handleFocusedItem(_ item: MediaItem) {
#if os(tvOS)
        if let coordinator = dependencies.tvFocusWarmupCoordinator {
            Task(priority: .background) {
                await coordinator.schedule(
                    scope: TVLibraryWarmupScope.focus,
                    detailShell: {
                        await dependencies.detailRepository.primeItem(id: item.id)
                        guard !Task.isCancelled else { return }
                        await dependencies.detailRepository.primeDetail(id: item.id)
                    },
                    artworkPrefetch: {
                        await dependencies.apiClient.prefetchImages(for: [item])
                        guard !Task.isCancelled else { return }

                        if let heroURL = await dependencies.apiClient.imageURL(
                            for: item.id,
                            type: item.backdropTag == nil ? .primary : .backdrop,
                            width: ArtworkRequestProfile.heroBackdropHigh.width,
                            quality: ArtworkRequestProfile.heroBackdropHigh.quality
                        ) {
                            await dependencies.imagePipeline.prefetch(urls: [heroURL])
                        }
                    },
                    playbackWarmup: {
                        guard !Task.isCancelled else { return }
                        await dependencies.playbackWarmupManager.trim(keeping: [item.id])
                        guard !Task.isCancelled else { return }
                        await warmPlaybackItem(item)
                    }
                )
            }
            return
        }
#endif
        warmupTask?.cancel()
        warmupTask = Task(priority: .background) {
            await dependencies.detailRepository.primeItem(id: item.id)
            guard !Task.isCancelled else { return }
            await dependencies.detailRepository.primeDetail(id: item.id)
            guard !Task.isCancelled else { return }
            await dependencies.apiClient.prefetchImages(for: [item])
            guard !Task.isCancelled else { return }

            if let heroURL = await dependencies.apiClient.imageURL(
                for: item.id,
                type: item.backdropTag == nil ? .primary : .backdrop,
                width: ArtworkRequestProfile.heroBackdropHigh.width,
                quality: ArtworkRequestProfile.heroBackdropHigh.quality
            ) {
                await dependencies.imagePipeline.prefetch(urls: [heroURL])
            }
            guard !Task.isCancelled else { return }

            await dependencies.playbackWarmupManager.trim(keeping: [item.id])
            guard !Task.isCancelled else { return }
            await warmPlaybackItem(item)
        }
    }

    private func warmPlaybackItem(_ item: MediaItem) async {
        await dependencies.playbackWarmupManager.warm(
            itemID: item.id,
            resumeSeconds: Self.resumeSeconds(for: item),
            runtimeSeconds: Self.runtimeSeconds(for: item),
            isTVOS: Self.isTVOSPlatform
        )
    }

    private static var isTVOSPlatform: Bool {
#if os(tvOS)
        true
#else
        false
#endif
    }

    private static func resumeSeconds(for item: MediaItem) -> Double {
        guard let ticks = item.playbackPositionTicks, ticks > 0 else {
            return 0
        }
        return Double(ticks) / 10_000_000
    }

    private static func runtimeSeconds(for item: MediaItem) -> Double? {
        guard let ticks = item.runtimeTicks, ticks > 0 else {
            return nil
        }
        return Double(ticks) / 10_000_000
    }

    private func handleVisibleItem(_ item: MediaItem) {
        guard viewModel.paginationTriggerItemID == item.id else { return }
        Task {
            await viewModel.loadMoreIfNeeded()
        }
    }

    private var nativeDetailNavigationBinding: Binding<Bool> {
        Binding(
            get: {
#if os(tvOS)
                false
#else
                viewModel.selectedItem != nil
#endif
            },
            set: { isPresented in
                guard !isPresented else { return }
#if os(tvOS)
                dismissTVDetailPresentation()
#else
                viewModel.selectedItem = nil
                selectedDetailTransitionSourceID = nil
#endif
            }
        )
    }

#if os(tvOS)
    @ViewBuilder
    private var tvInlineDetailPresentation: some View {
        if let item = viewModel.selectedItem {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                DetailView(
                    dependencies: dependencies,
                    item: item,
                    namespace: posterNamespace,
                    transitionSourceID: selectedDetailTransitionSourceID,
                    tvPresentationFocusRequest: tvDetailFocusRequest,
                    onDismissRequest: dismissTVDetailPresentation
                )
                .ignoresSafeArea()

                if let tvOpeningArtworkItem {
                    TVDetailOpeningArtworkView(
                        item: tvOpeningArtworkItem,
                        apiClient: dependencies.apiClient,
                        imagePipeline: dependencies.imagePipeline
                    )
                    .modifier(
                        TVInlineDetailArtworkDestinationModifier(
                            namespace: posterNamespace,
                            sourceID: selectedDetailTransitionSourceID
                        )
                    )
                    .opacity(tvOpeningArtworkVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .zIndex(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .opacity(detailPresentationVisualState == .closing ? 0 : 1)
            .scaleEffect(
                detailPresentationVisualState == .closing && !accessibilityReduceMotion ? 0.97 : 1,
                anchor: .center
            )
            .transition(tvInlineDetailTransition)
            .zIndex(10)
        }
    }

    private var tvInlineDetailTransition: AnyTransition {
        if accessibilityReduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .center)),
            removal: .opacity
        )
    }

    private var tvDetailOpenAnimation: Animation {
        .smooth(
            duration: accessibilityReduceMotion
                ? TVDetailTransitionMetrics.reducedMotionDuration
                : TVDetailTransitionMetrics.openingDuration,
            extraBounce: accessibilityReduceMotion ? 0 : 0.04
        )
    }

    private var tvDetailCloseAnimation: Animation {
        .smooth(
            duration: accessibilityReduceMotion
                ? TVDetailTransitionMetrics.reducedMotionDuration
                : TVDetailTransitionMetrics.closingDuration,
            extraBounce: 0
        )
    }

    private func presentTVDetail(_ item: MediaItem) {
        let sourceID = LibraryCardTransitionSource.id(itemID: item.id)
        let detailItemID = item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
        selectedDetailTransitionSourceID = sourceID
        savedSelectedPosterID = item.id
        detailPresentation.beginOpening(itemID: detailItemID, sourceID: sourceID)
        guard case .opening = detailPresentation.phase else { return }

        detailPresentationVisualState = .opening
        tvOpeningArtworkItem = item
        tvOpeningArtworkVisible = true

        Task {
            await DetailPresentationTelemetry.shared.beginNavigation(for: detailItemID)
        }

        withAnimation(tvDetailOpenAnimation, completionCriteria: .logicallyComplete) {
            viewModel.select(item: item, animated: false)
            detailPresentationVisualState = .presented
            tvOpeningArtworkVisible = false
        } completion: {
            guard viewModel.selectedItem?.id == item.id else { return }
            guard case .opening = detailPresentation.phase else { return }
            detailPresentation.finishOpening()
            tvOpeningArtworkItem = nil
            tvDetailFocusRequest &+= 1
        }
    }

    private func dismissTVDetailPresentation() {
        let backResult = detailPresentation.handleBack()
        logTVBackNavigationMarker(backResult == .allowRoot ? .root : .closing)
        guard backResult == .beginClosing else { return }

        let returnPosterID = savedSelectedPosterID
        tvOpeningArtworkItem = viewModel.selectedItem
        tvOpeningArtworkVisible = false

        withAnimation(tvDetailCloseAnimation, completionCriteria: .logicallyComplete) {
            detailPresentationVisualState = .closing
            tvOpeningArtworkVisible = true
        } completion: {
            viewModel.dismissDetail(animated: false)
            detailPresentation.finishClosing()
            tvOpeningArtworkVisible = false
            tvOpeningArtworkItem = nil
            selectedDetailTransitionSourceID = nil
            savedSelectedPosterID = nil
            focusedLibraryItemID = returnPosterID
        }
    }

    private func logTVBackNavigationMarker(_ marker: TVBackNavigationDebugMarker) {
#if DEBUG
        AppLog.ui.notice("tv.back.owner value=\(marker.rawValue, privacy: .public)")
#endif
    }

    private func setTVFilter(_ filter: MediaType) {
        viewModel.selectedFilter = filter
    }

    private func toggleTVSortMode() {
        viewModel.sortMode = viewModel.sortMode == .recent ? .title : .recent
    }

    private func focusPreferredControlBar() {
        focusControlBar(preferredControlBarTarget)
    }

    private func focusControlBar(_ target: TVLibraryControlFocus) {
        controlBarNavigationUnlockTask?.cancel()
        allowsControlBarTopNavigation = false
        focusedControl = target

        controlBarNavigationUnlockTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            allowsControlBarTopNavigation = true
        }
    }

    private var preferredControlBarTarget: TVLibraryControlFocus {
        viewModel.selectedFilter == .series ? .shows : .movies
    }

    private func tvTopRowItemIDs(containerWidth: CGFloat) -> Set<String> {
        TVAdaptiveGridFocusLayout(
            containerWidth: containerWidth,
            horizontalPadding: horizontalPadding,
            minimumItemWidth: 240,
            interItemSpacing: 32
        )
        .firstRowItemIDs(in: viewModel.items)
    }
#endif
}

struct TVAdaptiveGridFocusLayout: Equatable {
    let containerWidth: CGFloat
    let horizontalPadding: CGFloat
    let minimumItemWidth: CGFloat
    let interItemSpacing: CGFloat

    var columnCount: Int {
        let usableWidth = max(containerWidth - (horizontalPadding * 2), minimumItemWidth)
        return max(Int((usableWidth + interItemSpacing) / (minimumItemWidth + interItemSpacing)), 1)
    }

    func isInFirstRow(index: Int) -> Bool {
        index >= 0 && index < columnCount
    }

    func firstRowItemIDs<Item: Identifiable>(in items: [Item]) -> Set<Item.ID> where Item.ID: Hashable {
        Set(items.prefix(columnCount).map(\.id))
    }
}
