import PlaybackEngine
import JellyfinAPI
import Shared
import SwiftUI
import UIKit

final class MockJellyfinAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    private var config: ServerConfiguration?
    private var session: UserSession? = UserSession(userID: "preview-user", username: "Preview", token: "token")

    func currentConfiguration() async -> ServerConfiguration? {
        config
    }

    func currentSession() async -> UserSession? {
        session
    }

    func configure(server: ServerConfiguration) async throws {
        config = server
    }

    func testConnection(serverURL: URL) async throws {}

    func authenticate(credentials: UserCredentials) async throws -> UserSession {
        let newSession = UserSession(userID: "preview-user", username: credentials.username, token: "token")
        session = newSession
        return newSession
    }

    func signOut() async {
        session = nil
    }

    func fetchUserViews() async throws -> [Shared.LibraryView] {
        [Shared.LibraryView(id: "movies", name: "Movies", collectionType: "movies")]
    }

    func fetchItem(id: String) async throws -> MediaItem {
        Self.sampleItems(prefix: 1).first!
    }

    func fetchSeasons(seriesID: String) async throws -> [MediaItem] {
        [
            MediaItem(id: "season1", name: "Season 1", mediaType: .season, indexNumber: 1),
            MediaItem(id: "season2", name: "Season 2", mediaType: .season, indexNumber: 2)
        ]
    }

    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] {
        Self.sampleItems(prefix: 5).enumerated().map { index, item in
            var modified = item
            modified.mediaType = .episode
            modified.indexNumber = index + 1
            return modified
        }
    }

    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? {
        // For previews, return the second episode to simulate resume behaviour
        let eps = try await fetchEpisodes(seriesID: seriesID, seasonID: "season1")
        return eps.first
    }

    func fetchHomeFeed(since: Date?) async throws -> HomeFeed {
        let recentMovies = Self.sampleItems(prefix: 8).map { item -> MediaItem in
            var copy = item
            copy.mediaType = .movie
            return copy
        }
        let recentSeries = Self.sampleItems(prefix: 8).map { item -> MediaItem in
            var copy = item
            copy.mediaType = .series
            return copy
        }
        let nextUp = Self.sampleItems(prefix: 8).enumerated().map { index, item -> MediaItem in
            var copy = item
            copy.mediaType = .episode
            copy.indexNumber = index + 1
            copy.parentIndexNumber = 1
            copy.seriesName = "Sample Series \(index + 1)"
            return copy
        }

        return HomeFeed(featured: Self.sampleItems(prefix: 5), rows: [
            HomeRow(kind: .continueWatching, title: "Continue Watching", items: Self.sampleItems(prefix: 8)),
            HomeRow(kind: .nextUp, title: "Next Up", items: nextUp),
            HomeRow(kind: .recentlyAddedMovies, title: "Recently Added Movies", items: recentMovies),
            HomeRow(kind: .recentlyAddedSeries, title: "Recently Added Series", items: recentSeries),
            HomeRow(kind: .popular, title: "Popular", items: Self.sampleItems(prefix: 8)),
            HomeRow(kind: .trending, title: "Trending", items: Self.sampleItems(prefix: 8)),
            HomeRow(kind: .movies, title: "Movies", items: Self.sampleItems(prefix: 8)),
            HomeRow(kind: .shows, title: "Shows", items: Self.sampleItems(prefix: 8).map { item in
                var copy = item
                copy.mediaType = .series
                return copy
            })
        ])
    }

    func fetchItemDetail(id: String) async throws -> MediaDetail {
        let item = Self.sampleItems(prefix: 1).first ?? MediaItem(id: id, name: "Mock")
        return MediaDetail(item: item, similar: Self.sampleItems(prefix: 8), cast: [
            PersonCredit(id: "1", name: "Actor One", role: "Lead"),
            PersonCredit(id: "2", name: "Actor Two", role: "Support")
        ])
    }

    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        Self.sampleItems(prefix: query.pageSize)
    }

    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] {
        [
            MediaSource(
                id: "source-1",
                itemID: itemID,
                name: "Mock Source",
                container: "mp4",
                videoCodec: "h264",
                audioCodec: "aac",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"),
                directPlayURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"),
                transcodeURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"),
                audioTracks: [MediaTrack(id: "audio-1", title: "English", language: "en", isDefault: true, index: 0)],
                subtitleTracks: [MediaTrack(id: "sub-1", title: "English CC", language: "en", isDefault: true, index: 0)]
            )
        ]
    }

    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? {
        URL(string: "https://picsum.photos/\(width ?? 400)/600?random=\(itemID.hashValue)")
    }

    func reportPlayback(progress: PlaybackProgressUpdate) async throws {}

    func reportPlayed(itemID: String) async throws {}

    private static func sampleItems(prefix: Int) -> [MediaItem] {
        var items: [MediaItem] = []
        items.reserveCapacity(prefix)

        for index in 0 ..< prefix {
            let mediaType: MediaType = index.isMultiple(of: 2) ? .movie : .series
            let runtimeTicks = Int64((95 + index * 3) * 60 * 10_000_000)
            let rating = 7.4 + Double(index) * 0.1

            let item = MediaItem(
                id: "sample-\(index)",
                name: "Sample Title \(index + 1)",
                overview: "A high-quality preview entry used to validate the UI and offline rendering pipeline.",
                mediaType: mediaType,
                year: 2020 + (index % 5),
                runtimeTicks: runtimeTicks,
                genres: ["Drama", "Thriller"],
                communityRating: rating,
                posterTag: "poster",
                backdropTag: "backdrop",
                libraryID: "movies"
            )
            items.append(item)
        }

        return items
    }
}

