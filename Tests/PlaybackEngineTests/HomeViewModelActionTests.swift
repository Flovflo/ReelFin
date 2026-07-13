import JellyfinAPI
import PlaybackEngine
@testable import ReelFinUI
import Shared
import XCTest

@MainActor
final class HomeViewModelActionTests: XCTestCase {
    func testFeaturedPlayUsesCustomRouteWhenCustomEngineIsEnabled() {
        XCTAssertEqual(
            HomePlaybackRoute.preferred(useCustomPlayerEngine: true),
            .custom
        )
    }

    func testFeaturedPlayKeepsExplicitLegacyOptOut() {
        XCTAssertEqual(
            HomePlaybackRoute.preferred(useCustomPlayerEngine: false),
            .legacy
        )
    }

    func testTopNavigationIsHiddenWhileHomePlayerIsPresented() {
        XCTAssertFalse(HomePlayerPresentationPolicy.showsTopNavigation(hasActivePlayer: true))
        XCTAssertTrue(HomePlayerPresentationPolicy.showsTopNavigation(hasActivePlayer: false))
    }

    func testToggleFeaturedWatchlistUpdatesFeedAndCallsFavoriteEndpoint() async throws {
        let apiClient = HomeActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let heroItem = MediaItem(id: "hero-1", name: "Hero Item", mediaType: .movie, libraryID: "movies")
        try await repository.saveHomeFeed(
            HomeFeed(
                featured: [heroItem],
                rows: [HomeRow(kind: .recentlyAddedMovies, title: "Recently Added Movies", items: [heroItem])]
            )
        )

        let viewModel = HomeViewModel(dependencies: makeDependencies(apiClient: apiClient, repository: repository))
        await viewModel.load()
        viewModel.toggleFeaturedWatchlist(for: heroItem)

        XCTAssertTrue(viewModel.feed.featured[0].isFavorite)
        XCTAssertTrue(viewModel.visibleRows[0].items[0].isFavorite)
        let didRecordFavoriteCall = await waitForFavoriteCallCount(1, in: apiClient, timeout: 2)
        XCTAssertTrue(didRecordFavoriteCall)

        let favoriteCalls = await apiClient.favoriteCalls()
        XCTAssertEqual(favoriteCalls.count, 1)
        XCTAssertEqual(favoriteCalls.first?.itemID, "hero-1")
        XCTAssertEqual(favoriteCalls.first?.isFavorite, true)
    }

    func testManualRefreshRunsManualSyncAndReloadsCache() async throws {
        let apiClient = HomeActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let refreshedItem = MediaItem(id: "fresh-1", name: "Fresh Item", mediaType: .movie, libraryID: "movies")
        let refreshedFeed = HomeFeed(
            featured: [refreshedItem],
            rows: [HomeRow(kind: .recentlyAddedMovies, title: "Recently Added Movies", items: [refreshedItem])]
        )
        let syncEngine = HomeRecordingSyncEngine(repository: repository, feedAfterSync: refreshedFeed)

        let viewModel = HomeViewModel(
            dependencies: makeDependencies(
                apiClient: apiClient,
                repository: repository,
                syncEngine: syncEngine
            )
        )
        await viewModel.manualRefresh()

        let reasons = await syncEngine.recordedReasons()
        XCTAssertEqual(reasons, [.manualRefresh])
        XCTAssertEqual(viewModel.feed.featured.first?.id, "fresh-1")
        XCTAssertEqual(viewModel.visibleRows.first?.items.first?.id, "fresh-1")
    }

    func testManualRefreshSkipsWhenRefreshAlreadyRunning() async {
        let apiClient = HomeActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let syncEngine = HomeRecordingSyncEngine(repository: repository, feedAfterSync: .empty)
        let viewModel = HomeViewModel(
            dependencies: makeDependencies(
                apiClient: apiClient,
                repository: repository,
                syncEngine: syncEngine
            )
        )
        viewModel.isRefreshing = true

        await viewModel.manualRefresh()

        let reasons = await syncEngine.recordedReasons()
        XCTAssertEqual(reasons, [])
        XCTAssertTrue(viewModel.isRefreshing)
    }

