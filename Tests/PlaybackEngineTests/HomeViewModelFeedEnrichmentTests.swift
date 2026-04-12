import JellyfinAPI
import PlaybackEngine
import Shared
@testable import ReelFinUI
import XCTest

@MainActor
final class HomeViewModelFeedEnrichmentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        HomeSectionPreferencesStore.reset()
    }

    override func tearDown() {
        HomeSectionPreferencesStore.reset()
        super.tearDown()
    }

    func testLoadShowsOnlySupportedHomeSections() async throws {
        let dependencies = ReelFinPreviewFactory.dependencies()
        let expectedFeed = try await dependencies.repository.fetchHomeFeed()

        let viewModel = HomeViewModel(dependencies: dependencies)
        await viewModel.load()

        XCTAssertEqual(
            expectedFeed.rows.map(\.kind),
            [.continueWatching, .recentlyReleasedMovies, .recentlyReleasedSeries, .recentlyAddedMovies, .recentlyAddedSeries]
        )
        XCTAssertEqual(
            viewModel.visibleRows.map(\.kind),
            [.continueWatching, .recentlyReleasedMovies, .recentlyReleasedSeries, .recentlyAddedMovies, .recentlyAddedSeries]
        )
        XCTAssertEqual(
            viewModel.sectionCustomizationKinds,
            [.continueWatching, .recentlyReleasedMovies, .recentlyReleasedSeries, .recentlyAddedMovies, .recentlyAddedSeries]
        )
        XCTAssertEqual(
            viewModel.visibleRows.map(\.title),
            ["Continue Watching", "Recently Released Movies", "Recently Released TV Shows", "Recently Added Movies", "Recently Added TV"]
        )
    }

    func testLoadRestoresHiddenSectionsFromPersistedPreferences() async throws {
        HomeSectionPreferencesStore.save(
            HomeSectionPreferences(
                orderedKinds: HomeViewModel.defaultSectionOrder,
                hiddenKinds: [.recentlyReleasedSeries, .recentlyAddedSeries]
            )
        )

        let viewModel = HomeViewModel(dependencies: ReelFinPreviewFactory.dependencies())
        await viewModel.load()

        XCTAssertFalse(viewModel.isSectionVisible(.recentlyReleasedSeries))
        XCTAssertFalse(viewModel.isSectionVisible(.recentlyAddedSeries))
        XCTAssertEqual(
            viewModel.visibleRows.map(\.kind),
            [.continueWatching, .recentlyReleasedMovies, .recentlyAddedMovies]
        )
    }

    func testLoadDeduplicatesRepeatedItemsWithinFeaturedAndRows() async throws {
        let dependencies = ReelFinPreviewFactory.dependencies()
        let repeated = MediaItem(id: "jurassic-world", name: "Jurassic World", mediaType: .movie, libraryID: "movies")
        let neighbor = MediaItem(id: "neighbor", name: "Neighbor", mediaType: .movie, libraryID: "movies")

        try await dependencies.repository.saveHomeFeed(
            HomeFeed(
                featured: [repeated, repeated, neighbor],
                rows: [
                    HomeRow(
                        kind: .recentlyReleasedMovies,
                        title: "Recently Released Movies",
                        items: [repeated, neighbor, repeated]
                    )
                ]
            )
        )

        let viewModel = HomeViewModel(dependencies: dependencies)
        await viewModel.load()

        XCTAssertEqual(viewModel.feed.featured.map(\.id), ["jurassic-world", "neighbor"])
        XCTAssertEqual(viewModel.visibleRows.map(\.kind), [.recentlyReleasedMovies])
        XCTAssertEqual(viewModel.visibleRows.first?.items.map(\.id), ["jurassic-world", "neighbor"])
        XCTAssertEqual(viewModel.rowIDByItemID["jurassic-world"], viewModel.visibleRows.first?.id)
    }

    func testLoadPrefersAppleOptimizedSourceWhenDuplicateCandidatesShareTheSameMovie() async throws {
        let repository = MockMetadataRepository()
        let apiClient = MockJellyfinAPIClient()
        let serverPrepared = MediaItem(
            id: "jurassic-world-server-prep",
            name: "Jurassic World",
            mediaType: .movie,
            year: 2015,
            runtimeTicks: Int64(124 * 60 * 10_000_000),
            libraryID: "movies-a"
        )
        let appleOptimized = MediaItem(
            id: "jurassic-world-apple",
            name: "Jurassic World",
            mediaType: .movie,
            year: 2015,
            runtimeTicks: Int64(124 * 60 * 10_000_000),
            libraryID: "movies-b"
        )

        try await repository.saveHomeFeed(
            HomeFeed(
                featured: [serverPrepared, appleOptimized],
                rows: [
                    HomeRow(
                        kind: .recentlyReleasedMovies,
                        title: "Recently Released Movies",
                        items: [serverPrepared, appleOptimized]
                    )
                ]
            )
        )

        let warmupManager = HomeFeedWarmupManagerStub(
            selectionsByItemID: [
                serverPrepared.id: makeSelection(
                    itemID: serverPrepared.id,
                    route: .transcode(URL(string: "https://example.com/jurassic-world-server-prep.m3u8")!)
                ),
                appleOptimized.id: makeSelection(
                    itemID: appleOptimized.id,
                    route: .directPlay(URL(string: "https://example.com/jurassic-world-apple.mp4")!)
                )
            ]
        )

        let viewModel = HomeViewModel(
            dependencies: makeDependencies(
                apiClient: apiClient,
                repository: repository,
                warmupManager: warmupManager
            )
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.feed.featured.map(\.id), [appleOptimized.id])
        XCTAssertEqual(viewModel.visibleRows.first?.items.map(\.id), [appleOptimized.id])
    }

    private func makeDependencies(
        apiClient: MockJellyfinAPIClient,
        repository: MockMetadataRepository,
        warmupManager: PlaybackWarmupManaging
    ) -> ReelFinDependencies {
        let detailRepository = DefaultMediaDetailRepository(
            apiClient: apiClient,
            repository: repository,
            itemTTL: 60,
            detailTTL: 60,
            collectionTTL: 60
        )

        return ReelFinDependencies(
            apiClient: apiClient,
            repository: repository,
            detailRepository: detailRepository,
            imagePipeline: MockImagePipeline(),
            syncEngine: MockSyncEngine(),
            settingsStore: MockSettingsStore(),
            episodeReleaseNotificationManager: NoopEpisodeReleaseNotificationManager(),
            seriesCache: SeriesLookupCache(apiClient: apiClient),
            playbackWarmupManager: warmupManager,
            tvFocusWarmupCoordinator: nil,
            makePlaybackSession: {
                PlaybackSessionController(
                    apiClient: apiClient,
                    repository: repository,
                    warmupManager: warmupManager
                )
            }
        )
    }

    private func makeSelection(itemID: String, route: PlaybackRoute) -> PlaybackAssetSelection {
        let source = MediaSource(
            id: "source-\(itemID)",
            itemID: itemID,
            name: "Example",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/\(itemID)/stream.m3u8"),
            directPlayURL: URL(string: "https://example.com/\(itemID)/direct.mp4"),
            transcodeURL: URL(string: "https://example.com/\(itemID)/transcode.m3u8")
        )

        return PlaybackAssetSelection(
            source: source,
            decision: PlaybackDecision(sourceID: source.id, route: route),
            assetURL: URL(string: "https://example.com/\(itemID)/asset")!,
            headers: [:],
            debugInfo: PlaybackDebugInfo(
                container: "mp4",
                videoCodec: "hevc",
                videoBitDepth: 10,
                hdrMode: .dolbyVision,
                audioMode: "EAC3",
                bitrate: 18_000_000,
                playMethod: "DirectPlay"
            )
        )
    }
}

private actor HomeFeedWarmupManagerStub: PlaybackWarmupManaging {
    private let selectionsByItemID: [String: PlaybackAssetSelection]

    init(selectionsByItemID: [String: PlaybackAssetSelection]) {
        self.selectionsByItemID = selectionsByItemID
    }

    func warm(itemID: String) async {
        _ = itemID
    }

    func selection(for itemID: String) async -> PlaybackAssetSelection? {
        selectionsByItemID[itemID]
    }

    func cancel(itemID: String) async {
        _ = itemID
    }

    func trim(keeping itemIDs: [String]) async {
        _ = itemIDs
    }

    func invalidate(itemID: String) async {
        _ = itemID
    }
}
