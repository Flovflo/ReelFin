@testable import PlaybackEngine
import Shared
import XCTest

final class PlaybackResumeTests: XCTestCase {
    @MainActor
    func testLoadPreservesResumeTicksAcrossInitialProfileUpgrade() async throws {
        let resumeTicks: Int64 = 42 * 10_000_000
        let configuration = ServerConfiguration(
            serverURL: URL(string: "https://example.com")!,
            playbackPolicy: .auto,
            allowSDRFallback: true,
            preferAudioTranscodeOnly: true
        )
        let source = MediaSource(
            id: "source-1",
            itemID: "item-1",
            name: "Premium Source",
            container: "avi",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 22_000_000,
            videoBitDepth: 10,
            videoRange: "HDR10",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(
                string: "https://example.com/Videos/item-1/master.mp4?AllowVideoStreamCopy=true&AllowAudioStreamCopy=false&VideoCodec=hevc"
            )!,
            videoWidth: 3840,
            videoHeight: 2160
        )
        let apiClient = RecordingPlaybackAPIClient(configuration: configuration, sourcesByItemID: ["item-1": [source]])
        let repository = ResumeMetadataRepository(
            playbackProgressByItemID: [
                "item-1": PlaybackProgress(
                    itemID: "item-1",
                    positionTicks: resumeTicks,
                    totalTicks: 120 * 10_000_000,
                    updatedAt: Date()
                )
            ]
        )
        let controller = PlaybackSessionController(apiClient: apiClient, repository: repository)

        try await controller.load(item: MediaItem(id: "item-1", name: "Movie", mediaType: .movie), autoPlay: false)

        XCTAssertEqual(apiClient.requestedOptions.count, 2)
        XCTAssertEqual(apiClient.requestedOptions.map(\.startTimeTicks), [resumeTicks, resumeTicks])
        controller.stop()
    }
}

private final class ResumeMetadataRepository: MetadataRepositoryProtocol, @unchecked Sendable {
    let playbackProgressByItemID: [String: PlaybackProgress]

    init(playbackProgressByItemID: [String: PlaybackProgress]) {
        self.playbackProgressByItemID = playbackProgressByItemID
    }

    func saveLibraryViews(_ views: [LibraryView]) async throws { _ = views }
    func fetchLibraryViews() async throws -> [LibraryView] { [] }
    func saveHomeFeed(_ feed: HomeFeed) async throws { _ = feed }
    func fetchHomeFeed() async throws -> HomeFeed { .empty }
    func upsertItems(_ items: [MediaItem]) async throws { _ = items }
    func fetchItem(id: String) async throws -> MediaItem? { nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { _ = query; return [] }
    func searchItems(query: String, limit: Int) async throws -> [MediaItem] { _ = query; _ = limit; return [] }
    func savePlaybackProgress(_ progress: PlaybackProgress) async throws { _ = progress }
    func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? { playbackProgressByItemID[itemID] }
    func fetchLastSyncDate() async throws -> Date? { nil }
    func setLastSyncDate(_ date: Date) async throws { _ = date }
}

private final class RecordingPlaybackAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    private let configurationValue: ServerConfiguration
    private let sessionValue: UserSession
    private let sourcesByItemID: [String: [MediaSource]]
    var requestedOptions: [PlaybackInfoOptions] = []

    init(configuration: ServerConfiguration, sourcesByItemID: [String: [MediaSource]]) {
        self.configurationValue = configuration
        self.sourcesByItemID = sourcesByItemID
        self.sessionValue = UserSession(userID: "user-1", username: "tester", token: "token-1")
    }

    func currentConfiguration() async -> ServerConfiguration? { configurationValue }
    func currentSession() async -> UserSession? { sessionValue }
    func configure(server: ServerConfiguration) async throws { _ = server }
    func testConnection(serverURL: URL) async throws { _ = serverURL }
    func authenticate(credentials: UserCredentials) async throws -> UserSession { _ = credentials; return sessionValue }
    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { nil }
    func fetchUserViews() async throws -> [LibraryView] { [] }
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed { _ = since; return .empty }
    func fetchItem(id: String) async throws -> MediaItem { throw AppError.network("Not implemented") }
    func fetchItemDetail(id: String) async throws -> MediaDetail { throw AppError.network("Not implemented") }
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { [] }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? { nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { _ = query; return [] }
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] { sourcesByItemID[itemID] ?? [] }

    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] {
        requestedOptions.append(options)
        return try await fetchPlaybackSources(itemID: itemID)
    }

    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? {
        _ = itemID
        _ = type
        _ = width
        _ = quality
        return nil
    }

    func prefetchImages(for items: [MediaItem]) async { _ = items }
    func reportPlayback(progress: PlaybackProgressUpdate) async throws { _ = progress }
    func reportPlayed(itemID: String) async throws { _ = itemID }
    func setPlayedState(itemID: String, isPlayed: Bool) async throws { _ = itemID; _ = isPlayed }
    func setFavorite(itemID: String, isFavorite: Bool) async throws { _ = itemID; _ = isFavorite }
}