    func testStaleFeedEnrichmentPreservesLoadedNextPageAndCurrentItemState() async throws {
        let initialItems = (0..<20).map { index in
            MediaItem(
                id: "movie-\(index)",
                name: "Movie \(index)",
                mediaType: .movie,
                libraryID: "movies"
            )
        }
        let remoteItems = (20..<23).map { index in
            MediaItem(
                id: "movie-\(index)",
                name: "Movie \(index)",
                mediaType: .movie,
                libraryID: "movies"
            )
        }
        let series = MediaItem(
            id: "series-enriched",
            name: "Enriched Series",
            mediaType: .series,
            posterTag: "series-poster"
        )
        let episode = MediaItem(
            id: "episode-current",
            name: "Current Episode",
            mediaType: .episode,
            parentID: series.id
        )
        let enrichmentStarted = expectation(description: "stale feed enrichment started")
        let apiClient = HomeActionSpyAPIClient(
            userViews: [Shared.LibraryView(id: "movies", name: "Movies", collectionType: "movies")],
            libraryItems: remoteItems,
            blockedSeriesItem: series,
            seriesFetchStartedExpectation: enrichmentStarted
        )
        let repository = MockMetadataRepository()
        try await repository.saveHomeFeed(
            HomeFeed(
                featured: [episode],
                rows: [
                    HomeRow(
                        kind: .recentlyReleasedMovies,
                        title: "Recently Released Movies",
                        items: initialItems
                    ),
                    HomeRow(
                        kind: .continueWatching,
                        title: "Continue Watching",
                        items: [episode]
                    )
                ]
            )
        )

        let viewModel = HomeViewModel(dependencies: makeDependencies(apiClient: apiClient, repository: repository))
        await viewModel.load()
        await fulfillment(of: [enrichmentStarted], timeout: 1)

        let row = try XCTUnwrap(viewModel.visibleRows.first(where: { $0.kind == .recentlyReleasedMovies }))
        let triggerItemID = try XCTUnwrap(TVLibraryPaginationPolicy.triggerItemID(in: row.items, trailingWindow: 6))

        await viewModel.loadMoreIfNeeded(rowID: row.id, visibleItemID: triggerItemID)
        viewModel.toggleFeaturedWatchlist(for: episode)
        await apiClient.releaseBlockedSeriesFetch()

        let enrichmentApplied = await waitUntil(timeout: .seconds(1)) {
            viewModel.feed.rows
                .flatMap(\.items)
                .first(where: { $0.id == episode.id })?
                .seriesName == series.name
        }
        XCTAssertTrue(enrichmentApplied)

        let loadedIDs = viewModel.visibleRows
            .first(where: { $0.kind == .recentlyReleasedMovies })?
            .items.map(\.id) ?? []
        XCTAssertEqual(loadedIDs.count, 23)
        XCTAssertEqual(Array(loadedIDs.suffix(3)), ["movie-20", "movie-21", "movie-22"])

        let currentEpisode = viewModel.feed.rows
            .flatMap(\.items)
            .first(where: { $0.id == episode.id })
        XCTAssertEqual(currentEpisode?.isFavorite, true)
        XCTAssertEqual(currentEpisode?.seriesName, series.name)
        XCTAssertEqual(currentEpisode?.seriesPosterTag, series.posterTag)
        XCTAssertEqual(viewModel.feed.featured.map(\.id), [episode.id])
        XCTAssertEqual(viewModel.feed.featured.first?.isFavorite, true)
        XCTAssertEqual(viewModel.feed.featured.first?.seriesName, series.name)
        XCTAssertEqual(viewModel.feed.featured.first?.seriesPosterTag, series.posterTag)

        let recordedQueries = await apiClient.recordedLibraryQueries()
        let query = recordedQueries.last
        XCTAssertEqual(query?.page, 1)
        XCTAssertEqual(query?.pageSize, 20)
        XCTAssertEqual(query?.mediaType, .movie)
        XCTAssertEqual(query?.sortBy, .premiereDate)
        XCTAssertEqual(query?.resolvedViewIDs, ["movies"])
    }

    func testContinueWatchingDoesNotPaginateFromHomeRail() async throws {
        let item = MediaItem(id: "resume-1", name: "Resume", mediaType: .movie)
        let apiClient = HomeActionSpyAPIClient(libraryItems: [MediaItem(id: "movie-2", name: "Movie 2")])
        let repository = MockMetadataRepository()
        try await repository.saveHomeFeed(
            HomeFeed(
                featured: [],
                rows: [HomeRow(kind: .continueWatching, title: "Continue Watching", items: [item])]
            )
        )

        let viewModel = HomeViewModel(dependencies: makeDependencies(apiClient: apiClient, repository: repository))
        await viewModel.load()
        await viewModel.loadMoreIfNeeded(rowID: viewModel.visibleRows[0].id, visibleItemID: item.id)

        let recordedQueries = await apiClient.recordedLibraryQueries()
        XCTAssertEqual(recordedQueries, [])
        XCTAssertEqual(viewModel.visibleRows[0].items.map(\.id), ["resume-1"])
    }

