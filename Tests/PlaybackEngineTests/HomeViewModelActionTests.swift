import JellyfinAPI
import PlaybackEngine
@testable import ReelFinUI
import Shared
import XCTest

@MainActor
final class HomeViewModelActionTests: XCTestCase {
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
    private var recordedFavoriteCalls: [(itemID: String, isFavorite: Bool)] = []

    func currentConfiguration() async -> ServerConfiguration? { nil }
    func currentSession() async -> UserSession? { nil }
    func configure(server: ServerConfiguration) async throws { _ = server }
    func testConnection(serverURL: URL) async throws { _ = serverURL }
    func authenticate(credentials: UserCredentials) async throws -> UserSession { _ = credentials; throw AppError.unknown }
    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { nil }
    func fetchUserViews() async throws -> [Shared.LibraryView] { [] }
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed {
        _ = since
        return .empty
    }
    func fetchItem(id: String) async throws -> MediaItem { MediaItem(id: id, name: id) }
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
        _ = query
        return []
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
}
