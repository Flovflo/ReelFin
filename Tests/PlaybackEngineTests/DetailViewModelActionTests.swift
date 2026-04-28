import JellyfinAPI
import PlaybackEngine
@testable import ReelFinUI
import Shared
import XCTest

@MainActor
final class DetailViewModelActionTests: XCTestCase {
    func testToggleWatchedMarksMovieAsPlayedAndCallsAPI() async {
        let apiClient = DetailActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let item = MediaItem(
            id: "movie-1",
            name: "Movie",
            mediaType: .movie,
            runtimeTicks: Int64(100 * 60 * 10_000_000),
            libraryID: "movies",
            isPlayed: false,
            playbackPositionTicks: Int64(25 * 60 * 10_000_000)
        )

        let viewModel = DetailViewModel(
            item: item,
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        viewModel.toggleWatched()

        XCTAssertTrue(viewModel.isWatched)
        XCTAssertTrue(viewModel.detail.item.isPlayed)
        let didRecordPlayedCall = await waitForPlayedCallCount(1, in: apiClient, timeout: 2)
        XCTAssertTrue(didRecordPlayedCall)

        let playedCalls = await apiClient.playedCalls()
        XCTAssertEqual(playedCalls.first?.itemID, "movie-1")
        XCTAssertEqual(playedCalls.first?.isPlayed, true)
    }

    func testToggleWatchedClearsLocalStoppedProgress() async {
        let apiClient = DetailActionSpyAPIClient()
        let repository = DetailActionMetadataRepository(
            localProgress: PlaybackProgress(
                itemID: "movie-progress",
                positionTicks: Int64(19 * 60 * 10_000_000),
                totalTicks: Int64(90 * 60 * 10_000_000),
                updatedAt: Date()
            )
        )
        let item = MediaItem(
            id: "movie-progress",
            name: "Movie",
            mediaType: .movie,
            runtimeTicks: Int64(90 * 60 * 10_000_000),
            libraryID: "movies",
            isPlayed: false
        )
        let viewModel = DetailViewModel(
            item: item,
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        viewModel.toggleWatched()

        let didClearProgress = await waitForStoredProgressPosition(
            0,
            itemID: "movie-progress",
            in: repository,
            timeout: 2
        )
        XCTAssertTrue(didClearProgress)
    }

    func testToggleWatchlistMarksMovieAsLikedAndCallsAPI() async {
        let apiClient = DetailActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let item = MediaItem(
            id: "movie-2",
            name: "Movie",
            mediaType: .movie,
            libraryID: "movies",
            isFavorite: false
        )

        let viewModel = DetailViewModel(
            item: item,
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        viewModel.toggleWatchlist()

        XCTAssertTrue(viewModel.isInWatchlist)
        XCTAssertTrue(viewModel.detail.item.isFavorite)
        let didRecordFavoriteCall = await waitForFavoriteCallCount(1, in: apiClient, timeout: 2)
        XCTAssertTrue(didRecordFavoriteCall)

        let favoriteCalls = await apiClient.favoriteCalls()
        XCTAssertEqual(favoriteCalls.first?.itemID, "movie-2")
        XCTAssertEqual(favoriteCalls.first?.isFavorite, true)
    }

    func testLoadUsesServerResumeWhenLocalProgressIsEarlier() async {
        let serverPositionTicks = Int64(10 * 60 * 10_000_000)
        let apiClient = DetailActionSpyAPIClient()
        let repository = DetailActionMetadataRepository(
            localProgress: PlaybackProgress(
                itemID: "movie-3",
                positionTicks: Int64(11.4 * 10_000_000),
                totalTicks: Int64(90 * 60 * 10_000_000),
                updatedAt: Date()
            )
        )
        let item = MediaItem(
            id: "movie-3",
            name: "Movie",
            mediaType: .movie,
            runtimeTicks: Int64(90 * 60 * 10_000_000),
            isPlayed: false,
            playbackPositionTicks: serverPositionTicks
        )

        let viewModel = DetailViewModel(
            item: item,
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.playbackProgress?.positionTicks, serverPositionTicks)
        XCTAssertEqual(viewModel.playbackStatusText, "Stopped at 10m")
        XCTAssertEqual(viewModel.playButtonLabel, "Resume")
    }

    func testPrimaryPlayActionStartsFromBeginningWhenResumeIsHidden() async {
        let apiClient = DetailActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let item = MediaItem(
            id: "movie-play",
            name: "Movie",
            mediaType: .movie,
            runtimeTicks: Int64(90 * 60 * 10_000_000),
            isPlayed: true,
            playbackPositionTicks: Int64(26 * 60 * 10_000_000)
        )
        let viewModel = DetailViewModel(
            item: item,
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        await viewModel.load()

        XCTAssertFalse(viewModel.shouldShowResume)
        XCTAssertEqual(viewModel.playButtonLabel, "Play")
        XCTAssertEqual(viewModel.primaryPlayButtonLabel, "Play Again")
        XCTAssertEqual(viewModel.primaryPlaybackStartPosition, .beginning)
    }

    func testLoadUsesLocalStoppedProgressForPlayedItem() async {
        let localPositionTicks = Int64(17 * 60 * 10_000_000)
        let apiClient = DetailActionSpyAPIClient()
        let repository = DetailActionMetadataRepository(
            localProgress: PlaybackProgress(
                itemID: "movie-rewatch",
                positionTicks: localPositionTicks,
                totalTicks: Int64(90 * 60 * 10_000_000),
                updatedAt: Date()
            )
        )
        let item = MediaItem(
            id: "movie-rewatch",
            name: "Movie",
            mediaType: .movie,
            runtimeTicks: Int64(90 * 60 * 10_000_000),
            isPlayed: true,
            playbackPositionTicks: nil
        )
        let viewModel = DetailViewModel(
            item: item,
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.shouldShowResume)
        XCTAssertEqual(viewModel.playbackProgress?.positionTicks, localPositionTicks)
        XCTAssertEqual(viewModel.playbackStatusText, "Stopped at 17m")
        XCTAssertEqual(viewModel.playButtonLabel, "Resume")
        XCTAssertEqual(viewModel.primaryPlayButtonLabel, "Resume")
        XCTAssertFalse(viewModel.primaryPlaybackItemIsWatched)
        XCTAssertEqual(viewModel.primaryPlaybackStartPosition, .resumeIfAvailable)
    }

    func testStoppedPlaybackProgressUpdatesPrimaryActionWithoutReload() {
        let apiClient = DetailActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let item = MediaItem(
            id: "movie-return",
            name: "Movie",
            mediaType: .movie,
            runtimeTicks: Int64(90 * 60 * 10_000_000),
            isPlayed: true
        )
        let viewModel = DetailViewModel(
            item: item,
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        viewModel.applyStoppedPlaybackProgress(
            PlaybackProgress(
                itemID: "movie-return",
                positionTicks: Int64(21 * 60 * 10_000_000),
                totalTicks: Int64(90 * 60 * 10_000_000),
                updatedAt: Date()
            )
        )

        XCTAssertTrue(viewModel.shouldShowResume)
        XCTAssertEqual(viewModel.playbackStatusText, "Stopped at 21m")
        XCTAssertEqual(viewModel.primaryPlayButtonLabel, "Resume")
        XCTAssertFalse(viewModel.primaryPlaybackItemIsWatched)
    }

    func testBackgroundWarmupDoesNotShowBlockingPlaybackPreparation() {
        XCTAssertFalse(
            DetailView.showsBlockingPlaybackPreparation(
                isLoadingPlayback: false,
                isBackgroundWarmingPlayback: true
            )
        )
    }

    func testExplicitPlaybackLoadShowsBlockingPlaybackPreparation() {
        XCTAssertTrue(
            DetailView.showsBlockingPlaybackPreparation(
                isLoadingPlayback: true,
                isBackgroundWarmingPlayback: false
            )
        )
    }

    func testRemoteProgressiveDirectPlayWarmupDoesNotMarkReadyWithoutConsumableEvidence() async {
        let apiClient = DetailActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let warmupManager = EpisodeWarmupManager(
            delayByItemID: [:],
            selectionByItemID: [
                "movie-cache": makeSelection(
                    sourceID: "source-cache",
                    itemID: "movie-cache",
                    assetExtension: "mp4",
                    bitrate: 22_000_000
                )
            ]
        )
        let item = MediaItem(
            id: "movie-cache",
            name: "Movie",
            mediaType: .movie,
            runtimeTicks: Int64(90 * 60 * 10_000_000),
            playbackPositionTicks: Int64(10 * 60 * 10_000_000)
        )
        let viewModel = DetailViewModel(
            item: item,
            dependencies: makeDependencies(
                apiClient: apiClient,
                repository: repository,
                warmupManager: warmupManager
            )
        )

        await viewModel.load()

        let didResolveSelection = await waitForCondition(timeout: 2) {
            viewModel.preferredPlaybackSource?.id == "source-cache"
        }

        XCTAssertTrue(didResolveSelection)
        XCTAssertFalse(viewModel.isPlaybackWarm)
        XCTAssertNotEqual(viewModel.playbackStatusText, "Ready to play")
    }

    func testHighBitrateProgressiveDirectPlayWarmupMarksReadyFromRangePreheat() async {
        let apiClient = DetailActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let warmupManager = EpisodeWarmupManager(
            delayByItemID: [:],
            selectionByItemID: [
                "movie-ready": makeSelection(
                    sourceID: "source-ready",
                    itemID: "movie-ready",
                    assetExtension: "mp4",
                    bitrate: 22_000_000
                )
            ],
            startupPreheatByItemID: [
                "movie-ready": PlaybackStartupPreheater.Result(
                    byteCount: 4_194_304,
                    elapsedSeconds: 0.5,
                    observedBitrate: 67_108_864,
                    rangeStart: 0,
                    reason: "directplay_range"
                )
            ]
        )
        let item = MediaItem(
            id: "movie-ready",
            name: "Movie",
            mediaType: .movie,
            runtimeTicks: Int64(90 * 60 * 10_000_000),
            playbackPositionTicks: Int64(10 * 60 * 10_000_000)
        )
        let viewModel = DetailViewModel(
            item: item,
            dependencies: makeDependencies(
                apiClient: apiClient,
                repository: repository,
                warmupManager: warmupManager
            )
        )

        await viewModel.load()

        let didResolveSelection = await waitForCondition(timeout: 2) {
            viewModel.preferredPlaybackSource?.id == "source-ready"
        }

        XCTAssertTrue(didResolveSelection)
        XCTAssertTrue(viewModel.isPlaybackWarm)
        XCTAssertEqual(viewModel.loadPhase, .playbackWarm)
        XCTAssertEqual(viewModel.playbackStatusText, "Ready to play")
    }

    func testPrepareEpisodePlaybackLatestWinsAcrossWarmupSignals() async {
        let apiClient = DetailActionSpyAPIClient()
        let repository = EpisodeProgressRepository(
            progressByItemID: [
                "episode-1": PlaybackProgress(
                    itemID: "episode-1",
                    positionTicks: 10 * 10_000_000,
                    totalTicks: 40 * 10_000_000,
                    updatedAt: Date(timeIntervalSince1970: 1)
                ),
                "episode-2": PlaybackProgress(
                    itemID: "episode-2",
                    positionTicks: 20 * 10_000_000,
                    totalTicks: 40 * 10_000_000,
                    updatedAt: Date(timeIntervalSince1970: 2)
                )
            ],
            delayByItemID: [
                "episode-1": 150_000_000,
                "episode-2": 10_000_000
            ]
        )
        let warmupManager = EpisodeWarmupManager(
            delayByItemID: [
                "episode-1": 150_000_000,
                "episode-2": 10_000_000
            ],
            selectionByItemID: [
                "episode-1": makeSelection(sourceID: "source-1", itemID: "episode-1"),
                "episode-2": makeSelection(sourceID: "source-2", itemID: "episode-2")
            ]
        )
        let series = MediaItem(id: "series-1", name: "Series", mediaType: .series)
        let episode1 = MediaItem(id: "episode-1", name: "Episode 1", mediaType: .episode, parentID: "series-1")
        let episode2 = MediaItem(id: "episode-2", name: "Episode 2", mediaType: .episode, parentID: "series-1")

        let viewModel = DetailViewModel(
            item: series,
            dependencies: makeDependencies(
                apiClient: apiClient,
                repository: repository,
                warmupManager: warmupManager
            )
        )

        viewModel.prepareEpisodePlayback(episode1)
        viewModel.prepareEpisodePlayback(episode2)

        let didSettle = await waitForCondition(timeout: 2) {
            viewModel.playbackProgress?.itemID == "episode-2"
                && viewModel.preferredPlaybackSource?.id == "source-2"
        }

        XCTAssertTrue(didSettle)
        XCTAssertEqual(viewModel.playbackProgress?.itemID, "episode-2")
        XCTAssertEqual(viewModel.playbackProgress?.positionTicks, 20 * 10_000_000)
        XCTAssertEqual(viewModel.preferredPlaybackSource?.id, "source-2")
    }

    func testLoadWarmsServerNextUpEpisodeFromMatchingSeason() async {
        let season1 = MediaItem(id: "season-1", name: "Season 1", mediaType: .season, indexNumber: 1)
        let season5 = MediaItem(id: "season-5", name: "Season 5", mediaType: .season, indexNumber: 5)
        let s1e1 = MediaItem(
            id: "s1e1",
            name: "Pilot",
            mediaType: .episode,
            runtimeTicks: 1_800 * 10_000_000,
            parentID: "series-1",
            indexNumber: 1,
            parentIndexNumber: 1
        )
        let s5e2 = MediaItem(
            id: "s5e2",
            name: "The Current One",
            mediaType: .episode,
            runtimeTicks: 1_800 * 10_000_000,
            parentID: "series-1",
            indexNumber: 2,
            parentIndexNumber: 5,
            playbackPositionTicks: 300 * 10_000_000
        )
        let apiClient = DetailActionSpyAPIClient(
            seasonsBySeriesID: ["series-1": [season1, season5]],
            episodesBySeasonID: [
                "season-1": [s1e1],
                "season-5": [s5e2]
            ],
            nextUpBySeriesID: ["series-1": s5e2]
        )
        let warmupManager = EpisodeWarmupManager(
            delayByItemID: [:],
            selectionByItemID: [
                "s5e2": makeSelection(sourceID: "source-s5e2", itemID: "s5e2")
            ]
        )
        let viewModel = DetailViewModel(
            item: MediaItem(id: "series-1", name: "Series", mediaType: .series),
            dependencies: makeDependencies(
                apiClient: apiClient,
                repository: MockMetadataRepository(),
                warmupManager: warmupManager
            )
        )

        await viewModel.load()

        let didWarmNextUp = await waitForCondition(timeout: 2) {
            viewModel.selectedSeason?.id == "season-5"
                && viewModel.nextUpEpisode?.id == "s5e2"
                && viewModel.isPlaybackWarm
        }
        let warmupRequests = await warmupManager.startupWarmupRequests()

        XCTAssertTrue(didWarmNextUp)
        XCTAssertEqual(viewModel.playButtonLabel, "Resume S5 E2")
        XCTAssertEqual(warmupRequests.last?.itemID, "s5e2")
        XCTAssertEqual(warmupRequests.last?.resumeSeconds, 300)
        XCTAssertEqual(warmupRequests.last?.runtimeSeconds, 1_800)
    }

    func testSetEpisodeWatchedMarksOnlyTargetEpisodeAndAdvancesNextUp() async {
        let apiClient = DetailActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let episode1 = MediaItem(
            id: "episode-1",
            name: "Episode 1",
            mediaType: .episode,
            parentID: "series-1",
            indexNumber: 1,
            parentIndexNumber: 1
        )
        let episode2 = MediaItem(
            id: "episode-2",
            name: "Episode 2",
            mediaType: .episode,
            parentID: "series-1",
            indexNumber: 2,
            parentIndexNumber: 1
        )
        let viewModel = DetailViewModel(
            item: MediaItem(id: "series-1", name: "Series", mediaType: .series),
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )
        viewModel.episodes = [episode1, episode2]
        viewModel.nextUpEpisode = episode1

        viewModel.setEpisodeWatched(episode1, isPlayed: true)

        XCTAssertTrue(viewModel.episodes[0].isPlayed)
        XCTAssertFalse(viewModel.episodes[1].isPlayed)
        XCTAssertEqual(viewModel.nextUpEpisode?.id, "episode-2")
        let didRecordPlayedCall = await waitForPlayedCallCount(1, in: apiClient, timeout: 2)
        XCTAssertTrue(didRecordPlayedCall)

        let playedCalls = await apiClient.playedCalls()
        XCTAssertEqual(playedCalls.first?.itemID, "episode-1")
        XCTAssertEqual(playedCalls.first?.isPlayed, true)
    }

    func testSetEpisodeUnwatchedPromotesTargetEpisodeToNextUp() async {
        let apiClient = DetailActionSpyAPIClient()
        let repository = MockMetadataRepository()
        let episode1 = MediaItem(
            id: "episode-1",
            name: "Episode 1",
            mediaType: .episode,
            parentID: "series-1",
            indexNumber: 1,
            parentIndexNumber: 1,
            isPlayed: true
        )
        let episode2 = MediaItem(
            id: "episode-2",
            name: "Episode 2",
            mediaType: .episode,
            parentID: "series-1",
            indexNumber: 2,
            parentIndexNumber: 1
        )
        let viewModel = DetailViewModel(
            item: MediaItem(id: "series-1", name: "Series", mediaType: .series),
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )
        viewModel.episodes = [episode1, episode2]
        viewModel.nextUpEpisode = episode2

        viewModel.setEpisodeWatched(episode1, isPlayed: false)

        XCTAssertFalse(viewModel.episodes[0].isPlayed)
        XCTAssertEqual(viewModel.nextUpEpisode?.id, "episode-1")
        let didRecordPlayedCall = await waitForPlayedCallCount(1, in: apiClient, timeout: 2)
        XCTAssertTrue(didRecordPlayedCall)

        let playedCalls = await apiClient.playedCalls()
        XCTAssertEqual(playedCalls.first?.itemID, "episode-1")
        XCTAssertEqual(playedCalls.first?.isPlayed, false)
    }

    private func makeDependencies(
        apiClient: DetailActionSpyAPIClient,
        repository: any MetadataRepositoryProtocol,
        warmupManager: (any PlaybackWarmupManaging)? = nil
    ) -> ReelFinDependencies {
        let detailRepository = DefaultMediaDetailRepository(
            apiClient: apiClient,
            repository: repository,
            itemTTL: 60,
            detailTTL: 60,
            collectionTTL: 60
        )
        let resolvedWarmupManager = warmupManager ?? PlaybackWarmupManager(apiClient: apiClient, ttl: 60)
        let notifications = NoopEpisodeReleaseNotificationManager()

        return ReelFinDependencies(
            apiClient: apiClient,
            repository: repository,
            detailRepository: detailRepository,
            imagePipeline: MockImagePipeline(),
            syncEngine: MockSyncEngine(),
            settingsStore: MockSettingsStore(),
            episodeReleaseNotificationManager: notifications,
            seriesCache: SeriesLookupCache(apiClient: apiClient),
            playbackWarmupManager: resolvedWarmupManager,
            tvFocusWarmupCoordinator: nil,
            makePlaybackSession: {
                PlaybackSessionController(
                    apiClient: apiClient,
                    repository: repository,
                    warmupManager: resolvedWarmupManager
                )
            }
        )
    }

    @MainActor
    private func waitForCondition(
        timeout: TimeInterval,
        pollInterval: UInt64 = 25_000_000,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return true
            }

            try? await Task.sleep(nanoseconds: pollInterval)
        }

        return condition()
    }

    private func makeSelection(
        sourceID: String,
        itemID: String,
        assetExtension: String = "m3u8",
        bitrate: Int? = nil
    ) -> PlaybackAssetSelection {
        let assetURL = URL(string: "https://example.com/\(sourceID).\(assetExtension)")!
        let source = MediaSource(
            id: sourceID,
            itemID: itemID,
            name: sourceID,
            bitrate: bitrate,
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directPlayURL: assetURL
        )

        return PlaybackAssetSelection(
            source: source,
            decision: PlaybackDecision(sourceID: sourceID, route: .directPlay(assetURL)),
            assetURL: assetURL,
            headers: [:],
            debugInfo: PlaybackDebugInfo(
                container: "mp4",
                videoCodec: "h264",
                videoBitDepth: nil,
                hdrMode: .sdr,
                audioMode: "Stereo",
                bitrate: nil,
                playMethod: "DirectPlay"
            )
        )
    }

    private func waitForPlayedCallCount(
        _ expectedCount: Int,
        in apiClient: DetailActionSpyAPIClient,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await apiClient.playedCalls().count == expectedCount {
                return true
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return await apiClient.playedCalls().count == expectedCount
    }

    private func waitForFavoriteCallCount(
        _ expectedCount: Int,
        in apiClient: DetailActionSpyAPIClient,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await apiClient.favoriteCalls().count == expectedCount {
                return true
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return await apiClient.favoriteCalls().count == expectedCount
    }

    private func waitForStoredProgressPosition(
        _ expectedPositionTicks: Int64,
        itemID: String,
        in repository: DetailActionMetadataRepository,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let progress = try? await repository.fetchPlaybackProgress(itemID: itemID)
            if progress?.positionTicks == expectedPositionTicks {
                return true
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        let progress = try? await repository.fetchPlaybackProgress(itemID: itemID)
        return progress?.positionTicks == expectedPositionTicks
    }
}

    private actor DetailActionMetadataRepository: MetadataRepositoryProtocol {
        private var localProgress: PlaybackProgress?

    init(localProgress: PlaybackProgress?) {
        self.localProgress = localProgress
    }

    func saveLibraryViews(_ views: [Shared.LibraryView]) async throws { _ = views }
    func fetchLibraryViews() async throws -> [Shared.LibraryView] { [] }
    func saveHomeFeed(_ feed: HomeFeed) async throws { _ = feed }
    func fetchHomeFeed() async throws -> HomeFeed { .empty }
    func upsertItems(_ items: [MediaItem]) async throws { _ = items }
    func fetchItem(id: String) async throws -> MediaItem? { _ = id; return nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { _ = query; return [] }
    func searchItems(query: String, limit: Int) async throws -> [MediaItem] { _ = query; _ = limit; return [] }
    func savePlaybackProgress(_ progress: PlaybackProgress) async throws { localProgress = progress }

    func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? {
        guard localProgress?.itemID == itemID else { return nil }
        return localProgress
    }

        func fetchLastSyncDate() async throws -> Date? { nil }
        func setLastSyncDate(_ date: Date) async throws { _ = date }
        func upsertEpisodeReleaseState(_ state: EpisodeReleaseState) async throws { _ = state }
        func fetchEpisodeReleaseState(seriesID: String) async throws -> EpisodeReleaseState? { _ = seriesID; return nil }
        func fetchEpisodeReleaseStates() async throws -> [EpisodeReleaseState] { [] }
    }

    private actor EpisodeProgressRepository: MetadataRepositoryProtocol {
        private let progressByItemID: [String: PlaybackProgress]
        private let delayByItemID: [String: UInt64]

        init(progressByItemID: [String: PlaybackProgress], delayByItemID: [String: UInt64]) {
            self.progressByItemID = progressByItemID
            self.delayByItemID = delayByItemID
        }

        func saveLibraryViews(_ views: [Shared.LibraryView]) async throws { _ = views }
        func fetchLibraryViews() async throws -> [Shared.LibraryView] { [] }
        func saveHomeFeed(_ feed: HomeFeed) async throws { _ = feed }
        func fetchHomeFeed() async throws -> HomeFeed { .empty }
        func upsertItems(_ items: [MediaItem]) async throws { _ = items }
        func fetchItem(id: String) async throws -> MediaItem? { _ = id; return nil }
        func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { _ = query; return [] }
        func searchItems(query: String, limit: Int) async throws -> [MediaItem] { _ = query; _ = limit; return [] }

        func savePlaybackProgress(_ progress: PlaybackProgress) async throws { _ = progress }

        func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? {
            if let delay = delayByItemID[itemID] {
                try? await Task.sleep(nanoseconds: delay)
            }
            return progressByItemID[itemID]
        }

        func fetchLastSyncDate() async throws -> Date? { nil }
        func setLastSyncDate(_ date: Date) async throws { _ = date }
        func upsertEpisodeReleaseState(_ state: EpisodeReleaseState) async throws { _ = state }
        func fetchEpisodeReleaseState(seriesID: String) async throws -> EpisodeReleaseState? { _ = seriesID; return nil }
        func fetchEpisodeReleaseStates() async throws -> [EpisodeReleaseState] { [] }
    }

    private actor EpisodeWarmupManager: PlaybackWarmupManaging {
        struct StartupWarmupRequest: Equatable {
            let itemID: String
            let resumeSeconds: Double
            let runtimeSeconds: Double?
            let isTVOS: Bool
        }

        private let delayByItemID: [String: UInt64]
        private let selectionByItemID: [String: PlaybackAssetSelection]
        private let startupPreheatByItemID: [String: PlaybackStartupPreheater.Result]
        private var startupRequests: [StartupWarmupRequest] = []

        init(
            delayByItemID: [String: UInt64],
            selectionByItemID: [String: PlaybackAssetSelection],
            startupPreheatByItemID: [String: PlaybackStartupPreheater.Result] = [:]
        ) {
            self.delayByItemID = delayByItemID
            self.selectionByItemID = selectionByItemID
            self.startupPreheatByItemID = startupPreheatByItemID
        }

        func warm(itemID: String) async {
            if let delay = delayByItemID[itemID] {
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        func warm(itemID: String, resumeSeconds: Double, runtimeSeconds: Double?, isTVOS: Bool) async {
            startupRequests.append(
                StartupWarmupRequest(
                    itemID: itemID,
                    resumeSeconds: resumeSeconds,
                    runtimeSeconds: runtimeSeconds,
                    isTVOS: isTVOS
                )
            )
            await warm(itemID: itemID)
        }

        func selection(for itemID: String) async -> PlaybackAssetSelection? {
            selectionByItemID[itemID]
        }

        func startupPreheatResult(
            for itemID: String,
            resumeSeconds: Double,
            runtimeSeconds: Double?,
            isTVOS: Bool
        ) async -> PlaybackStartupPreheater.Result? {
            _ = resumeSeconds
            _ = runtimeSeconds
            _ = isTVOS
            return startupPreheatByItemID[itemID]
        }

        func startupPreheatResult(
            for selection: PlaybackAssetSelection,
            resumeSeconds: Double,
            runtimeSeconds: Double?,
            isTVOS: Bool
        ) async -> PlaybackStartupPreheater.Result? {
            await startupPreheatResult(
                for: selection.source.itemID,
                resumeSeconds: resumeSeconds,
                runtimeSeconds: runtimeSeconds,
                isTVOS: isTVOS
            )
        }

        func startupWarmupRequests() -> [StartupWarmupRequest] {
            startupRequests
        }

        func cancel(itemID: String) async { _ = itemID }
        func trim(keeping itemIDs: [String]) async { _ = itemIDs }
        func invalidate(itemID: String) async { _ = itemID }
    }

    private actor DetailActionSpyAPIClient: JellyfinAPIClientProtocol {
    private let seasonsBySeriesID: [String: [MediaItem]]
    private let episodesBySeasonID: [String: [MediaItem]]
    private let nextUpBySeriesID: [String: MediaItem]
    private var recordedPlayedCalls: [(itemID: String, isPlayed: Bool)] = []
    private var recordedFavoriteCalls: [(itemID: String, isFavorite: Bool)] = []

    init(
        seasonsBySeriesID: [String: [MediaItem]] = [:],
        episodesBySeasonID: [String: [MediaItem]] = [:],
        nextUpBySeriesID: [String: MediaItem] = [:]
    ) {
        self.seasonsBySeriesID = seasonsBySeriesID
        self.episodesBySeasonID = episodesBySeasonID
        self.nextUpBySeriesID = nextUpBySeriesID
    }

    func currentConfiguration() async -> ServerConfiguration? { nil }
    func currentSession() async -> UserSession? { nil }
    func configure(server: ServerConfiguration) async throws { _ = server }
    func testConnection(serverURL: URL) async throws { _ = serverURL }
    func authenticate(credentials: UserCredentials) async throws -> UserSession { _ = credentials; throw AppError.unknown }
    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { nil }
    func fetchUserViews() async throws -> [Shared.LibraryView] { [] }
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed { _ = since; return .empty }
    func fetchItem(id: String) async throws -> MediaItem {
        if seasonsBySeriesID[id] != nil {
            return MediaItem(id: id, name: id, mediaType: .series)
        }
        return MediaItem(id: id, name: id)
    }
    func fetchItemDetail(id: String) async throws -> MediaDetail {
        MediaDetail(item: try await fetchItem(id: id))
    }
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] {
        seasonsBySeriesID[seriesID] ?? []
    }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] {
        _ = seriesID
        return episodesBySeasonID[seasonID] ?? []
    }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? {
        nextUpBySeriesID[seriesID]
    }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { _ = query; return [] }
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] { _ = itemID; return [] }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? {
        _ = itemID
        _ = type
        _ = width
        _ = quality
        return nil
    }
    func reportPlayback(progress: PlaybackProgressUpdate) async throws { _ = progress }
    func reportPlayed(itemID: String) async throws { _ = itemID }
    func setPlayedState(itemID: String, isPlayed: Bool) async throws {
        recordedPlayedCalls.append((itemID, isPlayed))
    }

    func setFavorite(itemID: String, isFavorite: Bool) async throws {
        recordedFavoriteCalls.append((itemID, isFavorite))
    }

    func playedCalls() -> [(itemID: String, isPlayed: Bool)] {
        recordedPlayedCalls
    }

    func favoriteCalls() -> [(itemID: String, isFavorite: Bool)] {
        recordedFavoriteCalls
    }
}
