import AVFoundation
@testable import PlaybackEngine
import Shared
import XCTest

@MainActor
final class PlaybackTransportStateTests: XCTestCase {
    func testTransportStateCommitterCoalescesPendingUpdates() async {
        let committer = PlaybackTransportStateCommitter(delayNanoseconds: 20_000_000)
        let applied = expectation(description: "latest transport snapshot applied")
        var commits: [Int] = []

        committer.schedule {
            commits.append(1)
        }
        committer.schedule {
            commits.append(2)
            applied.fulfill()
        }

        await fulfillment(of: [applied], timeout: 1.0)
        XCTAssertEqual(commits, [2])
    }

    func testTransportStateIgnoresProgressTicksAndClearsOnStop() async throws {
        let controller = PlaybackSessionController(
            apiClient: TransportStateAPIClient(),
            repository: TransportStateRepository()
        )
        let suggestion = PlaybackSkipSuggestion(
            title: "Skip Intro",
            systemImageName: "forward.end.circle.fill",
            target: .seek(to: 90)
        )

        controller.activeSkipSuggestion = suggestion
        try await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertEqual(controller.transportState.activeSkipSuggestion, suggestion)
        let snapshot = controller.transportState

        controller.currentTime = 42
        try await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertEqual(controller.transportState, snapshot)

        controller.currentItemID = "episode-1"
        controller.player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: "https://example.com/video.mp4")!))
        controller.stop()

        XCTAssertEqual(controller.transportState, .empty)
    }
}

private actor TransportStateRepository: MetadataRepositoryProtocol {
    func saveLibraryViews(_ views: [LibraryView]) async throws {}
    func fetchLibraryViews() async throws -> [LibraryView] { [] }
    func saveHomeFeed(_ feed: HomeFeed) async throws {}
    func fetchHomeFeed() async throws -> HomeFeed { .empty }
    func upsertItems(_ items: [MediaItem]) async throws {}
    func fetchItem(id: String) async throws -> MediaItem? { nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { [] }
    func searchItems(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func savePlaybackProgress(_ progress: PlaybackProgress) async throws {}
    func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? { nil }
    func fetchLastSyncDate() async throws -> Date? { nil }
    func setLastSyncDate(_ date: Date) async throws {}
}

private final class TransportStateAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
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
    func fetchItem(id: String) async throws -> MediaItem { throw AppError.unknown }
    func fetchItemDetail(id: String) async throws -> MediaDetail { throw AppError.unknown }
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { [] }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? { nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { [] }
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] { [] }
    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] { [] }
    func fetchMediaSegments(itemID: String) async throws -> [MediaSegment] { [] }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? { nil }
    func prefetchImages(for items: [MediaItem]) async {}
    func reportPlayback(progress: PlaybackProgressUpdate) async throws {}
    func reportPlaybackStopped(progress: PlaybackProgressUpdate) async throws {}
    func reportPlayed(itemID: String) async throws {}
    func setPlayedState(itemID: String, isPlayed: Bool) async throws {}
    func setFavorite(itemID: String, isFavorite: Bool) async throws {}
}
