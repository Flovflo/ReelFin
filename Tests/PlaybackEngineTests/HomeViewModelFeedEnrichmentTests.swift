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

    func testLoadPrefersLocalPlaybackQualityWithoutWarmupWhenDuplicateCandidatesShareTheSameMovie() async throws {
        let repository = MockMetadataRepository()
        let apiClient = MockJellyfinAPIClient()
        let standardCopy = MediaItem(
            id: "jurassic-world-a-standard",
            name: "Jurassic World",
            mediaType: .movie,
            year: 2015,
            runtimeTicks: Int64(124 * 60 * 10_000_000),
            libraryID: "movies-a"
        )
        let dolbyVisionCopy = MediaItem(
            id: "jurassic-world-z-dolby-vision",
            name: "Jurassic World",
            mediaType: .movie,
            year: 2015,
            runtimeTicks: Int64(124 * 60 * 10_000_000),
            libraryID: "movies-b",
            has4K: true,
            hasDolbyVision: true
        )

        try await repository.saveHomeFeed(
            HomeFeed(
                featured: [standardCopy, dolbyVisionCopy],
                rows: [
                    HomeRow(
                        kind: .recentlyReleasedMovies,
                        title: "Recently Released Movies",
                        items: [dolbyVisionCopy, standardCopy]
                    )
                ]
            )
        )

        let warmupManager = HomeFeedWarmupManagerStub()

        let viewModel = HomeViewModel(
            dependencies: makeDependencies(
                apiClient: apiClient,
                repository: repository,
                warmupManager: warmupManager
            )
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.feed.featured.map(\.id), [dolbyVisionCopy.id])
        XCTAssertEqual(viewModel.visibleRows.first?.items.map(\.id), [dolbyVisionCopy.id])
        let warmedItemIDs = await warmupManager.warmedItemIDs()
        XCTAssertEqual(warmedItemIDs, [])
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

}

private actor HomeFeedWarmupManagerStub: PlaybackWarmupManaging {
    private var warmedIDs: [String] = []

    func warm(itemID: String) async {
        warmedIDs.append(itemID)
    }

    func selection(for itemID: String) async -> PlaybackAssetSelection? {
        _ = itemID
        return nil
    }

    func warmedItemIDs() -> [String] {
        warmedIDs
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
