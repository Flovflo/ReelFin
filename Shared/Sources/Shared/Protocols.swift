import Foundation
import UIKit

public enum SyncReason: String, Sendable {
    case appLaunch
    case appForeground
    case manualRefresh
    case backgroundRefresh
}

public enum AppError: LocalizedError, Sendable {
    case invalidServerURL
    case unauthenticated
    case network(String)
    case decoding(String)
    case persistence(String)
    case nativeBridge(String)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The server URL is invalid."
        case .unauthenticated:
            return "Please login first."
        case let .network(message):
            return message
        case let .decoding(message):
            return message
        case let .persistence(message):
            return message
        case let .nativeBridge(message):
            return message
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

public struct ImageRequestConsumerID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public protocol TokenStoreProtocol: AnyObject, Sendable {
    func saveToken(_ token: String) throws
    func fetchToken() throws -> String?
    func clearToken() throws
}

public protocol SettingsStoreProtocol: AnyObject, Sendable {
    var serverConfiguration: ServerConfiguration? { get set }
    var lastSession: UserSession? { get set }
    var episodeReleaseNotificationsEnabled: Bool { get set }
    var hasCompletedOnboarding: Bool { get set }
    var completedOnboardingVersion: Int { get set }
}

public protocol JellyfinAPIClientProtocol: AnyObject, Sendable {
    func currentConfiguration() async -> ServerConfiguration?
    func currentSession() async -> UserSession?

    func configure(server: ServerConfiguration) async throws
    func testConnection(serverURL: URL) async throws
    func authenticate(credentials: UserCredentials) async throws -> UserSession
    func signOut() async

    // Quick Connect (Jellyfin 10.7+)
    /// Initiates a Quick Connect request and returns the 4-character display code and an opaque secret.
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState
    /// Polls the server to check if the user has approved the code. Returns the session when approved.
    func pollQuickConnect(secret: String) async throws -> UserSession?

    func fetchUserViews() async throws -> [LibraryView]
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed
    func fetchNextUpEpisodes(limit: Int) async throws -> [MediaItem]
    func fetchItem(id: String) async throws -> MediaItem
    func fetchItemDetail(id: String) async throws -> MediaDetail
    func fetchSeasons(seriesID: String) async throws -> [MediaItem]
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem]
    /// Returns the next episode to watch for a given series (in-progress first, then next unplayed).
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem?
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem]
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource]
    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource]
    func fetchMediaSegments(itemID: String) async throws -> [MediaSegment]
    func fetchTrickplayManifest(itemID: String, mediaSourceID: String?) async throws -> TrickplayManifest?
    func trickplayTileBaseURL(itemID: String, mediaSourceID: String?, width: Int) async -> URL?

    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL?
    func prefetchImages(for items: [MediaItem]) async
    func reportPlayback(progress: PlaybackProgressUpdate) async throws
    func reportPlaybackStopped(progress: PlaybackProgressUpdate) async throws
    func reportPlayed(itemID: String) async throws
    func setPlayedState(itemID: String, isPlayed: Bool) async throws
    func setFavorite(itemID: String, isFavorite: Bool) async throws
}

public protocol MetadataRepositoryProtocol: AnyObject, Sendable {
    func saveLibraryViews(_ views: [LibraryView]) async throws
    func fetchLibraryViews() async throws -> [LibraryView]

    func saveHomeFeed(_ feed: HomeFeed) async throws
    func fetchHomeFeed() async throws -> HomeFeed

    func upsertItems(_ items: [MediaItem]) async throws
    func fetchItem(id: String) async throws -> MediaItem?
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem]
    func searchItems(query: String, limit: Int) async throws -> [MediaItem]

    func savePlaybackProgress(_ progress: PlaybackProgress) async throws
    func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress?

    func fetchLastSyncDate() async throws -> Date?
    func setLastSyncDate(_ date: Date) async throws

    func upsertEpisodeReleaseState(_ state: EpisodeReleaseState) async throws
    func fetchEpisodeReleaseState(seriesID: String) async throws -> EpisodeReleaseState?
    func fetchEpisodeReleaseStates() async throws -> [EpisodeReleaseState]
}

public protocol MediaDetailRepositoryProtocol: AnyObject, Sendable {
    func cachedItem(id: String) async -> MediaItem?
    func refreshItem(id: String) async throws -> MediaItem
    func loadDetail(id: String) async throws -> MediaDetail
    func loadSeasons(seriesID: String) async throws -> [MediaItem]
    func loadEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem]
    func loadNextUpEpisode(seriesID: String) async throws -> MediaItem?
    func primeItem(id: String) async
    func primeDetail(id: String) async
}

public protocol ImagePipelineProtocol: AnyObject, Sendable {
    func image(for url: URL) async throws -> UIImage
    func image(for url: URL, consumer consumerID: ImageRequestConsumerID) async throws -> UIImage
    func cachedImage(for url: URL) async -> UIImage?
    func prefetch(urls: [URL]) async
    func cancel(url: URL)
    func cancel(url: URL, consumer consumerID: ImageRequestConsumerID)
}

public protocol SyncEngineProtocol: AnyObject, Sendable {
    func sync(reason: SyncReason) async
}

public extension JellyfinAPIClientProtocol {
    func fetchNextUpEpisodes(limit _: Int) async throws -> [MediaItem] {
        []
    }

    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] {
        _ = options
        return try await fetchPlaybackSources(itemID: itemID)
    }

    // Default no-op: concrete clients may provide a real implementation.
    func prefetchImages(for items: [MediaItem]) async {}

    func fetchMediaSegments(itemID _: String) async throws -> [MediaSegment] {
        []
    }

    func fetchTrickplayManifest(itemID _: String, mediaSourceID _: String?) async throws -> TrickplayManifest? {
        nil
    }

    func trickplayTileBaseURL(itemID _: String, mediaSourceID _: String?, width _: Int) async -> URL? {
        nil
    }

    func reportPlaybackStopped(progress: PlaybackProgressUpdate) async throws {
        try await reportPlayback(progress: progress)
    }

    func setPlayedState(itemID: String, isPlayed: Bool) async throws {
        guard isPlayed else { return }
        try await reportPlayed(itemID: itemID)
    }

    func setFavorite(itemID _: String, isFavorite _: Bool) async throws {}
}

public extension ImagePipelineProtocol {
    func image(for url: URL, consumer consumerID: ImageRequestConsumerID) async throws -> UIImage {
        _ = consumerID
        return try await image(for: url)
    }

    func cancel(url: URL, consumer consumerID: ImageRequestConsumerID) {
        _ = consumerID
        cancel(url: url)
    }
}

public extension MetadataRepositoryProtocol {
    func upsertEpisodeReleaseState(_ state: EpisodeReleaseState) async throws {
        _ = state
    }

    func fetchEpisodeReleaseState(seriesID _: String) async throws -> EpisodeReleaseState? {
        nil
    }

    func fetchEpisodeReleaseStates() async throws -> [EpisodeReleaseState] {
        []
    }
}
