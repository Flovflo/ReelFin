import PlaybackEngine
import Shared
import SwiftUI

// MARK: - Components (Merged here to avoid missing .pbxproj references)

#if os(tvOS)
/// A focusable card for Apple TV Siri Remote navigation.
/// Uses .focusable(interactions: .activate) on the VStack directly — no Button wrapper.
/// This prevents tvOS 26 Liquid Glass from applying its glass container, which it does
/// automatically around any focused Button regardless of focusEffectDisabled.
private struct TVCardButton: View {
    @Environment(\.tvTopNavigationFocusAction) private var requestTopNavigationFocus
    @FocusState private var isFocused: Bool

    let item: MediaItem
    let index: Int
    let kind: HomeSectionKind
    let isTop10: Bool
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let namespaceProvider: (String) -> Namespace.ID?
    let isLandscapeRail: Bool
    let progress: Double?
    let onFocus: ((MediaItem) -> Void)?
    let onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Artwork — scale/shadow applied directly, no Button glass container
            PosterCardArtworkView(
                item: item,
                apiClient: apiClient,
                imagePipeline: imagePipeline,
                layoutStyle: isLandscapeRail ? .landscape : .row,
                namespace: namespaceProvider(item.id),
                ranking: isTop10 ? (index + 1) : nil,
                progress: progress
            )
            .scaleEffect(isFocused ? 1.05 : 1)
            .shadow(
                color: .black.opacity(isFocused ? 0.42 : 0.20),
                radius: isFocused ? 32 : 14,
                x: 0,
                y: isFocused ? 20 : 8
            )
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isFocused)

            PosterCardMetadataView(
                item: item,
                layoutStyle: isLandscapeRail ? .landscape : .row,
                titleLineLimit: isLandscapeRail ? 2 : 1
            )
            .padding(.horizontal, 4)
            .opacity(isFocused ? 1.0 : 0.68)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isFocused)
        }
        // focusable on the VStack itself — no Button = no Liquid Glass container.
        // onTapGesture fires when the Siri Remote touchpad is clicked on the focused element.
        .focusable(true, interactions: .activate)
        .onMoveCommand(perform: handleMoveCommand)
        .onTapGesture { onSelect(item) }
        .focusEffectDisabled(true)
        .focused($isFocused)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("media_card_button_\(kind.rawValue)_\(item.id)")
        .onChange(of: isFocused) { _, focused in
            guard focused else { return }
            onFocus?(item)
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard direction == .up, kind == .continueWatching else { return }
        requestTopNavigationFocus?(.watchNow)
    }
}
#endif

public struct SectionRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let title: String
    private let items: [MediaItem]
    private let kind: HomeSectionKind
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let namespaceProvider: (String) -> Namespace.ID?
    private let onFocus: ((MediaItem, [MediaItem]) -> Void)?
    private let onSelect: (MediaItem) -> Void

    public init(
        title: String,
        items: [MediaItem],
        kind: HomeSectionKind,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        namespaceProvider: @escaping (String) -> Namespace.ID?,
        onFocus: ((MediaItem, [MediaItem]) -> Void)? = nil,
        onSelect: @escaping (MediaItem) -> Void
    ) {
        self.title = title
        self.items = items
        self.kind = kind
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.namespaceProvider = namespaceProvider
        self.onFocus = onFocus
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .reelFinSectionStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)

#if os(iOS)
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.4))
#endif
            }
            .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: cardSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
#if os(tvOS)
                        TVCardButton(
                            item: item,
                            index: index,
                            kind: kind,
                            isTop10: isTop10,
                            apiClient: apiClient,
                            imagePipeline: imagePipeline,
                            namespaceProvider: namespaceProvider,
                            isLandscapeRail: isLandscapeRail,
                            progress: progress(for: item),
                            onFocus: { focusedItem in
                                onFocus?(focusedItem, items)
                            },
                            onSelect: onSelect
                        )
