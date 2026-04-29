import PlaybackEngine
import JellyfinAPI
import Shared
import SwiftUI
import UIKit

final class MockJellyfinAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    private var config: ServerConfiguration?
    private var session: UserSession?
    private(set) var configureCallCount = 0
    private(set) var testConnectionCallCount = 0
    private(set) var authenticateCallCount = 0

    init(authenticated: Bool = true) {
        config = ServerConfiguration(serverURL: URL(string: "https://demo.reelfin.app")!)
        session = authenticated ? UserSession(userID: "preview-user", username: "Preview", token: "token") : nil
    }

    func currentConfiguration() async -> ServerConfiguration? {
        config
    }

    func currentSession() async -> UserSession? {
        session
    }

    func configure(server: ServerConfiguration) async throws {
        configureCallCount += 1
        config = server
    }

    func testConnection(serverURL: URL) async throws {
        testConnectionCallCount += 1
    }

    func authenticate(credentials: UserCredentials) async throws -> UserSession {
        authenticateCallCount += 1
        let newSession = UserSession(userID: "preview-user", username: credentials.username, token: "token")
        session = newSession
        return newSession
    }

    func signOut() async {
        session = nil
    }

    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState {
        QuickConnectState(code: "1234", secret: "mock-secret")
    }

    func pollQuickConnect(secret: String) async throws -> UserSession? {
        nil
    }

    func fetchUserViews() async throws -> [Shared.LibraryView] {
        [Shared.LibraryView(id: "movies", name: "Movies", collectionType: "movies")]
    }

    func fetchItem(id: String) async throws -> MediaItem {
        Self.item(for: id)
    }

    func fetchSeasons(seriesID: String) async throws -> [MediaItem] {
        [
            MediaItem(id: "season1", name: "Season 1", mediaType: .season, indexNumber: 1),
            MediaItem(id: "season2", name: "Season 2", mediaType: .season, indexNumber: 2)
        ]
    }

    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] {
        if seriesID == "series-continue-1" {
            return Self.continueWatchingEpisodes()
        }

        return Self.sampleItems(prefix: 5).enumerated().map { index, item in
            var modified = item
            modified.mediaType = .episode
            modified.indexNumber = index + 1
            modified.parentID = seriesID
            return modified
        }
    }

    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? {
        if seriesID == "series-continue-1" {
            return Self.continueWatchingEpisodes()[1]
        }

        let eps = try await fetchEpisodes(seriesID: seriesID, seasonID: "season1")
        return eps.first
    }

    func fetchNextUpEpisodes(limit: Int) async throws -> [MediaItem] {
        Array(Self.continueWatchingEpisodes().prefix(limit))
    }

    func fetchHomeFeed(since: Date?) async throws -> HomeFeed {
        let releasedMovies = Self.sampleItems(prefix: 8).enumerated().map { index, item -> MediaItem in
            var copy = item
            copy.mediaType = .movie
            copy.year = 2026 - (index % 3)
            return copy
        }
        let releasedSeries = Self.sampleItems(prefix: 8).enumerated().map { index, item -> MediaItem in
            var copy = item
            copy.id = "released-series-\(index)"
            copy.name = "Released Series \(index + 1)"
            copy.mediaType = .series
            copy.year = 2026 - (index % 2)
            return copy
        }
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
        return HomeFeed(featured: Self.sampleItems(prefix: 5), rows: [
            HomeRow(kind: .continueWatching, title: "Continue Watching", items: Self.continueWatchingItems()),
            HomeRow(kind: .recentlyReleasedMovies, title: "Recently Released Movies", items: releasedMovies),
            HomeRow(kind: .recentlyReleasedSeries, title: "Recently Released TV Shows", items: releasedSeries),
            HomeRow(kind: .recentlyAddedMovies, title: "Recently Added Movies", items: recentMovies),
            HomeRow(kind: .recentlyAddedSeries, title: "Recently Added TV", items: recentSeries)
        ])
    }

    func fetchItemDetail(id: String) async throws -> MediaDetail {
        let item = Self.item(for: id)
        return MediaDetail(item: item, similar: Self.sampleItems(prefix: 8), cast: [
            PersonCredit(id: "1", name: "Actor One", role: "Lead", primaryImageTag: "primary"),
            PersonCredit(id: "2", name: "Actor Two", role: "Support", primaryImageTag: "primary")
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
        let normalizedWidth = width.map { type.normalizedImageWidth($0) } ?? 400
        return URL(string: "mock-image://\(itemID)?type=\(type.rawValue)&width=\(normalizedWidth)")
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

    private static func continueWatchingItems() -> [MediaItem] {
        let resumeEpisode = continueWatchingEpisodes()[1]
        let resumeMovie = MediaItem(
            id: "cw-movie-1",
            name: "Resume Movie",
            overview: "A mock movie already started for validating direct resume from home.",
            mediaType: .movie,
            year: 2024,
            runtimeTicks: Int64(112 * 60 * 10_000_000),
            genres: ["Adventure"],
            communityRating: 7.8,
            posterTag: "poster",
            backdropTag: "backdrop",
            libraryID: "movies",
            has4K: true,
            isPlayed: false,
            playbackPositionTicks: Int64(41 * 60 * 10_000_000)
        )

        return [resumeEpisode, resumeMovie] + sampleItems(prefix: 6)
    }

    private static func continueWatchingEpisodes() -> [MediaItem] {
        [
            MediaItem(
                id: "cw-episode-1",
                name: "Pilot",
                overview: "The opening episode used to validate series resume flow.",
                mediaType: .episode,
                year: 2025,
                runtimeTicks: Int64(24 * 60 * 10_000_000),
                genres: ["Drama"],
                communityRating: 7.9,
                posterTag: "poster",
                backdropTag: "backdrop",
                libraryID: "shows",
                parentID: "series-continue-1",
                seriesName: "Continue Series",
                seriesPosterTag: "poster",
                indexNumber: 1,
                parentIndexNumber: 1,
                isPlayed: true,
                playbackPositionTicks: Int64(24 * 60 * 10_000_000)
            ),
            MediaItem(
                id: "cw-episode-2",
                name: "Second Wind",
                overview: "The in-progress episode used to validate direct resume from Continue Watching.",
                mediaType: .episode,
                year: 2025,
                runtimeTicks: Int64(27 * 60 * 10_000_000),
                genres: ["Drama"],
                communityRating: 8.1,
                posterTag: "poster",
                backdropTag: "backdrop",
                libraryID: "shows",
                parentID: "series-continue-1",
                seriesName: "Continue Series",
                seriesPosterTag: "poster",
                indexNumber: 2,
                parentIndexNumber: 1,
                isPlayed: false,
                playbackPositionTicks: Int64((11 * 60 + 12) * 10_000_000)
            )
        ]
    }

    private static func item(for id: String) -> MediaItem {
        if let match = continueWatchingItems().first(where: { $0.id == id }) {
            return match
        }

        if id == "series-continue-1" {
            return MediaItem(
                id: "series-continue-1",
                name: "Continue Series",
                overview: "Mock series container for continue watching playback resolution.",
                mediaType: .series,
                year: 2025,
                runtimeTicks: Int64(27 * 60 * 10_000_000),
                genres: ["Drama"],
                communityRating: 8.1,
                posterTag: "poster",
                backdropTag: "backdrop",
                libraryID: "shows"
            )
        }

        return sampleItems(prefix: 8).first(where: { $0.id == id }) ?? MediaItem(id: id, name: "Mock")
    }
}

final class MockSettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    var serverConfiguration: ServerConfiguration?
    var lastSession: UserSession?
    var episodeReleaseNotificationsEnabled = false
    var hasCompletedOnboarding: Bool
    var completedOnboardingVersion: Int

    init(authenticated: Bool = true) {
        serverConfiguration = ServerConfiguration(serverURL: URL(string: "https://demo.reelfin.app")!)
        lastSession = authenticated ? UserSession(userID: "preview-user", username: "Preview", token: "token") : nil
        hasCompletedOnboarding = authenticated
        completedOnboardingVersion = authenticated ? ReelFinOnboardingVersion.current : 0
    }
}

actor MockMetadataRepository: MetadataRepositoryProtocol {
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
        ArtworkPlaceholderRenderer.makeImage(seed: url.absoluteString)
    }

    func image(for url: URL, consumer consumerID: ImageRequestConsumerID) async throws -> UIImage {
        _ = consumerID
        return try await image(for: url)
    }

    func cachedImage(for url: URL) async -> UIImage? {
        nil
    }

    func prefetch(urls: [URL]) async {}

    func cancel(url: URL) {}

    func cancel(url: URL, consumer consumerID: ImageRequestConsumerID) {
        _ = consumerID
    }
}

