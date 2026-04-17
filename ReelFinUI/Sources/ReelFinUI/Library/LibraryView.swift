import Shared
import SwiftUI

#if os(tvOS)
private enum TVLibraryWarmupScope {
    static let focus = "library.focus"
}
#endif

struct LibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#if os(tvOS)
    @Environment(\.tvContentFocusReadyAction) private var notifyContentFocusReady
    @FocusState private var focusedControl: TVLibraryControlFocus?
#endif
    @StateObject private var viewModel: LibraryViewModel
    private let dependencies: ReelFinDependencies
    private let contentFocusRequest: TVContentFocusRequest?
    @State private var warmupTask: Task<Void, Never>?
#if os(tvOS)
    @State private var allowsControlBarTopNavigation = true
    @State private var controlBarNavigationUnlockTask: Task<Void, Never>?
    @State private var lastHandledContentFocusSequence = 0
#endif

    init(dependencies: ReelFinDependencies) {
        self.init(dependencies: dependencies, contentFocusRequest: nil)
    }

    init(dependencies: ReelFinDependencies, contentFocusRequest: TVContentFocusRequest?) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(dependencies: dependencies))
        self.dependencies = dependencies
        self.contentFocusRequest = contentFocusRequest
    }

    var body: some View {
        ZStack {
            ReelFinTheme.pageGradient.ignoresSafeArea()
            libraryContent
        }
        .navigationDestination(
            isPresented: Binding(
                get: { viewModel.selectedItem != nil },
                set: { if !$0 { viewModel.selectedItem = nil } }
            )
        ) {
            if let item = viewModel.selectedItem {
                DetailView(
                    dependencies: dependencies,
                    item: item
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
        .onAppear {
            applyContentFocusRequestIfNeeded()
        }
        .onChange(of: contentFocusRequest?.sequence) { _, _ in
            applyContentFocusRequestIfNeeded()
        }
        .toolbar(.hidden, for: .navigationBar)
        .preference(key: TVTopNavigationAppearancePreferenceKey.self, value: .neutral)
#elseif os(iOS)
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
        libraryContent(topRowItemIDs: [])
#endif
    }

    private func libraryContent(topRowItemIDs: Set<String>) -> some View {
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
                .padding(.bottom, 10)
                .accessibilityIdentifier("library_sticky_blur_header")
        } content: {
            libraryGridContent(topRowItemIDs: topRowItemIDs)
        }
#endif
    }

    private func libraryScrollContent(topRowItemIDs: Set<String>) -> some View {
        ScrollView(showsIndicators: false) {
            libraryGridContent(topRowItemIDs: topRowItemIDs)
        }
    }

    private func libraryGridContent(topRowItemIDs: Set<String>) -> some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(viewModel.items) { item in
#if os(tvOS)
                    TVLibraryPosterCard(
                        item: item,
                        dependencies: dependencies,
                        onFocus: { focusedItem in
                            handleFocusedItem(focusedItem)
                        },
                        onMoveUp: topRowItemIDs.contains(item.id) ? focusPreferredControlBar : nil,
                        onSelect: { selectedItem in
                            let detailItemID = selectedItem.mediaType == .episode ? (selectedItem.parentID ?? selectedItem.id) : selectedItem.id
                            Task {
                                await DetailPresentationTelemetry.shared.beginNavigation(for: detailItemID)
                            }
                            viewModel.select(item: selectedItem)
                        }
                    )
                    .onAppear {
                        handleVisibleItem(item)
                    }
#else
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
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
                                layoutStyle: .grid
                            )
                        }
                        .accessibilityIdentifier("media_card_button_\(item.id)")
                        .buttonStyle(.plain)

                        PosterCardMetadataView(
                            item: item,
                            layoutStyle: .grid
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
        VStack(spacing: 8) {
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
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.white.opacity(0.98))
                        .background {
                            libraryCircleBackground()
                        }
                }
            }

            HStack(spacing: 8) {
                filterChip(title: "Movies", filter: .movie)
                filterChip(title: "Shows", filter: .series)
                Spacer()
            }

            TextField(
                "",
                text: $viewModel.searchQuery,
                prompt: Text("Search your library")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            )
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled(true)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .padding(.horizontal, 14)
                .frame(height: 46)
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
                .frame(minWidth: 74)
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
        horizontalSizeClass == .compact ? 6 : 10
    }

    private var columns: [GridItem] {
#if os(tvOS)
        let cardWidth = PosterCardMetrics.posterWidth(for: .grid, compact: false)
        return [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth + 22), spacing: 24)]
#else
        let cardWidth = PosterCardMetrics.posterWidth(for: .grid, compact: horizontalSizeClass == .compact)
        if horizontalSizeClass == .compact {
            return [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth + 24), spacing: 10)]
        }
        return [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth + 22), spacing: 12)]
#endif
    }

    private var gridSpacing: CGFloat {
#if os(tvOS)
        return 28
#else
        return 12
#endif
    }

    private var horizontalPadding: CGFloat {
#if os(tvOS)
        return 44
#else
        return horizontalSizeClass == .compact ? 10 : 18
#endif
    }

    private var chipFontSize: CGFloat {
#if os(tvOS)
        return 18
#else
        return 14
#endif
    }

    private var chipHPad: CGFloat {
#if os(tvOS)
        return 20
#else
        return 12
#endif
    }

    private var chipVPad: CGFloat {
#if os(tvOS)
        return 12
#else
        return 7
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
                        await dependencies.playbackWarmupManager.warm(itemID: item.id)
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
            await dependencies.playbackWarmupManager.warm(itemID: item.id)
        }
    }

    private func handleVisibleItem(_ item: MediaItem) {
        guard viewModel.paginationTriggerItemID == item.id else { return }
        Task {
            await viewModel.loadMoreIfNeeded()
        }
    }

#if os(tvOS)
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

    private func applyContentFocusRequestIfNeeded() {
        guard let contentFocusRequest else { return }
        guard contentFocusRequest.destination == .library else { return }
        guard contentFocusRequest.sequence != lastHandledContentFocusSequence else { return }

        lastHandledContentFocusSequence = contentFocusRequest.sequence
        focusPreferredControlBar()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            notifyContentFocusReady?(.library, contentFocusRequest.sequence)
        }
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