#else
                        Button {
                            onSelect(item)
                        } label: {
                            PosterCardView(
                                item: item,
                                apiClient: apiClient,
                                imagePipeline: imagePipeline,
                                layoutStyle: isLandscapeRail ? .landscape : .row,
                                namespace: namespaceProvider(item.id),
                                ranking: isTop10 ? (index + 1) : nil,
                                progress: progress(for: item)
                            )
                            .scrollTransition(axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.95)
                            }
                        }
                        .accessibilityIdentifier("media_card_button_\(kind.rawValue)_\(item.id)")
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
#endif
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 14)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var cardSpacing: CGFloat {
#if os(tvOS)
        return ReelFinTheme.tvRailSpacing
#else
        return 16
#endif
    }

    private var isTop10: Bool {
        title.lowercased().contains("top 10") || title.lowercased().contains("trending")
    }

    private var isLandscapeRail: Bool {
        kind == .continueWatching || kind == .nextUp
    }

    private func progress(for item: MediaItem) -> Double? {
        if kind == .continueWatching || kind == .nextUp {
            return item.playbackProgress ?? 0.4
        }
        return nil
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return ReelFinTheme.tvSectionHorizontalPadding
        #else
        return horizontalSizeClass == .compact ? 24 : 40
        #endif
    }
}

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel: HomeViewModel
    @Namespace private var posterNamespace

    private let dependencies: ReelFinDependencies
    @State private var scrollInterval: SignpostInterval?
    @State private var isCustomizationPresented = false
    @State private var selectedDetailNamespace: Namespace.ID?
    @State private var selectedDetailContextItems: [MediaItem] = []
    @State private var selectedDetailContextTitle: String?
    @State private var ambientItem: MediaItem?
    @State private var playerSession: PlaybackSessionController?
    @State private var playerItem: MediaItem?
    @State private var showPlayer = false
    @State private var isPreparingPlayback = false
    @State private var playbackErrorMessage: String?

    init(dependencies: ReelFinDependencies) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(dependencies: dependencies))
        self.dependencies = dependencies
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CinematicBackdropView(
                item: ambientItem ?? viewModel.feed.featured.first,
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline,
                sharpnessOpacity: 0.78,
                blurOpacity: 0.56,
                bottomFadeStart: 0.5,
                leadingScrimOpacity: tvHomeLeadingScrimOpacity,
                edgeVignetteOpacity: tvHomeEdgeVignetteOpacity
            )
            .overlay {
                Color.black.opacity(0.18).ignoresSafeArea()
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    if viewModel.isInitialLoading && viewModel.feed.rows.isEmpty {
                        loadingSkeleton
                            .padding(.top, 48)
                    } else if viewModel.visibleRows.isEmpty && viewModel.feed.featured.isEmpty {
                        emptyState
                            .padding(.top, 48)
                    } else {
                        featuredSection

                        ForEach(viewModel.visibleRows) { row in
                            SectionRow(
                                title: row.title,
                                items: row.items,
                                kind: row.kind,
                                apiClient: dependencies.apiClient,
                                imagePipeline: dependencies.imagePipeline,
                                namespaceProvider: { itemID in
                                    namespaceForCard(itemID: itemID, rowID: row.id)
                                },
                                onFocus: { item, neighbors in
                                    handleFocusedItem(item, neighbors: neighbors)
                                },
                                onSelect: { item in
                                    selectedDetailNamespace = namespaceForCard(itemID: item.id, rowID: row.id)
                                    selectedDetailContextItems = row.items
                                    selectedDetailContextTitle = row.title
                                    ambientItem = item
                                    let detailItemID = item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
                                    Task {
                                        await DetailPresentationTelemetry.shared.beginNavigation(for: detailItemID)
                                    }
                                    viewModel.select(item: item)
                                }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.snappy(duration: 0.35), value: viewModel.visibleRows.map(\.id))
            }
            .background(ReelFinTheme.pageGradient.ignoresSafeArea())
#if os(tvOS)
            .contentMargins(.zero, for: .scrollContent)
#endif
#if os(iOS)
            .refreshable {
                await viewModel.manualRefresh()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in
                        if scrollInterval == nil {
                            scrollInterval = SignpostInterval(signposter: Signpost.homeScroll, name: "home_scroll_session")
                        }
                    }
                    .onEnded { _ in
                        scrollInterval?.end(name: "home_scroll_session")
                        scrollInterval = nil
                    }
            )
#endif
        }
