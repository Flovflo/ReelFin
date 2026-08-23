import Shared
@testable import SyncEngine
import XCTest

final class DefaultSyncEngineHomeFeedTests: XCTestCase {
    func testIncrementalHomeFeedDoesNotOverwriteCachedCatalogRowsWithEmptyRows() async throws {
        let cachedFeed = Self.homeFeed(itemSuffix: "cached", emptyKinds: [])
        let incrementalFeed = Self.homeFeed(
            itemSuffix: "incremental",
            emptyKinds: [.recentlyReleasedMovies, .recentlyAddedMovies, .recentlyAddedSeries]
        )
        let fullFeed = Self.homeFeed(itemSuffix: "full", emptyKinds: [])

        let repository = HomeFeedSyncRepository(
            cachedFeed: cachedFeed,
            lastSyncDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let apiClient = HomeFeedSyncAPIClient(incrementalFeed: incrementalFeed, fullFeed: fullFeed)
        let syncEngine = DefaultSyncEngine(
            apiClient: apiClient,
            repository: repository,
            artworkPrefetcher: RecordingArtworkPrefetcher()
        )

        await syncEngine.sync(reason: .appForeground)

        let savedFeed = try await repository.fetchHomeFeed()
        XCTAssertEqual(savedFeed.rows.map(\.kind), Self.expectedKinds)
        XCTAssertEqual(savedFeed.rows.map { $0.items.map(\.id) }, fullFeed.rows.map { $0.items.map(\.id) })
        let sinceValues = await apiClient.fetchHomeFeedSinceValues()
        XCTAssertEqual(sinceValues, [Date(timeIntervalSince1970: 1_700_000_000), nil])
    }

    func testPrefetchMapsFeaturedResumeNextUpAndCatalogRowsToCanonicalRoles() async throws {
        let featured = MediaItem(id: "featured", name: "Featured", backdropTag: "featured-backdrop")
        let resume = MediaItem(
            id: "episode",
            name: "Episode",
            mediaType: .episode,
            backdropTag: "episode-backdrop",
            parentID: "series"
        )
        let nextUp = MediaItem(id: "next", name: "Next")
        let catalog = MediaItem(id: "catalog", name: "Catalog", backdropTag: "catalog-backdrop")
        let feed = HomeFeed(
            featured: [featured],
            rows: [
                HomeRow(kind: .continueWatching, title: "Continue", items: [resume]),
                HomeRow(kind: .nextUp, title: "Next Up", items: [nextUp]),
                HomeRow(kind: .recentlyAddedMovies, title: "Recently Added", items: [catalog])
            ]
        )
        let repository = HomeFeedSyncRepository(cachedFeed: feed, lastSyncDate: nil)
        let apiClient = HomeFeedSyncAPIClient(incrementalFeed: feed, fullFeed: feed)
        let prefetcher = RecordingArtworkPrefetcher()
        let syncEngine = DefaultSyncEngine(
            apiClient: apiClient,
            repository: repository,
            artworkPrefetcher: prefetcher
        )

        await syncEngine.sync(reason: .manualRefresh)
        try await waitUntil { await prefetcher.batches.count == 1 }

        guard let requests = await prefetcher.batches.first else {
            XCTFail("Expected one artwork prefetch batch after manual refresh")
            return
        }
        let expectedFeaturedRequests = [
            ArtworkRequest.make(for: featured, role: .heroLow),
            ArtworkRequest.make(for: featured, role: .heroHigh)
        ]
        XCTAssertEqual(Array(requests.prefix(2)), expectedFeaturedRequests)
        XCTAssertEqual(requests.map(\.itemID), ["featured", "featured", "series", "next", "catalog"])
        XCTAssertEqual(
            requests.map(\.profile),
            [.heroBackdropLow, .heroBackdropHigh, .landscapeRail, .landscapeRail, .posterRow]
        )
        XCTAssertEqual(requests.map(\.type), [.backdrop, .backdrop, .backdrop, .backdrop, .primary])
    }

    func testStartingNewPrefetchCancelsPreviousPrefetchTask() async throws {
        let feed = Self.homeFeed(itemSuffix: "latest", emptyKinds: [])
        let repository = HomeFeedSyncRepository(cachedFeed: feed, lastSyncDate: nil)
        let apiClient = HomeFeedSyncAPIClient(incrementalFeed: feed, fullFeed: feed)
        let prefetcher = CancellationRecordingArtworkPrefetcher()
        let syncEngine = DefaultSyncEngine(
            apiClient: apiClient,
            repository: repository,
            artworkPrefetcher: prefetcher
        )

        await syncEngine.sync(reason: .manualRefresh)
        try await waitUntil { await prefetcher.callCount == 1 }

        await syncEngine.sync(reason: .manualRefresh)

        try await waitUntil {
            let status = await prefetcher.status()
            return status.callCount == 2 && status.cancelledCallIndices == [0]
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }

    private static let expectedKinds: [HomeSectionKind] = [
        .continueWatching, .recentlyReleasedMovies, .recentlyReleasedSeries, .recentlyAddedMovies, .recentlyAddedSeries
    ]

    private static func homeFeed(itemSuffix: String, emptyKinds: Set<HomeSectionKind>) -> HomeFeed {
        let titles: [HomeSectionKind: String] = [
            .continueWatching: "Continue Watching",
            .recentlyReleasedMovies: "Recently Released Movies",
            .recentlyReleasedSeries: "Recently Released TV Shows",
            .recentlyAddedMovies: "Recently Added Movies",
            .recentlyAddedSeries: "Recently Added TV"
        ]
        let rows = expectedKinds.map {
            row(kind: $0, title: titles[$0, default: $0.rawValue], itemSuffix: itemSuffix, emptyKinds: emptyKinds)
        }
        return HomeFeed(featured: rows.flatMap(\.items).prefix(4).map { $0 }, rows: rows)
    }

    private static func row(
        kind: HomeSectionKind,
        title: String,
        itemSuffix: String,
        emptyKinds: Set<HomeSectionKind>
    ) -> HomeRow {
        let items = emptyKinds.contains(kind)
            ? []
            : [MediaItem(id: "\(kind.rawValue)-\(itemSuffix)", name: title, mediaType: mediaType(for: kind))]
        return HomeRow(kind: kind, title: title, items: items)
    }

    private static func mediaType(for kind: HomeSectionKind) -> MediaType {
        switch kind {
        case .recentlyReleasedSeries, .recentlyAddedSeries:
            return .series
        default:
            return .movie
        }
    }
}

private actor HomeFeedSyncRepository: MetadataRepositoryProtocol {
    private var homeFeed: HomeFeed
    private var lastSyncDate: Date?

    init(cachedFeed: HomeFeed, lastSyncDate: Date?) {
        self.homeFeed = cachedFeed
        self.lastSyncDate = lastSyncDate
    }

    func saveLibraryViews(_ views: [LibraryView]) async throws { _ = views }
    func fetchLibraryViews() async throws -> [LibraryView] { [] }
    func saveHomeFeed(_ feed: HomeFeed) async throws { homeFeed = feed }
    func fetchHomeFeed() async throws -> HomeFeed { homeFeed }
    func upsertItems(_ items: [MediaItem]) async throws { _ = items }
    func fetchItem(id: String) async throws -> MediaItem? { _ = id; return nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { _ = query; return [] }
    func searchItems(query: String, limit: Int) async throws -> [MediaItem] {
        _ = query
        _ = limit
        return []
    }
    func savePlaybackProgress(_ progress: PlaybackProgress) async throws { _ = progress }
    func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? { _ = itemID; return nil }
    func fetchLastSyncDate() async throws -> Date? { lastSyncDate }
    func setLastSyncDate(_ date: Date) async throws { lastSyncDate = date }
}

private actor HomeFeedSyncAPIClient: JellyfinAPIClientProtocol {
    private let incrementalFeed: HomeFeed
    private let fullFeed: HomeFeed
    private var sinceValues: [Date?] = []

    init(incrementalFeed: HomeFeed, fullFeed: HomeFeed) {
        self.incrementalFeed = incrementalFeed
        self.fullFeed = fullFeed
    }

    func fetchHomeFeedSinceValues() -> [Date?] { sinceValues }

    func currentConfiguration() async -> ServerConfiguration? { nil }
    func currentSession() async -> UserSession? { nil }
    func configure(server: ServerConfiguration) async throws { _ = server }
    func testConnection(serverURL: URL) async throws { _ = serverURL }
    func authenticate(credentials: UserCredentials) async throws -> UserSession {
        _ = credentials
        throw AppError.unknown
    }
    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState {
        _ = serverURL
        throw AppError.unknown
    }
    func pollQuickConnect(secret: String) async throws -> UserSession? { _ = secret; return nil }
    func fetchUserViews() async throws -> [LibraryView] { [] }
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed {
        sinceValues.append(since)
        return since == nil ? fullFeed : incrementalFeed
    }
    func fetchItem(id: String) async throws -> MediaItem { MediaItem(id: id, name: id) }
    func fetchItemDetail(id: String) async throws -> MediaDetail { MediaDetail(item: MediaItem(id: id, name: id)) }
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { _ = seriesID; return [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { [] }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? { _ = seriesID; return nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { _ = query; return [] }
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] { _ = itemID; return [] }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? { nil }
    func reportPlayback(progress: PlaybackProgressUpdate) async throws { _ = progress }
    func reportPlayed(itemID: String) async throws { _ = itemID }
}

private actor RecordingArtworkPrefetcher: ArtworkPrefetching {
    private(set) var batches = [[ArtworkRequest]]()

    func prefetch(_ requests: [ArtworkRequest]) async {
        batches.append(requests)
    }
}

private actor CancellationRecordingArtworkPrefetcher: ArtworkPrefetching {
    private(set) var callCount = 0
    private(set) var cancelledCallIndices = [Int]()

    func status() -> (callCount: Int, cancelledCallIndices: [Int]) {
        (callCount, cancelledCallIndices)
    }

    func prefetch(_ requests: [ArtworkRequest]) async {
        _ = requests
        let callIndex = callCount
        callCount += 1
        guard callIndex == 0 else { return }

        await withTaskCancellationHandler {
            do {
                try await Task.sleep(nanoseconds: UInt64.max)
            } catch {
                // Cancellation is asserted through the handler below.
            }
        } onCancel: {
            Task { await self.recordCancellation(callIndex) }
        }
    }

    private func recordCancellation(_ callIndex: Int) {
        cancelledCallIndices.append(callIndex)
    }
}
