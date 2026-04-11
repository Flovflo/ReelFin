import JellyfinAPI
import PlaybackEngine
@testable import ReelFinUI
import Shared
import XCTest

@MainActor
final class LibraryViewModelTests: XCTestCase {
    func testLoadInitialAggregatesMovieLibrariesDiscoveredFromJellyfinViews() async throws {
        let apiClient = LibraryViewModelAPIClientStub(
            views: [
                LibraryView(id: "movies-a", name: "Movies A", collectionType: "movies"),
                LibraryView(id: "movies-b", name: "Movies B", collectionType: "movies"),
                LibraryView(id: "shows-a", name: "Shows A", collectionType: "tvshows")
            ],
            itemsByViewID: [
                "movies-a": [
                    MediaItem(id: "movie-a-1", name: "Movie A 1", mediaType: .movie, year: 2025, libraryID: "movies-a")
                ],
                "movies-b": [
                    MediaItem(id: "movie-b-1", name: "Movie B 1", mediaType: .movie, year: 2024, libraryID: "movies-b")
                ],
                "shows-a": [
                    MediaItem(id: "series-a-1", name: "Series A 1", mediaType: .series, year: 2026, libraryID: "shows-a")
                ]
            ]
        )
        let repository = LibraryViewModelRepositoryStub()
        let dependencies = makeDependencies(apiClient: apiClient, repository: repository)

        let viewModel = LibraryViewModel(dependencies: dependencies)
        await viewModel.loadInitial()

        XCTAssertEqual(viewModel.items.map(\.id), ["movie-a-1", "movie-b-1"])
        XCTAssertEqual(repository.savedViews.map(\.id), ["movies-a", "movies-b", "shows-a"])
        XCTAssertEqual(await apiClient.recordedQueries().last?.resolvedViewIDs, ["movies-a", "movies-b"])
    }
}

private actor LibraryViewModelAPIClientStub: JellyfinAPIClientProtocol {
    private let views: [LibraryView]
    private let itemsByViewID: [String: [MediaItem]]
    private var queries: [LibraryQuery] = []

    init(views: [LibraryView], itemsByViewID: [String: [MediaItem]]) {
        self.views = views
        self.itemsByViewID = itemsByViewID
    }

    func currentConfiguration() async -> ServerConfiguration? {
        ServerConfiguration(serverURL: URL(string: "https://example.com")!)
    }

    func currentSession() async -> UserSession? {
        UserSession(userID: "user-1", username: "Flo", token: "token-1")
    }

    func configure(server: ServerConfiguration) async throws { _ = server }
    func testConnection(serverURL: URL) async throws { _ = serverURL }
    func authenticate(credentials: UserCredentials) async throws -> UserSession { _ = credentials; throw AppError.unknown }
    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { _ = serverURL; throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { _ = secret; return nil }

    func fetchUserViews() async throws -> [LibraryView] {
        views
    }

    func fetchHomeFeed(since: Date?) async throws -> HomeFeed {
        _ = since
        return .empty
    }

    func fetchNextUpEpisodes(limit: Int) async throws -> [MediaItem] {
        _ = limit
        return []
    }

    func fetchItem(id: String) async throws -> MediaItem {
        MediaItem(id: id, name: id)
    }

    func fetchItemDetail(id: String) async throws -> MediaDetail {
        MediaDetail(item: MediaItem(id: id, name: id))
    }

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
        queries.append(query)
        let viewIDs = query.resolvedViewIDs
        if viewIDs.isEmpty {
            return []
        }

        return viewIDs.flatMap { itemsByViewID[$0] ?? [] }
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

    func prefetchImages(for items: [MediaItem]) async {
        _ = items
    }

    func reportPlayback(progress: PlaybackProgressUpdate) async throws { _ = progress }
    func reportPlaybackStopped(progress: PlaybackProgressUpdate) async throws { _ = progress }
    func reportPlayed(itemID: String) async throws { _ = itemID }
    func setPlayedState(itemID: String, isPlayed: Bool) async throws {
        _ = itemID
        _ = isPlayed
    }
    func setFavorite(itemID: String, isFavorite: Bool) async throws {
        _ = itemID
        _ = isFavorite
    }

    func recordedQueries() -> [LibraryQuery] {
        queries
    }
}

private final class LibraryViewModelRepositoryStub: MetadataRepositoryProtocol, @unchecked Sendable {
    var savedViews: [LibraryView] = []
    private var views: [LibraryView] = []
    private var itemsByID: [String: MediaItem] = [:]

    func saveLibraryViews(_ views: [LibraryView]) async throws {
        self.views = views
        savedViews = views
    }

    func fetchLibraryViews() async throws -> [LibraryView] {
        views
    }

    func saveHomeFeed(_ feed: HomeFeed) async throws { _ = feed }
    func fetchHomeFeed() async throws -> HomeFeed { .empty }

    func upsertItems(_ items: [MediaItem]) async throws {
        for item in items {
            itemsByID[item.id] = item
        }
    }

    func fetchItem(id: String) async throws -> MediaItem? {
        itemsByID[id]
    }

    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        let allowedViewIDs = Set(query.resolvedViewIDs)
        return itemsByID.values
            .filter { item in
                (allowedViewIDs.isEmpty || allowedViewIDs.contains(item.libraryID ?? "")) &&
                    (query.mediaType == nil || item.mediaType == query.mediaType)
            }
            .prefix(query.pageSize)
            .map { $0 }
    }

    func searchItems(query: String, limit: Int) async throws -> [MediaItem] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        return Array(itemsByID.values.prefix(limit))
    }

    func savePlaybackProgress(_ progress: PlaybackProgress) async throws { _ = progress }
    func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? { _ = itemID; return nil }
    func fetchLastSyncDate() async throws -> Date? { nil }
    func setLastSyncDate(_ date: Date) async throws { _ = date }
}

@MainActor
private func makeDependencies(
    apiClient: LibraryViewModelAPIClientStub,
    repository: LibraryViewModelRepositoryStub
) -> ReelFinDependencies {
    let detailRepository = DefaultMediaDetailRepository(
        apiClient: apiClient,
        repository: repository,
        itemTTL: 60,
        detailTTL: 60,
        collectionTTL: 60
    )
    let warmupManager = PlaybackWarmupManager(apiClient: apiClient, ttl: 60)

    return ReelFinDependencies(
        apiClient: apiClient,
        repository: repository,
        detailRepository: detailRepository,
        imagePipeline: MockImagePipeline(),
        syncEngine: MockSyncEngine(),
        settingsStore: MockSettingsStore(),
        episodeReleaseNotificationManager: NoopEpisodeReleaseNotificationManager(),
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
