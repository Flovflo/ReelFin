import Shared
import SwiftUI

enum LibraryHeaderPresentation: Equatable {
    case expanded
    case compact

    static let revealDistance: CGFloat = 160
    static let compactRevealThreshold: CGFloat = 18.0 / 24.0

    static func resolve(quantizedRevealProgress: CGFloat) -> Self {
        quantizedRevealProgress >= compactRevealThreshold ? .compact : .expanded
    }
}

struct LibraryHeaderTransition: Equatable {
    let expandedControlsOpacity: CGFloat
    let compactHeaderOpacity: CGFloat
    let expandedControlsAreInteractive: Bool
    let compactHeaderIsInteractive: Bool

    private static let transitionStart: CGFloat = 0.56
    private static let transitionEnd: CGFloat = 0.84

    static func resolve(revealProgress: CGFloat) -> Self {
        let finiteProgress = revealProgress.isFinite ? revealProgress : 0
        let normalized = min(
            max(
                (finiteProgress - transitionStart) / (transitionEnd - transitionStart),
                0
            ),
            1
        )
        let eased = normalized * normalized * (3 - (2 * normalized))
        let compactIsPrimary = eased >= 0.5

        return Self(
            expandedControlsOpacity: 1 - eased,
            compactHeaderOpacity: eased,
            expandedControlsAreInteractive: !compactIsPrimary,
            compactHeaderIsInteractive: compactIsPrimary
        )
    }
}

enum LibraryResultContext {
    static func resolve(visibleItemCount: Int, isUpdating: Bool) -> String {
        let count = max(visibleItemCount, 0)
        let base: String

        switch count {
        case 0:
            base = isUpdating ? "Loading titles" : "No titles visible"
        case 1:
            base = "1 title visible"
        default:
            base = "\(count) titles visible"
        }

        return isUpdating && count > 0 ? "\(base) · Updating" : base
    }
}

enum TVLibraryGridMetrics {
    static let horizontalPadding: CGFloat = 56
    static let minimumItemWidth: CGFloat = 240
    static let maximumItemWidth: CGFloat = 280
    static let interItemSpacing: CGFloat = 32

    static func focusLayout(containerWidth: CGFloat) -> TVAdaptiveGridFocusLayout {
        TVAdaptiveGridFocusLayout(
            containerWidth: containerWidth,
            horizontalPadding: horizontalPadding,
            minimumItemWidth: minimumItemWidth,
            interItemSpacing: interItemSpacing
        )
    }
}

#if os(tvOS)
private enum TVLibraryWarmupScope {
    static let focus = "library.focus"
}
#endif

struct LibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.reelFinDisplayDensity) private var displayDensity
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Namespace private var posterNamespace
#if os(tvOS)
    @FocusState private var focusedControl: TVLibraryControlFocus?
    @FocusState private var focusedLibraryItemID: String?
#endif
    @State private var viewModel: LibraryViewModel
    private let dependencies: ReelFinDependencies
    @State private var searchDebounceTask: Task<Void, Never>?
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
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
            viewModel.cancelIntents()
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
            _ = viewModel.submitCriteria()
        }
        .onChange(of: viewModel.searchQuery) { _, _ in
            scheduleSearchCriteriaSubmission()
        }
        .onChange(of: viewModel.selectedFilter) { _, _ in
            submitCriteriaImmediately()
        }
        .onChange(of: viewModel.sortMode) { _, _ in
            submitCriteriaImmediately()
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
                posterGridLayout: iosPosterGridLayout(containerWidth: proxy.size.width),
                safeAreaTopInset: proxy.safeAreaInsets.top
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
#endif
    }

    private func libraryContent(
        topRowItemIDs: Set<String>,
        posterGridLayout: PosterGridLayout? = nil,
        safeAreaTopInset: CGFloat = 0
    ) -> some View {
#if os(tvOS)
        VStack(spacing: 14) {
            tvTopBar

            libraryScrollContent(topRowItemIDs: topRowItemIDs)
            .focusSection()
        }
#else
        StickyBlurHeader(
            maxBlurRadius: 12,
            fadeExtension: 88,
            tintOpacityTop: 0.48,
            tintOpacityMiddle: 0.18,
            statusBarBlurOpacity: 0.42,
            contentTopInset: 0,
            visibility: .revealOnScroll(
                distance: LibraryHeaderPresentation.revealDistance,
                minimumEffectOpacity: 0
            ),
            opaqueFallbackRevealThreshold: LibraryHeaderPresentation.compactRevealThreshold
        ) { quantizedRevealProgress in
            let transition = LibraryHeaderTransition.resolve(
                revealProgress: quantizedRevealProgress
            )

            iosCompactHeader(safeAreaTopInset: safeAreaTopInset)
                .opacity(transition.compactHeaderOpacity)
                .offset(y: (1 - transition.compactHeaderOpacity) * -8)
                .scaleEffect(0.98 + (0.02 * transition.compactHeaderOpacity))
                .allowsHitTesting(transition.compactHeaderIsInteractive)
                .accessibilityHidden(!transition.compactHeaderIsInteractive)
        } content: { quantizedRevealProgress in
            let transition = LibraryHeaderTransition.resolve(
                revealProgress: quantizedRevealProgress
            )

            VStack(spacing: 0) {
                iosExpandedHeader(
                    safeAreaTopInset: safeAreaTopInset,
                    transition: transition
                )

                libraryGridContent(
                    topRowItemIDs: topRowItemIDs,
                    gridColumns: posterGridLayout?.gridItems,
                    cardWidth: posterGridLayout?.cardWidth
                )
            }
        }
        .ignoresSafeArea(edges: .top)
#endif
    }

