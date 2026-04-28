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

        let progressUpdates = await apiClient.progressUpdates
        let stoppedUpdates = await apiClient.stoppedUpdates

        XCTAssertEqual(progressUpdates.count, 1)
        XCTAssertEqual(stoppedUpdates.count, 1)
        XCTAssertEqual(progressUpdates.first?.itemID, "episode-1")
        XCTAssertEqual(stoppedUpdates.first?.itemID, "episode-1")
    }

    func testStopReportsObservedDirectPlayTimeWhenAVPlayerTimeIsStillZero() async {
        let stoppedExpectation = expectation(description: "direct play stopped playback reported")
        let progressExpectation = expectation(description: "direct play progress playback reported")
        let apiClient = StopReportingAPIClient(
            stoppedExpectation: stoppedExpectation,
            progressExpectation: progressExpectation
        )
        let repository = StopReportingRepository()
        let controller = PlaybackSessionController(apiClient: apiClient, repository: repository)

        controller.currentItemID = "movie-1"
        controller.currentTime = 549.35
        controller.player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: "https://example.com/video.mp4")!))

        controller.stop()

        await fulfillment(of: [progressExpectation, stoppedExpectation], timeout: 1.0)
        let stoppedUpdates = await apiClient.stoppedUpdates
        let progressUpdates = await apiClient.progressUpdates

        XCTAssertEqual(stoppedUpdates.first?.positionTicks, 5_493_500_000)
        XCTAssertEqual(progressUpdates.first?.positionTicks, 5_493_500_000)
    }

    func testStopReturnsLocalProgressSnapshotForImmediateUIRefresh() async {
        let stoppedExpectation = expectation(description: "stopped playback reported")
        let progressExpectation = expectation(description: "progress playback reported")
        let apiClient = StopReportingAPIClient(
            stoppedExpectation: stoppedExpectation,
            progressExpectation: progressExpectation
        )
        let repository = StopReportingRepository()
        let controller = PlaybackSessionController(apiClient: apiClient, repository: repository)

        controller.currentItemID = "movie-1"
        controller.currentTime = 721.2
        controller.player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: "https://example.com/video.mp4")!))

        let progress = controller.stop()

        XCTAssertEqual(progress?.itemID, "movie-1")
        XCTAssertEqual(progress?.positionTicks, 7_212_000_000)
        await fulfillment(of: [progressExpectation, stoppedExpectation], timeout: 1.0)
    }

    func testStopReportsPendingSeekTimeBeforePeriodicObserverRuns() async {
        let stoppedExpectation = expectation(description: "pending seek stopped playback reported")
        let progressExpectation = expectation(description: "pending seek progress playback reported")
        let apiClient = StopReportingAPIClient(
            stoppedExpectation: stoppedExpectation,
            progressExpectation: progressExpectation
        )
        let repository = StopReportingRepository()
        let controller = PlaybackSessionController(apiClient: apiClient, repository: repository)

        controller.currentItemID = "movie-1"
        controller.player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: "https://example.com/video.mp4")!))

        controller.seek(to: 612.4)
        controller.stop()

        await fulfillment(of: [progressExpectation, stoppedExpectation], timeout: 1.0)
        let stoppedUpdates = await apiClient.stoppedUpdates

        XCTAssertEqual(stoppedUpdates.first?.positionTicks, 6_124_000_000)
    }

    func testPendingResumeWinsOverStartupTimeUntilSeekCompletes() {
        let position = PlaybackSessionController.resolvedProgressPositionSeconds(
            pendingPlaybackPositionOverrideSeconds: nil,
            playerAbsoluteSeconds: 3.4,
            observedSeconds: 3.4,
            lastKnownPlaybackPositionSeconds: nil,
            pendingResumeSeconds: 211.34,
            sessionInitialResumeSeconds: 211.34
        )

        XCTAssertEqual(position, 211.34, accuracy: 0.001)
    }

    func testPendingResumeDoesNotDiscardLaterObservedPlayback() {
        let position = PlaybackSessionController.resolvedProgressPositionSeconds(
            pendingPlaybackPositionOverrideSeconds: nil,
            playerAbsoluteSeconds: 260.2,
            observedSeconds: 260.2,
            lastKnownPlaybackPositionSeconds: 260.2,
            pendingResumeSeconds: 211.34,
            sessionInitialResumeSeconds: 211.34
        )

        XCTAssertEqual(position, 260.2, accuracy: 0.001)
    }

    func testFinishPlaybackMarksEpisodeSeriesAsFollowed() async {
        let apiClient = FinishPlaybackAPIClient()
        let repository = StopReportingRepository()
        let tracker = PlaybackFinishTracker()
        let controller = PlaybackSessionController(
            apiClient: apiClient,
            repository: repository,
            episodeReleaseTracker: tracker
        )

        controller.currentItemID = "episode-1"
        controller.currentMediaItem = MediaItem(
            id: "episode-1",
            name: "Pilot",
            mediaType: .episode,
            parentID: "series-1",
            seriesName: "For All Mankind",
            indexNumber: 1,
            parentIndexNumber: 5
        )
        controller.player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: "https://example.com/video.mp4")!))

        await controller.finishCurrentPlayback()

        let followedEpisodes = await tracker.followedEpisodes
        let reportedItemIDs = await apiClient.reportedItemIDs

        XCTAssertEqual(followedEpisodes.map(\.id), ["episode-1"])
        XCTAssertEqual(reportedItemIDs, ["episode-1"])
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

private actor StopReportingAPIClient: JellyfinAPIClientProtocol {
    let stoppedExpectation: XCTestExpectation
    let progressExpectation: XCTestExpectation

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
        progressUpdates.append(progress)
        progressExpectation.fulfill()
    }

    func reportPlaybackStopped(progress: PlaybackProgressUpdate) async throws {
        stoppedUpdates.append(progress)
        stoppedExpectation.fulfill()
    }

    func reportPlayed(itemID: String) async throws {}
    func setPlayedState(itemID: String, isPlayed: Bool) async throws {}
    func setFavorite(itemID: String, isFavorite: Bool) async throws {}
}

private actor PlaybackFinishTracker: EpisodeReleaseTrackingProtocol {
    private(set) var followedEpisodes: [MediaItem] = []

    func markSeriesFollowed(from episode: MediaItem) async {
        followedEpisodes.append(episode)
    }

    func reconcileAfterSync(feed: HomeFeed) async -> [EpisodeReleaseAlert] {
        _ = feed
        return []
    }
}

private actor FinishPlaybackAPIClient: JellyfinAPIClientProtocol {
    private(set) var reportedItemIDs: [String] = []

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

    func reportPlayed(itemID: String) async throws {
        reportedItemIDs.append(itemID)
    }

    func setPlayedState(itemID: String, isPlayed: Bool) async throws {}
    func setFavorite(itemID: String, isFavorite: Bool) async throws {}
}