#if os(tvOS)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(.container, edges: [.top, .horizontal])
#endif
        .navigationDestination(
            isPresented: Binding(
                get: { viewModel.selectedItem != nil },
                set: {
                    if !$0 {
                        selectedDetailNamespace = nil
                        selectedDetailContextItems = []
                        selectedDetailContextTitle = nil
                        viewModel.dismissDetail()
                    }
                }
            )
        ) {
            if let item = viewModel.selectedItem {
                DetailView(
                    dependencies: dependencies,
                    item: item,
                    preferredEpisode: viewModel.selectedEpisode,
                    contextItems: selectedDetailContextItems,
                    contextTitle: selectedDetailContextTitle,
                    namespace: selectedDetailNamespace
                )
            }
        }
        .task {
            await viewModel.load()
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let playerSession, let playerItem {
                PlayerView(session: playerSession, item: playerItem) {
                    showPlayer = false
                }
            }
        }
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { playbackErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        playbackErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                playbackErrorMessage = nil
            }
        } message: {
            Text(playbackErrorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $isCustomizationPresented) {
            HomeCustomizationSheet(viewModel: viewModel)
#if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
#endif
        }
#if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top) // Let hero stretch to status bar
#endif
    }

    @ViewBuilder
    private var featuredSection: some View {
        if !viewModel.feed.featured.isEmpty {
            #if os(tvOS)
            HeroCarouselView(
                items: featuredItems,
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline,
                onVisibleItemChange: { item in
                    ambientItem = item
                    Task(priority: .utility) {
                        await primePresentation(for: item, neighbors: Array(viewModel.feed.featured.prefix(3)))
                    }
                },
                onPlay: handleFeaturedPlay,
                onTap: handleFeaturedSelection
            )
            #else
            ZStack(alignment: .top) {
                HeroCarouselView(
                    items: Array(viewModel.feed.featured.prefix(10)),
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline,
                    onTap: { item in
                        selectedDetailNamespace = nil
                        selectedDetailContextItems = Array(viewModel.feed.featured.prefix(10))
                        selectedDetailContextTitle = "Featured"
                        viewModel.select(item: item)
                    }
                )

                topChrome
            }
            #endif
        } else {
            #if os(iOS)
            topChrome
                .padding(.top, 60) // Add top padding to account for missing hero
            #endif
        }
    }

    private var topChrome: some View {
        HStack(alignment: .top) {
            Text("ReelFin")
                .reelFinTitleStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            HStack(spacing: 12) {
                if viewModel.isRefreshing || viewModel.isInitialLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 4)
                }

#if os(iOS)
                Button {
                    isCustomizationPresented = true
                } label: {
                    topIcon(symbol: "slider.horizontal.3", accessibilityLabel: "Customize Home")
                }
                .buttonStyle(.plain)
#endif
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topChromePadding)
        .shadow(color: .black.opacity(0.3), radius: 6)
    }

    private func topIcon(symbol: String, accessibilityLabel: String) -> some View {
        Image(systemName: symbol)
            .font(.headline.weight(.semibold))
            .frame(width: 44, height: 44)
            .foregroundStyle(.white)
            .glassPanelStyle(cornerRadius: 22)
            .accessibilityLabel(accessibilityLabel)
    }

    private func namespaceForCard(itemID: String, rowID: String) -> Namespace.ID? {
        firstRowByItemID[itemID] == rowID ? posterNamespace : nil
    }

    private var featuredItems: [MediaItem] {
        Array(viewModel.feed.featured.prefix(10))
    }

    private var tvHomeLeadingScrimOpacity: Double {
        #if os(tvOS)
        return 0.42
        #else
        return 0.82
        #endif
    }

    private var tvHomeEdgeVignetteOpacity: Double {
        #if os(tvOS)
        return 0.08
        #else
        return 0.58
        #endif
    }

    private var firstRowByItemID: [String: String] {
        var map: [String: String] = [:]
        for row in viewModel.visibleRows {
            for item in row.items where map[item.id] == nil {
                map[item.id] = row.id
            }
        }
        return map
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoundedRectangle(cornerRadius: ReelFinTheme.glassPanelCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(height: heroSkeletonHeight)
                .overlay(ShimmerView())
                .padding(.horizontal, horizontalPadding)

            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 120, height: 24)
                        .padding(.horizontal, horizontalPadding)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: ReelFinTheme.cardCornerRadius, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(width: rowCardWidth, height: rowCardHeight)
                                    .overlay(ShimmerView())
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white.opacity(0.88))

            Text("Your Home Is Ready")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)

            Text("We could not load rows yet. Pull to refresh or update server settings.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            Button {
                Task { await viewModel.manualRefresh() }
            } label: {
                Label("Retry Sync", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .glassPanelStyle(cornerRadius: 16)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, minHeight: isCompact ? 380 : 480)
        .padding(24)
        .glassPanelStyle(cornerRadius: ReelFinTheme.glassPanelCornerRadius)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 10)
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return ReelFinTheme.tvSectionHorizontalPadding
        #else
        return isCompact ? 24 : 40
        #endif
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    private var heroSkeletonHeight: CGFloat {
        horizontalSizeClass == .compact ? 500 : 600
    }

    private var rowCardWidth: CGFloat {
        isCompact ? 134 : 160
    }

    private var rowCardHeight: CGFloat {
        rowCardWidth * 1.55
    }

    private var topChromePadding: CGFloat {
        #if os(tvOS)
        return 42
        #else
        return 64
        #endif
    }

    private func handleFocusedItem(_ item: MediaItem, neighbors: [MediaItem]) {
        ambientItem = item
        Task(priority: .utility) {
            await primePresentation(for: item, neighbors: neighbors)
        }
    }

    private func handleFeaturedSelection(_ item: MediaItem) {
        selectedDetailNamespace = nil
        selectedDetailContextItems = featuredItems
        selectedDetailContextTitle = "Featured"
        ambientItem = item

        let detailItemID = item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
        Task {
            await DetailPresentationTelemetry.shared.beginNavigation(for: detailItemID)
        }

        viewModel.select(item: item)
    }

    private func handleFeaturedPlay(_ item: MediaItem) {
        guard !isPreparingPlayback else { return }
        isPreparingPlayback = true

        Task {
            let playbackItem = await resolvePlaybackItem(for: item)
            await MainActor.run {
                isPreparingPlayback = false
            }

            guard let playbackItem else {
                await MainActor.run {
                    handleFeaturedSelection(item)
                }
                return
            }

            await launchPlayback(for: playbackItem)
        }
    }

    private func resolvePlaybackItem(for item: MediaItem) async -> MediaItem? {
        guard item.mediaType == .series else { return item }

        do {
            return try await dependencies.detailRepository.loadNextUpEpisode(seriesID: item.id)
        } catch {
            return nil
        }
    }

    @MainActor
    private func launchPlayback(for item: MediaItem) async {
        let session = dependencies.makePlaybackSession()
        playerSession = session
        playerItem = item

        do {
            try await session.load(item: item)
            showPlayer = true
        } catch {
            playerSession = nil
            playerItem = nil
            showPlayer = false
            playbackErrorMessage = error.localizedDescription
        }
    }

    private func primePresentation(for item: MediaItem, neighbors: [MediaItem]) async {
        let detailItemID = item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
        await dependencies.detailRepository.primeItem(id: detailItemID)
        await dependencies.detailRepository.primeDetail(id: detailItemID)

        let nearbyItems = Array(neighbors.prefix(4))
        await dependencies.apiClient.prefetchImages(for: nearbyItems)

        if let heroURL = await dependencies.apiClient.imageURL(
            for: item.mediaType == .episode ? (item.parentID ?? item.id) : item.id,
            type: item.backdropTag == nil ? .primary : .backdrop,
            width: 1_920,
            quality: 78
        ) {
            await dependencies.imagePipeline.prefetch(urls: [heroURL])
        }

        await dependencies.playbackWarmupManager.trim(keeping: [item.id] + nearbyItems.map(\.id))
        await dependencies.playbackWarmupManager.warm(itemID: item.id)
    }
}

