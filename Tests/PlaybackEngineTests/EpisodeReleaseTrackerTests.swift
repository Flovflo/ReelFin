import Shared
@testable import SyncEngine
import XCTest

final class EpisodeReleaseTrackerTests: XCTestCase {
    func testMarkSeriesFollowedSeedsCurrentNextUp() async throws {
        let repository = EpisodeReleaseStateRepository()
        let nextUpEpisode = makeEpisode(
            id: "episode-2",
            name: "The New Mission",
            seriesID: "series-1",
            seriesName: "For All Mankind",
            season: 5,
            episode: 2
        )
        let apiClient = EpisodeReleaseAPIClient(
            perSeriesNextUp: ["series-1": nextUpEpisode],
            globalNextUp: [nextUpEpisode]
        )
        let tracker = DefaultEpisodeReleaseTracker(apiClient: apiClient, repository: repository)

        await tracker.markSeriesFollowed(
            from: makeEpisode(
                id: "episode-1",
                name: "Catch Up",
                seriesID: "series-1",
                seriesName: "For All Mankind",
                season: 5,
                episode: 1
            )
        )

        let state = try await repository.fetchEpisodeReleaseState(seriesID: "series-1")
        XCTAssertEqual(state?.lastKnownNextUpEpisodeID, "episode-2")
        XCTAssertEqual(state?.lastKnownNextUpSeasonNumber, 5)
        XCTAssertEqual(state?.lastKnownNextUpEpisodeNumber, 2)
        XCTAssertNil(state?.lastNotifiedEpisodeID)
    }

    func testReconcileSeedsContinueWatchingWithoutImmediateAlert() async throws {
        let repository = EpisodeReleaseStateRepository()
        let nextUpEpisode = makeEpisode(
            id: "episode-2",
            name: "The New Mission",
            seriesID: "series-1",
            seriesName: "For All Mankind",
            season: 5,
            episode: 2
        )
        let apiClient = EpisodeReleaseAPIClient(
            perSeriesNextUp: ["series-1": nextUpEpisode],
            globalNextUp: [nextUpEpisode]
        )
        let tracker = DefaultEpisodeReleaseTracker(apiClient: apiClient, repository: repository)

        let alerts = await tracker.reconcileAfterSync(
            feed: HomeFeed(
                featured: [],
                rows: [
                    HomeRow(
                        kind: .continueWatching,
                        title: "Continue Watching",
                        items: [
                            makeEpisode(
                                id: "episode-1",
                                name: "Catch Up",
                                seriesID: "series-1",
                                seriesName: "For All Mankind",
                                season: 5,
                                episode: 1
                            )
                        ]
                    )
                ]
            )
        )

        let state = try await repository.fetchEpisodeReleaseState(seriesID: "series-1")
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertEqual(state?.lastKnownNextUpEpisodeID, "episode-2")
        XCTAssertNil(state?.lastNotifiedEpisodeID)
    }

    func testReconcileAlertsWhenTrackedSeriesGetsNewEpisodeAfterBeingCaughtUp() async throws {
        let repository = EpisodeReleaseStateRepository()
        try await repository.upsertEpisodeReleaseState(
            EpisodeReleaseState(
                seriesID: "series-1",
                seriesName: "For All Mankind",
                lastKnownNextUpEpisodeID: nil,
                lastKnownNextUpSeasonNumber: nil,
                lastKnownNextUpEpisodeNumber: nil,
                lastNotifiedEpisodeID: nil,
                updatedAt: .distantPast
            )
        )

        let nextUpEpisode = makeEpisode(
            id: "episode-2",
            name: "The New Mission",
            seriesID: "series-1",
            seriesName: "For All Mankind",
            season: 5,
            episode: 2
        )
        let apiClient = EpisodeReleaseAPIClient(
            perSeriesNextUp: ["series-1": nextUpEpisode],
            globalNextUp: [nextUpEpisode]
        )
        let tracker = DefaultEpisodeReleaseTracker(apiClient: apiClient, repository: repository)

        let alerts = await tracker.reconcileAfterSync(feed: .empty)

        let state = try await repository.fetchEpisodeReleaseState(seriesID: "series-1")
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.episodeID, "episode-2")
        XCTAssertEqual(alerts.first?.seriesName, "For All Mankind")
        XCTAssertEqual(state?.lastKnownNextUpEpisodeID, "episode-2")
        XCTAssertEqual(state?.lastNotifiedEpisodeID, "episode-2")
    }

    func testReconcileDoesNotAlertWhenNextUpChangesBetweenTwoAvailableEpisodes() async throws {
        let repository = EpisodeReleaseStateRepository()
        try await repository.upsertEpisodeReleaseState(
            EpisodeReleaseState(
                seriesID: "series-1",
                seriesName: "For All Mankind",
                lastKnownNextUpEpisodeID: "episode-2",
                lastKnownNextUpSeasonNumber: 5,
                lastKnownNextUpEpisodeNumber: 2,
                lastNotifiedEpisodeID: nil,
                updatedAt: .distantPast
            )
        )

        let nextUpEpisode = makeEpisode(
            id: "episode-3",
            name: "Already Available",
            seriesID: "series-1",
            seriesName: "For All Mankind",
            season: 5,
            episode: 3
        )
        let apiClient = EpisodeReleaseAPIClient(
            perSeriesNextUp: ["series-1": nextUpEpisode],
            globalNextUp: [nextUpEpisode]
        )
        let tracker = DefaultEpisodeReleaseTracker(apiClient: apiClient, repository: repository)

        let alerts = await tracker.reconcileAfterSync(feed: .empty)

        let state = try await repository.fetchEpisodeReleaseState(seriesID: "series-1")
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertEqual(state?.lastKnownNextUpEpisodeID, "episode-3")
        XCTAssertNil(state?.lastNotifiedEpisodeID)
    }

    private func makeEpisode(
        id: String,
        name: String,
        seriesID: String,
        seriesName: String,
        season: Int,
        episode: Int
    ) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            mediaType: .episode,
            parentID: seriesID,
            seriesName: seriesName,
            indexNumber: episode,
            parentIndexNumber: season
        )
    }
}

private actor EpisodeReleaseStateRepository: MetadataRepositoryProtocol {
    private var states: [String: EpisodeReleaseState] = [:]

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

    func upsertEpisodeReleaseState(_ state: EpisodeReleaseState) async throws {
        states[state.seriesID] = state
    }

    func fetchEpisodeReleaseState(seriesID: String) async throws -> EpisodeReleaseState? {
        states[seriesID]
    }

    func fetchEpisodeReleaseStates() async throws -> [EpisodeReleaseState] {
        Array(states.values)
    }
}

private final class EpisodeReleaseAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    let perSeriesNextUp: [String: MediaItem]
    let globalNextUp: [MediaItem]

    init(perSeriesNextUp: [String: MediaItem], globalNextUp: [MediaItem]) {
        self.perSeriesNextUp = perSeriesNextUp
        self.globalNextUp = globalNextUp
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
    func fetchNextUpEpisodes(limit: Int) async throws -> [MediaItem] { Array(globalNextUp.prefix(limit)) }
    func fetchItem(id: String) async throws -> MediaItem { throw AppError.unknown }
    func fetchItemDetail(id: String) async throws -> MediaDetail { throw AppError.unknown }
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { [] }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? { perSeriesNextUp[seriesID] }
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