final class MockMetadataRepository: MetadataRepositoryProtocol, @unchecked Sendable {
    private var homeFeed: HomeFeed = HomeFeed.empty
    private var itemsByID: [String: MediaItem] = [:]

    func saveLibraryViews(_ views: [Shared.LibraryView]) async throws {}
    func fetchLibraryViews() async throws -> [Shared.LibraryView] { [] }

    func saveHomeFeed(_ feed: HomeFeed) async throws {
        homeFeed = feed
        for item in feed.featured + feed.rows.flatMap(\.items) {
            itemsByID[item.id] = item
        }
    }

    func fetchHomeFeed() async throws -> HomeFeed {
        if homeFeed.rows.isEmpty {
            homeFeed = try await MockJellyfinAPIClient().fetchHomeFeed(since: nil)
        }
        return homeFeed
    }

    func upsertItems(_ items: [MediaItem]) async throws {
        for item in items {
            itemsByID[item.id] = item
        }
    }

    func fetchItem(id: String) async throws -> MediaItem? {
        itemsByID[id]
    }

    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        let all = Array(itemsByID.values)
        return Array(all.prefix(query.pageSize))
    }

    func searchItems(query: String, limit: Int) async throws -> [MediaItem] {
        Array(itemsByID.values.prefix(limit))
    }

    func savePlaybackProgress(_ progress: PlaybackProgress) async throws {}
    func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? { nil }

    func fetchLastSyncDate() async throws -> Date? { nil }
    func setLastSyncDate(_ date: Date) async throws {}
}

final class MockImagePipeline: ImagePipelineProtocol, @unchecked Sendable {
    func image(for url: URL) async throws -> UIImage {
        UIImage(systemName: "film.fill") ?? UIImage()
    }

    func cachedImage(for url: URL) async -> UIImage? {
        nil
    }

    func prefetch(urls: [URL]) async {}

    func cancel(url: URL) {}
}

final class MockSyncEngine: SyncEngineProtocol, @unchecked Sendable {
    func sync(reason: SyncReason) async {}
}

public enum ReelFinPreviewFactory {
    @MainActor public static func dependencies() -> ReelFinDependencies {
        let api = MockJellyfinAPIClient()
        let repository = MockMetadataRepository()
        let images = MockImagePipeline()
        let sync = MockSyncEngine()
        let settings = DefaultSettingsStore()
        let seriesCache = SeriesLookupCache(apiClient: api)

        return ReelFinDependencies(
            apiClient: api,
            repository: repository,
            imagePipeline: images,
            syncEngine: sync,
            settingsStore: settings,
            seriesCache: seriesCache,
            makePlaybackSession: {
                PlaybackSessionController(apiClient: api, repository: repository)
            }
        )
    }
}

#Preview {
    ReelFinRootView(dependencies: ReelFinPreviewFactory.dependencies())
}