private enum ArtworkPlaceholderRenderer {
    static func makeImage(seed: String, size: CGSize = CGSize(width: 900, height: 1350)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let palette = palette(for: seed)

        return renderer.image { context in
            let cgContext = context.cgContext

            let gradientColors = palette.map(\.cgColor) as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0, 0.55, 1])!

            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            UIColor.white.withAlphaComponent(0.07).setFill()
            cgContext.fillEllipse(in: CGRect(x: size.width - 420, y: size.height - 520, width: 560, height: 560))

            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 220, weight: .bold)
            let symbol = UIImage(systemName: "film.stack.fill", withConfiguration: symbolConfiguration)?
                .withTintColor(.white.withAlphaComponent(0.16), renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: 72, y: size.height - 360, width: 220, height: 220))
        }
    }

    private static func palette(for seed: String) -> [UIColor] {
        let palettes: [[UIColor]] = [
            [UIColor(red: 0.07, green: 0.10, blue: 0.18, alpha: 1), UIColor(red: 0.17, green: 0.30, blue: 0.54, alpha: 1), UIColor(red: 0.03, green: 0.64, blue: 0.89, alpha: 1)],
            [UIColor(red: 0.20, green: 0.07, blue: 0.16, alpha: 1), UIColor(red: 0.54, green: 0.16, blue: 0.29, alpha: 1), UIColor(red: 0.89, green: 0.36, blue: 0.29, alpha: 1)],
            [UIColor(red: 0.10, green: 0.18, blue: 0.12, alpha: 1), UIColor(red: 0.18, green: 0.40, blue: 0.24, alpha: 1), UIColor(red: 0.62, green: 0.83, blue: 0.39, alpha: 1)],
            [UIColor(red: 0.11, green: 0.08, blue: 0.20, alpha: 1), UIColor(red: 0.28, green: 0.20, blue: 0.55, alpha: 1), UIColor(red: 0.72, green: 0.48, blue: 0.96, alpha: 1)]
        ]

        let index = abs(seed.hashValue) % palettes.count
        return palettes[index]
    }
}

