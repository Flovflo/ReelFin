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
    @FocusState private var focusedControl: TVLibraryControlFocus?
#endif
    @StateObject private var viewModel: LibraryViewModel
    private let dependencies: ReelFinDependencies
    @State private var warmupTask: Task<Void, Never>?
#if os(tvOS)
    @State private var allowsControlBarTopNavigation = true
    @State private var controlBarNavigationUnlockTask: Task<Void, Never>?
#endif

    init(dependencies: ReelFinDependencies) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(dependencies: dependencies))
        self.dependencies = dependencies
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
        VStack(spacing: 14) {
            topBar

            ScrollView(showsIndicators: false) {
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
                .padding(.top, 52)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 24)

                if viewModel.isLoadingPage {
                    ProgressView()
                        .tint(.white)
                        .padding(.bottom, 16)
                }
            }
#if os(tvOS)
            .focusSection()
#endif
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

                glassGroup(spacing: 10) {
                    Menu {
                        Picker("Sort", selection: $viewModel.sortMode) {
                            ForEach(LibraryViewModel.SortMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(10)
                            .foregroundStyle(.white.opacity(0.96))
                            .background {
                                Color.clear.reelFinGlassCircle(
                                    interactive: true,
                                    tint: Color.white.opacity(0.10),
                                    stroke: Color.white.opacity(0.12),
                                    shadowOpacity: 0.10,
                                    shadowRadius: 10,
                                    shadowYOffset: 4
                                )
                            }
                    }
                }
            }

            glassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    filterChip(title: "All", isActive: viewModel.selectedFilter == nil) {
                        viewModel.selectedFilter = nil
                    }
                    filterChip(title: "Movies", isActive: viewModel.selectedFilter == .movie) {
                        viewModel.selectedFilter = .movie
                    }
                    filterChip(title: "Shows", isActive: viewModel.selectedFilter == .series) {
                        viewModel.selectedFilter = .series
                    }
                    Spacer()
                }
            }

            TextField("Search your library", text: $viewModel.searchQuery)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled(true)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .foregroundStyle(.white)
                .reelFinGlassRoundedRect(
                    cornerRadius: 12,
                    interactive: true,
                    tint: Color.white.opacity(0.08),
                    stroke: Color.white.opacity(0.10),
                    shadowOpacity: 0.10,
                    shadowRadius: 10,
                    shadowYOffset: 4
                )
        }
        .padding(.horizontal, horizontalPadding)
    }

    private func filterChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: chipFontSize, weight: .semibold, design: .rounded))
                .padding(.horizontal, chipHPad)
                .padding(.vertical, chipVPad)
                .foregroundStyle(isActive ? Color.black.opacity(0.92) : Color.white.opacity(0.94))
                .background {
                    Color.clear.reelFinGlassCapsule(
                        interactive: true,
                        tint: isActive ? Color.white.opacity(0.24) : Color.white.opacity(0.08),
                        stroke: Color.white.opacity(isActive ? 0.18 : 0.10),
                        shadowOpacity: isActive ? 0.14 : 0.08,
                        shadowRadius: isActive ? 14 : 8,
                        shadowYOffset: isActive ? 6 : 4
                    )
                }
        }
        .buttonStyle(.plain)
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

    private var columns: [GridItem] {
#if os(tvOS)
        return [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 32)]
#else
        if horizontalSizeClass == .compact {
            return [GridItem(.adaptive(minimum: 152, maximum: 190), spacing: 12)]
        }
        return [GridItem(.adaptive(minimum: 186, maximum: 230), spacing: 16)]
#endif
    }

    private var gridSpacing: CGFloat {
#if os(tvOS)
        return 40
#else
        return 16
#endif
    }

    private var horizontalPadding: CGFloat {
#if os(tvOS)
        return 56
#else
        return horizontalSizeClass == .compact ? 12 : 22
#endif
    }

    private var chipFontSize: CGFloat {
#if os(tvOS)
        return 18
#else
        return 13
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
        return 8
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
    private func setTVFilter(_ filter: MediaType?) {
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
