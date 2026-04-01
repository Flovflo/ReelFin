import AVFoundation
@testable import PlaybackEngine
import Shared
import XCTest

@MainActor
final class PlaybackStopReportingTests: XCTestCase {
    func testStopReportsStoppedEvenIfControllerIsReleasedImmediately() async {
        let stoppedExpectation = expectation(description: "stopped playback reported")
        let progressExpectation = expectation(description: "progress playback reported")
        let apiClient = StopReportingAPIClient(
            stoppedExpectation: stoppedExpectation,
            progressExpectation: progressExpectation
        )
        let repository = StopReportingRepository()

        var controller: PlaybackSessionController? = PlaybackSessionController(
            apiClient: apiClient,
            repository: repository
        )
        controller?.currentItemID = "episode-1"
        controller?.player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: "https://example.com/video.mp4")!))

        controller?.stop()
        controller = nil

        await fulfillment(of: [progressExpectation, stoppedExpectation], timeout: 1.0)

        XCTAssertEqual(apiClient.progressUpdates.count, 1)
        XCTAssertEqual(apiClient.stoppedUpdates.count, 1)
        XCTAssertEqual(apiClient.progressUpdates.first?.itemID, "episode-1")
        XCTAssertEqual(apiClient.stoppedUpdates.first?.itemID, "episode-1")
    }
}

private actor StopReportingRepository: MetadataRepositoryProtocol {
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

private final class StopReportingAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    let stoppedExpectation: XCTestExpectation
    let progressExpectation: XCTestExpectation
    private let lock = NSLock()

    private(set) var progressUpdates: [PlaybackProgressUpdate] = []
    private(set) var stoppedUpdates: [PlaybackProgressUpdate] = []

    init(stoppedExpectation: XCTestExpectation, progressExpectation: XCTestExpectation) {
        self.stoppedExpectation = stoppedExpectation
        self.progressExpectation = progressExpectation
    }

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

    func reportPlayback(progress: PlaybackProgressUpdate) async throws {
        lock.lock()
        progressUpdates.append(progress)
        lock.unlock()
        progressExpectation.fulfill()
    }

    func reportPlaybackStopped(progress: PlaybackProgressUpdate) async throws {
        lock.lock()
        stoppedUpdates.append(progress)
        lock.unlock()
        stoppedExpectation.fulfill()
    }

    func reportPlayed(itemID: String) async throws {}
    func setPlayedState(itemID: String, isPlayed: Bool) async throws {}
    func setFavorite(itemID: String, isFavorite: Bool) async throws {}
}
