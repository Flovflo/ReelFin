import JellyfinAPI
import PlaybackEngine
@testable import ReelFinUI
import Shared
import XCTest

@MainActor
final class DetailViewModelActionTests: XCTestCase {
    func testToggleWatchedMarksMovieAsPlayedAndCallsAPI() async {
        let apiClient = DetailActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let item = MediaItem(
            id: "movie-1",
            name: "Movie",
            mediaType: .movie,
            runtimeTicks: Int64(100 * 60 * 10_000_000),
            libraryID: "movies",
            isPlayed: false,
            playbackPositionTicks: Int64(25 * 60 * 10_000_000)
        )

        let viewModel = DetailViewModel(
            item: item,
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        viewModel.toggleWatched()

        XCTAssertTrue(viewModel.isWatched)
        XCTAssertTrue(viewModel.detail.item.isPlayed)
        let didRecordPlayedCall = await waitForPlayedCallCount(1, in: apiClient, timeout: 2)
        XCTAssertTrue(didRecordPlayedCall)

        let playedCalls = await apiClient.playedCalls()
        XCTAssertEqual(playedCalls.first?.itemID, "movie-1")
        XCTAssertEqual(playedCalls.first?.isPlayed, true)
    }

    func testToggleWatchlistMarksMovieAsLikedAndCallsAPI() async {
        let apiClient = DetailActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let item = MediaItem(
            id: "movie-2",
            name: "Movie",
            mediaType: .movie,
            libraryID: "movies",
            isFavorite: false
        )

        let viewModel = DetailViewModel(
            item: item,
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        viewModel.toggleWatchlist()

        XCTAssertTrue(viewModel.isInWatchlist)
        XCTAssertTrue(viewModel.detail.item.isFavorite)
        let didRecordFavoriteCall = await waitForFavoriteCallCount(1, in: apiClient, timeout: 2)
        XCTAssertTrue(didRecordFavoriteCall)

        let favoriteCalls = await apiClient.favoriteCalls()
        XCTAssertEqual(favoriteCalls.first?.itemID, "movie-2")
        XCTAssertEqual(favoriteCalls.first?.isFavorite, true)
    }

    private func makeDependencies(
        apiClient: DetailActionSpyAPIClient,
        repository: MockMetadataRepository
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
            syncEngine: MockSyncEngine(),
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

    private func waitForPlayedCallCount(
        _ expectedCount: Int,
        in apiClient: DetailActionSpyAPIClient,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await apiClient.playedCalls().count == expectedCount {
                return true
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return await apiClient.playedCalls().count == expectedCount
    }

    private func waitForFavoriteCallCount(
        _ expectedCount: Int,
        in apiClient: DetailActionSpyAPIClient,
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

private actor DetailActionSpyAPIClient: JellyfinAPIClientProtocol {
    private var recordedPlayedCalls: [(itemID: String, isPlayed: Bool)] = []
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
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed { _ = since; return .empty }
    func fetchItem(id: String) async throws -> MediaItem { MediaItem(id: id, name: id) }
    func fetchItemDetail(id: String) async throws -> MediaDetail { MediaDetail(item: MediaItem(id: id, name: id)) }
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { _ = seriesID; return [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { _ = seriesID; _ = seasonID; return [] }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? { _ = seriesID; return nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { _ = query; return [] }
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] { _ = itemID; return [] }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? {
        _ = itemID
        _ = type
        _ = width
        _ = quality
        return nil
    }
    func reportPlayback(progress: PlaybackProgressUpdate) async throws { _ = progress }
    func reportPlayed(itemID: String) async throws { _ = itemID }
    func setPlayedState(itemID: String, isPlayed: Bool) async throws {
        recordedPlayedCalls.append((itemID, isPlayed))
    }

    func setFavorite(itemID: String, isFavorite: Bool) async throws {
        recordedFavoriteCalls.append((itemID, isFavorite))
    }

    func playedCalls() -> [(itemID: String, isPlayed: Bool)] {
        recordedPlayedCalls
    }

    func favoriteCalls() -> [(itemID: String, isFavorite: Bool)] {
        recordedFavoriteCalls
    }
}
