import Foundation
import Shared
import XCTest

final class MediaDetailRepositoryTests: XCTestCase {
    func test_loadDetail_deduplicatesConcurrentRequests() async throws {
        let apiClient = DetailRepositoryAPIClient()
        let repository = DetailRepositoryStore()
        let detailRepository = DefaultMediaDetailRepository(
            apiClient: apiClient,
            repository: repository,
            itemTTL: 60,
            detailTTL: 60,
            collectionTTL: 60
        )

        async let first = detailRepository.loadDetail(id: "movie-1")
        async let second = detailRepository.loadDetail(id: "movie-1")
        async let third = detailRepository.loadDetail(id: "movie-1")

        let details = try await [first, second, third]

        XCTAssertEqual(details.count, 3)
        XCTAssertEqual(apiClient.fetchItemDetailCallCount, 1)
    }

    func test_refreshItem_updatesRepositoryAndCachesResult() async throws {
        let apiClient = DetailRepositoryAPIClient()
        let repository = DetailRepositoryStore()
        let detailRepository = DefaultMediaDetailRepository(
            apiClient: apiClient,
            repository: repository,
            itemTTL: 60,
            detailTTL: 60,
            collectionTTL: 60
        )

        let item = try await detailRepository.refreshItem(id: "movie-1")
        let cached = await detailRepository.cachedItem(id: "movie-1")
        let upsertedItemIDs = await repository.upsertedItemIDs

        XCTAssertEqual(item.id, "movie-1")
        XCTAssertEqual(cached?.id, "movie-1")
        XCTAssertEqual(apiClient.fetchItemCallCount, 1)
        XCTAssertEqual(upsertedItemIDs, ["movie-1"])
    }

    func test_loadEpisodes_usesMemoryCacheForRepeatedRequests() async throws {
        let apiClient = DetailRepositoryAPIClient()
        let repository = DetailRepositoryStore()
        let detailRepository = DefaultMediaDetailRepository(
            apiClient: apiClient,
            repository: repository,
            itemTTL: 60,
            detailTTL: 60,
            collectionTTL: 60
        )

        let first = try await detailRepository.loadEpisodes(seriesID: "series-1", seasonID: "season-1")
        let second = try await detailRepository.loadEpisodes(seriesID: "series-1", seasonID: "season-1")

        XCTAssertEqual(first.count, second.count)
        XCTAssertEqual(apiClient.fetchEpisodesCallCount, 1)
    }
}

private actor DetailRepositoryStore: MetadataRepositoryProtocol {
    private(set) var upsertedItemIDs: [String] = []
    private var itemsByID: [String: MediaItem] = [:]

    func saveLibraryViews(_ views: [LibraryView]) async throws {}
    func fetchLibraryViews() async throws -> [LibraryView] { [] }
    func saveHomeFeed(_ feed: HomeFeed) async throws {}
    func fetchHomeFeed() async throws -> HomeFeed { .empty }

    func upsertItems(_ items: [MediaItem]) async throws {
        upsertedItemIDs.append(contentsOf: items.map(\.id))
        for item in items {
            itemsByID[item.id] = item
        }
    }

    func fetchItem(id: String) async throws -> MediaItem? {
        itemsByID[id]
    }

    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { [] }
    func searchItems(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func savePlaybackProgress(_ progress: PlaybackProgress) async throws {}
    func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? { nil }
    func fetchLastSyncDate() async throws -> Date? { nil }
    func setLastSyncDate(_ date: Date) async throws {}
}

private final class DetailRepositoryAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    var fetchItemCallCount = 0
    var fetchItemDetailCallCount = 0
    var fetchEpisodesCallCount = 0

    func currentConfiguration() async -> ServerConfiguration? { nil }
    func currentSession() async -> UserSession? { nil }
    func configure(server: ServerConfiguration) async throws {}
    func testConnection(serverURL: URL) async throws {}
    func authenticate(credentials: UserCredentials) async throws -> UserSession { throw AppError.unknown }
    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { nil }
    func fetchUserViews() async throws -> [LibraryView] { [] }
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed { .empty }

    func fetchItem(id: String) async throws -> MediaItem {
        fetchItemCallCount += 1
        return MediaItem(
            id: id,
            name: "Fetched \(id)",
            overview: "Remote item",
            mediaType: .movie,
            year: 2024,
            runtimeTicks: Int64(120 * 60 * 10_000_000),
            genres: ["Drama"],
            posterTag: "poster",
            backdropTag: "backdrop"
        )
    }

    func fetchItemDetail(id: String) async throws -> MediaDetail {
        fetchItemDetailCallCount += 1
        return MediaDetail(
            item: try await fetchItem(id: id),
            similar: [
                MediaItem(id: "similar-1", name: "Similar", mediaType: .movie)
            ],
            cast: [
                PersonCredit(id: "cast-1", name: "Performer", role: "Lead")
            ]
        )
    }

    func fetchSeasons(seriesID: String) async throws -> [MediaItem] {
        [
            MediaItem(id: "season-1", name: "Season 1", mediaType: .season, indexNumber: 1)
        ]
    }

    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] {
        fetchEpisodesCallCount += 1
        return [
            MediaItem(
                id: "episode-1",
                name: "Episode 1",
                mediaType: .episode,
                runtimeTicks: Int64(40 * 60 * 10_000_000),
                parentID: seriesID,
                indexNumber: 1,
                parentIndexNumber: 1
            )
        ]
    }

    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? {
        MediaItem(
            id: "episode-1",
            name: "Episode 1",
            mediaType: .episode,
            runtimeTicks: Int64(40 * 60 * 10_000_000),
            parentID: seriesID,
            indexNumber: 1,
            parentIndexNumber: 1
        )
    }

    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { [] }
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] { [] }
    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] { [] }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? { nil }
    func prefetchImages(for items: [MediaItem]) async {}
    func reportPlayback(progress: PlaybackProgressUpdate) async throws {}
    func reportPlayed(itemID: String) async throws {}
}