    private func makeDependencies(
        apiClient: HomeActionSpyAPIClient,
        repository: MockMetadataRepository,
        syncEngine: any SyncEngineProtocol = MockSyncEngine()
    ) -> ReelFinDependencies {
        let detailRepository = DefaultMediaDetailRepository(
            apiClient: apiClient,
            repository: repository,
            itemTTL: 60,
            detailTTL: 60,
            collectionTTL: 60
        )
        let warmupManager = PlaybackWarmupManager(apiClient: apiClient, ttl: 60)
        let notifications = NoopEpisodeReleaseNotificationManager()

        return ReelFinDependencies(
            apiClient: apiClient,
            repository: repository,
            detailRepository: detailRepository,
            imagePipeline: MockImagePipeline(),
            syncEngine: syncEngine,
            settingsStore: MockSettingsStore(),
            episodeReleaseNotificationManager: notifications,
            seriesCache: SeriesLookupCache(apiClient: apiClient),
            playbackWarmupManager: warmupManager,
            tvFocusWarmupCoordinator: nil,
            makePlaybackSession: {
                PlaybackSessionController(
                    apiClient: apiClient,
                    repository: repository,
                    warmupManager: warmupManager
                )
            }
        )
    }

    private func waitForFavoriteCallCount(
        _ expectedCount: Int,
        in apiClient: HomeActionSpyAPIClient,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await apiClient.favoriteCalls().count == expectedCount {
                return true
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return await apiClient.favoriteCalls().count == expectedCount
    }

    private func waitUntil(
        timeout: Duration,
        condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return true
            }
            await Task.yield()
        }

        return condition()
    }
}

private actor HomeRecordingSyncEngine: SyncEngineProtocol {
    private let repository: MockMetadataRepository
    private let feedAfterSync: HomeFeed
    private var reasons: [SyncReason] = []

    init(repository: MockMetadataRepository, feedAfterSync: HomeFeed) {
        self.repository = repository
        self.feedAfterSync = feedAfterSync
    }

    func sync(reason: SyncReason) async {
        reasons.append(reason)
        try? await repository.saveHomeFeed(feedAfterSync)
    }

    func recordedReasons() -> [SyncReason] {
        reasons
    }
}

private actor HomeActionSpyAPIClient: JellyfinAPIClientProtocol {
    private let userViews: [Shared.LibraryView]
    private let libraryItems: [MediaItem]
    private let blockedSeriesItem: MediaItem?
    private let seriesFetchStartedExpectation: XCTestExpectation?
    private var recordedFavoriteCalls: [(itemID: String, isFavorite: Bool)] = []
    private var recordedQueries: [LibraryQuery] = []
    private var blockedSeriesFetchContinuations: [CheckedContinuation<MediaItem, Never>] = []
    private var isBlockedSeriesFetchReleased = false

    init(
        userViews: [Shared.LibraryView] = [],
        libraryItems: [MediaItem] = [],
        blockedSeriesItem: MediaItem? = nil,
        seriesFetchStartedExpectation: XCTestExpectation? = nil
    ) {
        self.userViews = userViews
        self.libraryItems = libraryItems
        self.blockedSeriesItem = blockedSeriesItem
        self.seriesFetchStartedExpectation = seriesFetchStartedExpectation
    }

    func currentConfiguration() async -> ServerConfiguration? { nil }
    func currentSession() async -> UserSession? { nil }
    func configure(server: ServerConfiguration) async throws { _ = server }
    func testConnection(serverURL: URL) async throws { _ = serverURL }
    func authenticate(credentials: UserCredentials) async throws -> UserSession { _ = credentials; throw AppError.unknown }
    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { nil }
    func fetchUserViews() async throws -> [Shared.LibraryView] { userViews }
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed {
        _ = since
        return .empty
    }
    func fetchItem(id: String) async throws -> MediaItem {
        guard let blockedSeriesItem, blockedSeriesItem.id == id else {
            return MediaItem(id: id, name: id)
        }

        seriesFetchStartedExpectation?.fulfill()
        guard !isBlockedSeriesFetchReleased else { return blockedSeriesItem }

        return await withCheckedContinuation { continuation in
            blockedSeriesFetchContinuations.append(continuation)
        }
    }
    func fetchItemDetail(id: String) async throws -> MediaDetail { MediaDetail(item: MediaItem(id: id, name: id)) }
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] {
        _ = seriesID
        return []
    }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] {
        _ = seriesID
        _ = seasonID
        return []
    }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? {
        _ = seriesID
        return nil
    }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        recordedQueries.append(query)
        return libraryItems
    }
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] {
        _ = itemID
        return []
    }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? {
        _ = itemID
        _ = type
        _ = width
        _ = quality
        return nil
    }
    func reportPlayback(progress: PlaybackProgressUpdate) async throws { _ = progress }
    func reportPlayed(itemID: String) async throws { _ = itemID }
    func setFavorite(itemID: String, isFavorite: Bool) async throws {
        recordedFavoriteCalls.append((itemID, isFavorite))
    }

    func favoriteCalls() -> [(itemID: String, isFavorite: Bool)] {
        recordedFavoriteCalls
    }

    func recordedLibraryQueries() -> [LibraryQuery] {
        recordedQueries
    }

    func releaseBlockedSeriesFetch() {
        guard let blockedSeriesItem else { return }

        isBlockedSeriesFetchReleased = true
        let continuations = blockedSeriesFetchContinuations
        blockedSeriesFetchContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: blockedSeriesItem)
        }
    }
}