#if os(tvOS)
    private func libraryScrollContent(topRowItemIDs: Set<String>) -> some View {
        ScrollView(showsIndicators: false) {
            libraryGridContent(topRowItemIDs: topRowItemIDs)
        }
        .contentMargins(
            .top,
            TVLibraryFocusLayout.firstRowTopReserve(
                cardWidth: 240,
                scale: TVFocusGeometry.scale(for: .libraryPoster, reduceMotion: accessibilityReduceMotion)
            ),
            for: .scrollContent
        )
    }
#endif

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
                        isFocused: focusedLibraryItemID == item.id,
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

#if os(iOS)
    // MARK: - iOS editorial Library header

    private func iosExpandedHeader(
        safeAreaTopInset: CGFloat,
        transition: LibraryHeaderTransition
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("YOUR JELLYFIN COLLECTION")
                    .font(.caption.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(ReelFinTheme.editorialAccent)

                Text("Library")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(ReelFinTheme.editorialPrimaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("library_expanded_header")

                Text(libraryResultContext)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ReelFinTheme.editorialSecondaryText)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("library_result_context")
            }

            iosSearchField

            iosControlCluster(compact: false)
                .opacity(transition.expandedControlsOpacity)
                .offset(y: (1 - transition.expandedControlsOpacity) * -6)
                .scaleEffect(0.98 + (0.02 * transition.expandedControlsOpacity))
                .allowsHitTesting(transition.expandedControlsAreInteractive)
                .accessibilityHidden(!transition.expandedControlsAreInteractive)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, safeAreaTopInset + expandedHeaderTopSpacing)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iosCompactHeader(safeAreaTopInset: CGFloat) -> some View {
        HStack(spacing: 10) {
            Text("Library")
                .font(.headline.weight(.bold))
                .foregroundStyle(ReelFinTheme.editorialPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("library_sticky_blur_header")

            Spacer(minLength: 4)

            iosControlCluster(compact: true)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, safeAreaTopInset + 6)
        .padding(.bottom, 10)
        .frame(height: safeAreaTopInset + 72, alignment: .bottom)
        .frame(maxWidth: .infinity)
    }

    private var iosSearchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(ReelFinTheme.editorialSecondaryText)
                .accessibilityHidden(true)

            TextField(
                "",
                text: $viewModel.searchQuery,
                prompt: Text("Search your library")
                    .foregroundStyle(ReelFinTheme.editorialSecondaryText)
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.search)
            .font(.body.weight(.medium))
            .foregroundStyle(ReelFinTheme.editorialPrimaryText)
            .accessibilityIdentifier("library_search_field")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background { librarySearchBackground }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func iosControlCluster(compact: Bool) -> some View {
        glassGroup(spacing: compact ? 8 : 10) {
            HStack(spacing: compact ? 8 : 10) {
                filterChip(title: "Movies", filter: .movie, compact: compact)
                filterChip(title: "Shows", filter: .series, compact: compact)
                sortControl(compact: compact)
            }
        }
    }

    private func filterChip(
        title: String,
        filter: MediaType,
        compact: Bool
    ) -> some View {
        let isActive = viewModel.selectedFilter == filter

        return Button {
            viewModel.selectedFilter = filter
        } label: {
            libraryControlSurface(isActive: isActive) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(compact ? 0.5 : 0.78)
                    .frame(minWidth: compact ? 54 : 72)
                    .frame(width: compact ? 54 : nil)
                    .padding(.horizontal, compact ? 8 : 12)
                    .padding(.vertical, compact ? 9 : 11)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func sortControl(compact: Bool) -> some View {
        Menu {
            Picker("Sort", selection: $viewModel.sortMode) {
                ForEach(LibraryViewModel.SortMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
        } label: {
            libraryControlSurface(isActive: false) {
                HStack(spacing: compact ? 5 : 7) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption.weight(.bold))

                    if !compact || !dynamicTypeSize.isAccessibilitySize {
                        Text(dynamicTypeSize.isAccessibilitySize ? "Sort" : sortModeDisplayTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(compact ? 0.5 : 0.74)
                    }
                }
                .font(.subheadline.weight(.bold))
                .frame(minWidth: compact ? 62 : 86)
                .frame(width: compact ? 62 : nil)
                .padding(.horizontal, compact ? 8 : 12)
                .padding(.vertical, compact ? 9 : 11)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort, \(sortModeDisplayTitle)")
        .accessibilityIdentifier("library_sort_control")
    }

    @ViewBuilder
    private func libraryControlSurface<Content: View>(
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = Capsule(style: .continuous)

        switch EditorialGlassRole.compactControl.presentation(
            reduceTransparency: accessibilityReduceTransparency
        ) {
        case .interactiveGlass:
            content()
                .foregroundStyle(
                    isActive ? Color.black.opacity(0.94) : ReelFinTheme.editorialPrimaryText
                )
                .background {
                    shape.fill(isActive ? Color.white.opacity(0.34) : Color.clear)
                }
                .glassEffect(
                    Glass.regular
                        .tint(
                            isActive
                                ? Color.white.opacity(0.56)
                                : ReelFinTheme.editorialGlassTint
                        )
                        .interactive(),
                    in: .capsule
                )
                .overlay {
                    shape.stroke(
                        Color.white.opacity(isActive ? 0.30 : 0.16),
                        lineWidth: 1
                    )
                }
                .contentShape(shape)
        case .opaque:
            content()
                .foregroundStyle(ReelFinTheme.editorialPrimaryText)
                .background { shape.fill(ReelFinTheme.editorialOpaqueFallback) }
                .overlay {
                    shape.stroke(
                        Color.white.opacity(isActive ? 0.46 : 0.30),
                        lineWidth: 1.2
                    )
                }
                .contentShape(shape)
        case .passiveGlass:
            content()
                .foregroundStyle(ReelFinTheme.editorialPrimaryText)
                .glassEffect(
                    Glass.regular.tint(ReelFinTheme.editorialGlassTint),
                    in: .capsule
                )
                .contentShape(shape)
        }
    }

    private var librarySearchBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return shape
            .fill(
                accessibilityReduceTransparency
                    ? ReelFinTheme.editorialOpaqueFallback
                    : Color.white.opacity(0.075)
            )
            .overlay {
                shape.stroke(
                    Color.white.opacity(accessibilityReduceTransparency ? 0.30 : 0.14),
                    lineWidth: accessibilityReduceTransparency ? 1.2 : 1
                )
            }
    }

    @ViewBuilder
    private func glassGroup<Content: View>(
        spacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }

    private var libraryResultContext: String {
        LibraryResultContext.resolve(
            visibleItemCount: viewModel.items.count,
            isUpdating: viewModel.isLoadingPage
        )
    }

    private var sortModeDisplayTitle: String {
        viewModel.sortMode == .recent ? "Recent" : "A–Z"
    }

    private var expandedHeaderTopSpacing: CGFloat {
        horizontalSizeClass == .compact ? 24 : 34
    }
#endif

    private var columns: [GridItem] {
#if os(tvOS)
        return [
            GridItem(
                .adaptive(
                    minimum: TVLibraryGridMetrics.minimumItemWidth,
                    maximum: TVLibraryGridMetrics.maximumItemWidth
                ),
                spacing: TVLibraryGridMetrics.interItemSpacing
            )
        ]
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
        return TVLibraryGridMetrics.horizontalPadding
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
                        await dependencies.artworkPrefetcher.prefetch([
                            ArtworkRequest.make(for: item, role: .posterGrid),
                            ArtworkRequest.make(for: item, role: .heroHigh)
                        ])
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
            await dependencies.artworkPrefetcher.prefetch([
                ArtworkRequest.make(for: item, role: .posterGrid),
                ArtworkRequest.make(for: item, role: .heroHigh)
            ])
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
        _ = viewModel.submitPaginationIfNeeded()
    }

    private func scheduleSearchCriteriaSubmission() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            searchDebounceTask = nil
            _ = viewModel.submitCriteria()
        }
    }

    private func submitCriteriaImmediately() {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        _ = viewModel.submitCriteria()
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

        // Keep the poster id in savedSelectedPosterID, but release its active FocusState before
        // mounting DetailView. Otherwise the outgoing grid can win the first focus transaction.
        focusedLibraryItemID = nil
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
        TVLibraryGridMetrics.focusLayout(containerWidth: containerWidth)
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