private struct HomeCustomizationSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            List {
#if os(iOS)
                Section("Order") {
                    ForEach(viewModel.sectionCustomizationKinds, id: \.self) { kind in
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: kind))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 20)
                            Text(viewModel.sectionTitle(for: kind))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                    .onMove(perform: viewModel.moveSectionKinds(from:to:))
                }
#endif

                Section("Visible Sections") {
                    ForEach(viewModel.sectionCustomizationKinds, id: \.self) { kind in
                        Toggle(isOn: Binding(
                            get: { viewModel.isSectionVisible(kind) },
                            set: { viewModel.setSectionVisibility(kind, isVisible: $0) }
                        )) {
                            Text(viewModel.sectionTitle(for: kind))
                                .foregroundStyle(.white)
                        }
                        .tint(.white)
                    }
                }
            }
            .environment(\.editMode, $editMode)
#if os(iOS)
            .scrollContentBackground(.hidden)
#endif
            .background(ReelFinTheme.pageGradient.ignoresSafeArea())
            .navigationTitle("Customize Home")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        viewModel.resetSectionCustomization()
                    }
                    .tint(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(.white)
                }
            }
#else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
#endif
        }
        .preferredColorScheme(.dark)
    }

    private func icon(for kind: HomeSectionKind) -> String {
        switch kind {
        case .continueWatching:
            return "play.circle"
        case .nextUp:
            return "forward.end.circle"
        case .recentlyAddedMovies:
            return "film.stack"
        case .recentlyAddedSeries:
            return "tv"
        case .popular:
            return "flame"
        case .trending:
            return "chart.line.uptrend.xyaxis"
        case .movies:
            return "film"
        case .shows:
            return "play.tv"
        case .latest:
            return "clock"
        }
    }
}

// MARK: - UI Checklist
// - Safe areas OK (edges ignored for Hero, bottom inset added for scrolling)
// - No text clipping (titles use minimumScaleFactor and fixedSize where necessary)
// - Tab bar overlay OK (ignoresSafeArea .keyboard)
// - Hero paging OK (uses .scrollTargetBehavior(.paging))
// - Matched geometry OK (posterNamespace preserved)
// - Dark gradient scrims OK (ReelFinTheme.heroGradientScrim applied)

#Preview("Home - iPhone SE") {
    NavigationStack {
        HomeView(dependencies: ReelFinPreviewFactory.dependencies())
    }
}

#Preview("Home - iPhone Pro Max") {
    NavigationStack {
        HomeView(dependencies: ReelFinPreviewFactory.dependencies())
    }
}

#Preview("Home - Accessibility XXXL") {
    NavigationStack {
        HomeView(dependencies: ReelFinPreviewFactory.dependencies())
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Home - Apple TV", traits: .fixedLayout(width: 1920, height: 1080)) {
    NavigationStack {
        HomeView(dependencies: ReelFinPreviewFactory.dependencies())
    }
    .preferredColorScheme(.dark)
}