final class MockSyncEngine: SyncEngineProtocol, @unchecked Sendable {
    func sync(reason: SyncReason) async {}
}

public enum ReelFinPreviewFactory {
    @MainActor public static func dependencies(authenticated: Bool = true) -> ReelFinDependencies {
        dependencies(
            authenticated: authenticated,
            apiClient: MockJellyfinAPIClient(authenticated: authenticated)
        )
    }

    @MainActor static func dependencies(
        authenticated: Bool = true,
        apiClient: MockJellyfinAPIClient
    ) -> ReelFinDependencies {
        let api = apiClient
        let repository = MockMetadataRepository()
        let detailRepository = DefaultMediaDetailRepository(
            apiClient: api,
            repository: repository,
            itemTTL: 60,
            detailTTL: 60,
            collectionTTL: 60
        )
        let images = MockImagePipeline()
        let sync = MockSyncEngine()
        let settings = MockSettingsStore(authenticated: authenticated)
        let notifications = NoopEpisodeReleaseNotificationManager()
        let seriesCache = SeriesLookupCache(apiClient: api)
        let warmupManager = PlaybackWarmupManager(apiClient: api, ttl: 60)
        let tvFocusWarmupCoordinator = TVFocusWarmupCoordinator(
            settleDelayNanoseconds: 0,
            maxConcurrentJobs: 1
        )

        return ReelFinDependencies(
            apiClient: api,
            repository: repository,
            detailRepository: detailRepository,
            imagePipeline: images,
            syncEngine: sync,
            settingsStore: settings,
            episodeReleaseNotificationManager: notifications,
            seriesCache: seriesCache,
            playbackWarmupManager: warmupManager,
            tvFocusWarmupCoordinator: tvFocusWarmupCoordinator,
            makePlaybackSession: {
                PlaybackSessionController(
                    apiClient: api,
                    repository: repository,
                    warmupManager: warmupManager
                )
            }
        )
    }

    @MainActor public static func appStoreDependencies(authenticated: Bool = true) -> ReelFinDependencies {
        dependencies(authenticated: authenticated)
    }
}

#Preview {
    ReelFinRootView(dependencies: ReelFinPreviewFactory.dependencies())
}
