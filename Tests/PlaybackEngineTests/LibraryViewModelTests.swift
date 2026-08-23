import JellyfinAPI
import PlaybackEngine
@testable import ReelFinUI
import Shared
import XCTest

private typealias SharedLibraryView = Shared.LibraryView

@MainActor
final class LibraryViewModelTests: XCTestCase {
    func testManualRefreshReloadsCurrentCriteriaAndLeavesRefreshInactive() async throws {
        let initialSeries = MediaItem(
            id: "initial-series",
            name: "Initial Series",
            mediaType: .series,
            libraryID: "shows"
        )
        let refreshedSeries = MediaItem(
            id: "refreshed-series",
            name: "Refreshed Series",
            mediaType: .series,
            libraryID: "shows"
        )
        let apiClient = LibraryViewModelAPIClientStub(
            views: Self.libraryViews,
            itemsByViewID: [:],
            libraryFetchPlans: [
                .immediate([initialSeries]),
                .immediate([refreshedSeries])
            ]
        )
        let repository = LibraryViewModelRepositoryStub(views: Self.libraryViews)
        let viewModel = LibraryViewModel(
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        viewModel.selectedFilter = .series
        viewModel.sortMode = .title
        await viewModel.loadInitial()
        await viewModel.manualRefresh()

        let queries = await apiClient.recordedQueries()
        XCTAssertEqual(queries.map(\.page), [0, 0])
        XCTAssertEqual(queries.last?.mediaType, .series)
        XCTAssertEqual(queries.last?.sortBy, .sortName)
        XCTAssertFalse(queries.last?.sortDescending ?? true)
        XCTAssertEqual(viewModel.items.map(\.id), [refreshedSeries.id])
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testManualRefreshCancelsPaginationAndRejectsItsStaleResponse() async throws {
        let initialPage = Self.makeItems(
            prefix: "initial-movie",
            count: 48,
            mediaType: .movie,
            libraryID: "movies"
        )
        let stalePage = [
            MediaItem(id: "stale-page", name: "Stale Page", mediaType: .movie, libraryID: "movies")
        ]
        let refreshedPage = [
            MediaItem(id: "refreshed-page", name: "Refreshed Page", mediaType: .movie, libraryID: "movies")
        ]
        let apiClient = LibraryViewModelAPIClientStub(
            views: Self.libraryViews,
            itemsByViewID: [:],
            libraryFetchPlans: [
                .immediate(initialPage),
                .suspended,
                .suspended
            ]
        )
        let repository = LibraryViewModelRepositoryStub(views: Self.libraryViews)
        let viewModel = LibraryViewModel(
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        await viewModel.loadInitial()
        let stalePaginationTask = try XCTUnwrap(viewModel.submitPaginationIfNeeded())
        await apiClient.waitForLibraryFetchCount(2)

        let refreshTask = Task { @MainActor in
            await viewModel.manualRefresh()
        }
        await apiClient.waitForLibraryFetchCount(3)
        await apiClient.resumeLibraryFetch(at: 2, returning: refreshedPage)
        await refreshTask.value

        await apiClient.resumeLibraryFetch(at: 1, returning: stalePage)
        await stalePaginationTask.value

        XCTAssertEqual(viewModel.items.map(\.id), [refreshedPage[0].id])
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testLoadInitialAggregatesMovieLibrariesDiscoveredFromJellyfinViews() async throws {
        let apiClient = LibraryViewModelAPIClientStub(
            views: [
                SharedLibraryView(id: "movies-a", name: "Movies A", collectionType: "movies"),
                SharedLibraryView(id: "movies-b", name: "Movies B", collectionType: "movies"),
                SharedLibraryView(id: "shows-a", name: "Shows A", collectionType: "tvshows")
            ],
            itemsByViewID: [
                "movies-a": [
                    MediaItem(id: "movie-a-1", name: "Movie A 1", mediaType: .movie, year: 2025, libraryID: "movies-a")
                ],
                "movies-b": [
                    MediaItem(id: "movie-b-1", name: "Movie B 1", mediaType: .movie, year: 2024, libraryID: "movies-b")
                ],
                "shows-a": [
                    MediaItem(id: "series-a-1", name: "Series A 1", mediaType: .series, year: 2026, libraryID: "shows-a")
                ]
            ]
        )
        let repository = LibraryViewModelRepositoryStub()
        let dependencies = makeDependencies(apiClient: apiClient, repository: repository)

        let viewModel = LibraryViewModel(dependencies: dependencies)
        await viewModel.loadInitial()
        let resolvedViewIDs = await apiClient.recordedQueries().last?.resolvedViewIDs
        let savedViewIDs = await repository.recordedSavedViews().map(\.id)

        XCTAssertEqual(viewModel.items.map(\.id), ["movie-a-1", "movie-b-1"])
        XCTAssertEqual(savedViewIDs, ["movies-a", "movies-b", "shows-a"])
        XCTAssertEqual(resolvedViewIDs, ["movies-a", "movies-b"])
    }

    func testLoadInitialPrefersLocalPlaybackQualityWithoutResolvingSourcesAcrossLibraries() async throws {
        let standardCopy = MediaItem(
            id: "captain-america-a-standard",
            name: "Captain America",
            mediaType: .movie,
            year: 2011,
            runtimeTicks: Int64(124 * 60 * 10_000_000),
            libraryID: "movies-a"
        )
        let dolbyVisionCopy = MediaItem(
            id: "captain-america-z-dolby-vision",
            name: "Captain America",
            mediaType: .movie,
            year: 2011,
            runtimeTicks: Int64(124 * 60 * 10_000_000),
            libraryID: "movies-b",
            has4K: true,
            hasDolbyVision: true
        )
        let apiClient = LibraryViewModelAPIClientStub(
            views: [
                SharedLibraryView(id: "movies-a", name: "Movies A", collectionType: "movies"),
                SharedLibraryView(id: "movies-b", name: "Movies B", collectionType: "movies")
            ],
            itemsByViewID: [
                "movies-a": [standardCopy],
                "movies-b": [dolbyVisionCopy]
            ]
        )
        let repository = LibraryViewModelRepositoryStub()
        let dependencies = makeDependencies(
            apiClient: apiClient,
            repository: repository
        )

        let viewModel = LibraryViewModel(dependencies: dependencies)
        await viewModel.loadInitial()

        XCTAssertEqual(viewModel.items.map(\.id), [dolbyVisionCopy.id])
        let playbackSourceItemIDs = await apiClient.recordedPlaybackSourceItemIDs()
        XCTAssertEqual(playbackSourceItemIDs, [])
    }

    func testSearchFiltersCachedItemsToSelectedMediaTypeBeforeMergingRemoteResults() async throws {
        let cachedSeries = MediaItem(
            id: "silo-series",
            name: "Silo",
            mediaType: .series,
            year: 2023,
            libraryID: "shows"
        )
        let cachedSeason = MediaItem(
            id: "silo-season-1",
            name: "Season 1",
            mediaType: .season,
            year: 2023,
            parentID: cachedSeries.id,
            seriesName: cachedSeries.name
        )
        let cachedEpisode = MediaItem(
            id: "silo-episode-1",
            name: "La fête de la Liberté",
            mediaType: .episode,
            year: 2023,
            parentID: cachedSeries.id,
            seriesName: cachedSeries.name
        )
        let cachedMovie = MediaItem(
            id: "silo-related-movie",
            name: "Silo: The Movie",
            mediaType: .movie,
            year: 2023,
            libraryID: "movies"
        )
        let refreshedSeries = MediaItem(
            id: cachedSeries.id,
            name: cachedSeries.name,
            overview: "Remote detail",
            mediaType: .series,
            year: cachedSeries.year,
            runtimeTicks: Int64(45 * 60) * 10_000_000,
            posterTag: "remote-poster",
            libraryID: "shows"
        )
        let apiClient = LibraryViewModelAPIClientStub(
            views: Self.libraryViews,
            itemsByViewID: [:],
            libraryFetchPlans: [.immediate([refreshedSeries])]
        )
        let repository = LibraryViewModelRepositoryStub(
            views: Self.libraryViews,
            searchPlans: [.immediate([cachedEpisode, cachedSeason, cachedSeries, cachedMovie])]
        )
        let viewModel = LibraryViewModel(
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        viewModel.searchQuery = "silo"
        viewModel.selectedFilter = .series
        await viewModel.loadInitial()

        XCTAssertEqual(viewModel.items.map(\.id), [cachedSeries.id])
    }

    func testLatestCriteriaWinsWhenOlderRemoteFetchFinishesLast() async throws {
        let cachedAlpha = MediaItem(
            id: "cached-alpha",
            name: "Cached Alpha",
            mediaType: .movie,
            libraryID: "movies"
        )
        let cachedBeta = MediaItem(
            id: "cached-beta",
            name: "Cached Beta",
            mediaType: .series,
            libraryID: "shows"
        )
        let remoteAlpha = MediaItem(
            id: "remote-alpha",
            name: "Remote Alpha",
            mediaType: .movie,
            libraryID: "movies"
        )
        let remoteBeta = MediaItem(
            id: "remote-beta",
            name: "Remote Beta",
            mediaType: .series,
            libraryID: "shows"
        )
        let apiClient = LibraryViewModelAPIClientStub(
            views: [],
            itemsByViewID: [:],
            libraryFetchPlans: [
                .suspended,
                .immediate([remoteBeta])
            ]
        )
        let repository = LibraryViewModelRepositoryStub(
            views: Self.libraryViews,
            searchPlans: [
                .immediate([cachedAlpha]),
                .immediate([cachedBeta])
            ]
        )
        let viewModel = LibraryViewModel(
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        viewModel.searchQuery = "  alpha  "
        viewModel.selectedFilter = .movie
        viewModel.sortMode = .recent
        let alphaTask = viewModel.submitCriteria()
        await apiClient.waitForLibraryFetchCount(1)

        viewModel.searchQuery = " beta "
        viewModel.selectedFilter = .series
        viewModel.sortMode = .title
        let betaTask = viewModel.submitCriteria()
        await apiClient.waitForLibraryFetchCount(2)
        await betaTask.value

        XCTAssertEqual(viewModel.items.map(\.id), [cachedBeta.id, remoteBeta.id])
        let queriesBeforeAlphaFinishes = await apiClient.recordedQueries()
        XCTAssertEqual(queriesBeforeAlphaFinishes.count, 2)
        XCTAssertEqual(queriesBeforeAlphaFinishes[0].query, "alpha")
        XCTAssertEqual(queriesBeforeAlphaFinishes[0].mediaType, .movie)
        XCTAssertEqual(queriesBeforeAlphaFinishes[0].sortBy, .dateCreated)
        XCTAssertTrue(queriesBeforeAlphaFinishes[0].sortDescending)
        XCTAssertEqual(queriesBeforeAlphaFinishes[0].resolvedViewIDs, ["movies"])
        XCTAssertEqual(queriesBeforeAlphaFinishes[1].query, "beta")
        XCTAssertEqual(queriesBeforeAlphaFinishes[1].mediaType, .series)
        XCTAssertEqual(queriesBeforeAlphaFinishes[1].sortBy, .sortName)
        XCTAssertFalse(queriesBeforeAlphaFinishes[1].sortDescending)
        XCTAssertEqual(queriesBeforeAlphaFinishes[1].resolvedViewIDs, ["shows"])

        await apiClient.resumeLibraryFetch(at: 0, returning: [remoteAlpha])
        await alphaTask.value

        XCTAssertEqual(viewModel.items.map(\.id), [cachedBeta.id, remoteBeta.id])
        let upsertedBatches = await repository.recordedUpsertBatches()
        XCTAssertEqual(upsertedBatches.map { $0.map(\.id) }, [[remoteBeta.id]])
    }

    func testFilterAndSortReloadStartsWhilePreviousPaginationIsSuspended() async throws {
        let initialPage = Self.makeItems(
            prefix: "movie",
            count: 48,
            mediaType: .movie,
            libraryID: "movies"
        )
        let stalePage = [
            MediaItem(id: "stale-page", name: "Stale Page", mediaType: .movie, libraryID: "movies")
        ]
        let currentFirstPage = Self.makeItems(
            prefix: "current-series",
            count: 48,
            mediaType: .series,
            libraryID: "shows"
        )
        let currentSecondPage = [
            MediaItem(id: "current-series-48", name: "Current Series 48", mediaType: .series, libraryID: "shows")
        ]
        let apiClient = LibraryViewModelAPIClientStub(
            views: [],
            itemsByViewID: [:],
            libraryFetchPlans: [
                .immediate(initialPage),
                .suspended,
                .immediate(currentFirstPage),
                .immediate(currentSecondPage)
            ]
        )
        let repository = LibraryViewModelRepositoryStub(views: Self.libraryViews)
        let viewModel = LibraryViewModel(
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        await viewModel.submitCriteria().value
        let stalePaginationTask = try XCTUnwrap(viewModel.submitPaginationIfNeeded())
        await apiClient.waitForLibraryFetchCount(2)

        viewModel.selectedFilter = .series
        viewModel.sortMode = .title
        let currentCriteriaTask = viewModel.submitCriteria()
        await apiClient.waitForLibraryFetchCount(3)

        let queries = await apiClient.recordedQueries()
        XCTAssertEqual(queries.map(\.page), [0, 1, 0])
        XCTAssertEqual(queries[2].query, nil)
        XCTAssertEqual(queries[2].mediaType, .series)
        XCTAssertEqual(queries[2].sortBy, .sortName)
        XCTAssertFalse(queries[2].sortDescending)
        XCTAssertEqual(queries[2].resolvedViewIDs, ["shows"])

        await currentCriteriaTask.value
        await apiClient.resumeLibraryFetch(at: 1, returning: stalePage)
        await stalePaginationTask.value

        XCTAssertEqual(viewModel.items.count, currentFirstPage.count)
        XCTAssertEqual(Set(viewModel.items.map(\.id)), Set(currentFirstPage.map(\.id)))
        let currentPaginationTask = try XCTUnwrap(viewModel.submitPaginationIfNeeded())
        await apiClient.waitForLibraryFetchCount(4)
        await currentPaginationTask.value

        let finalQueries = await apiClient.recordedQueries()
        XCTAssertEqual(finalQueries.map(\.page), [0, 1, 0, 1])
        XCTAssertEqual(finalQueries[3].mediaType, .series)
        XCTAssertEqual(finalQueries[3].sortBy, .sortName)
        XCTAssertFalse(finalQueries[3].sortDescending)
        XCTAssertEqual(finalQueries[3].resolvedViewIDs, ["shows"])
        XCTAssertEqual(
            Set(viewModel.items.map(\.id)),
            Set((currentFirstPage + currentSecondPage).map(\.id))
        )
    }

    func testCancelIntentPreservesLastCommittedCachedSearchResults() async throws {
        let cachedResult = MediaItem(
            id: "cached-search",
            name: "Cached Search",
            mediaType: .movie,
            libraryID: "movies"
        )
        let staleRemoteResult = MediaItem(
            id: "stale-remote-search",
            name: "Stale Remote Search",
            mediaType: .movie,
            libraryID: "movies"
        )
        let apiClient = LibraryViewModelAPIClientStub(
            views: [],
            itemsByViewID: [:],
            libraryFetchPlans: [.suspended]
        )
        let repository = LibraryViewModelRepositoryStub(
            views: Self.libraryViews,
            searchPlans: [.immediate([cachedResult])]
        )
        let viewModel = LibraryViewModel(
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        viewModel.searchQuery = "cached"
        let searchTask = viewModel.submitCriteria()
        await apiClient.waitForLibraryFetchCount(1)
        XCTAssertEqual(viewModel.items.map(\.id), [cachedResult.id])

        viewModel.cancelIntents()
        await apiClient.resumeLibraryFetch(at: 0, returning: [staleRemoteResult])
        await searchTask.value

        XCTAssertEqual(viewModel.items.map(\.id), [cachedResult.id])
        XCTAssertFalse(viewModel.isLoadingPage)
        let upsertedBatches = await repository.recordedUpsertBatches()
        XCTAssertTrue(upsertedBatches.isEmpty)
    }

    func testIsLoadingPageTracksOnlyCurrentCriteriaGeneration() async throws {
        let initialPage = Self.makeItems(
            prefix: "movie",
            count: 48,
            mediaType: .movie,
            libraryID: "movies"
        )
        let stalePage = [
            MediaItem(id: "stale-page", name: "Stale Page", mediaType: .movie, libraryID: "movies")
        ]
        let currentPage = [
            MediaItem(id: "current-series", name: "Current Series", mediaType: .series, libraryID: "shows")
        ]
        let apiClient = LibraryViewModelAPIClientStub(
            views: [],
            itemsByViewID: [:],
            libraryFetchPlans: [
                .immediate(initialPage),
                .suspended,
                .suspended
            ]
        )
        let repository = LibraryViewModelRepositoryStub(views: Self.libraryViews)
        let viewModel = LibraryViewModel(
            dependencies: makeDependencies(apiClient: apiClient, repository: repository)
        )

        await viewModel.submitCriteria().value
        let stalePaginationTask = try XCTUnwrap(viewModel.submitPaginationIfNeeded())
        await apiClient.waitForLibraryFetchCount(2)

        viewModel.selectedFilter = .series
        viewModel.sortMode = .title
        let currentCriteriaTask = viewModel.submitCriteria()
        await apiClient.waitForLibraryFetchCount(3)
        XCTAssertTrue(viewModel.isLoadingPage)

        await apiClient.resumeLibraryFetch(at: 1, returning: stalePage)
        await stalePaginationTask.value
        XCTAssertTrue(viewModel.isLoadingPage)

        await apiClient.resumeLibraryFetch(at: 2, returning: currentPage)
        await currentCriteriaTask.value
        XCTAssertFalse(viewModel.isLoadingPage)
        XCTAssertEqual(viewModel.items.map(\.id), currentPage.map(\.id))
    }

    private static let libraryViews = [
        SharedLibraryView(id: "movies", name: "Movies", collectionType: "movies"),
        SharedLibraryView(id: "shows", name: "Shows", collectionType: "tvshows")
    ]

    private static func makeItems(
        prefix: String,
        count: Int,
        mediaType: MediaType,
        libraryID: String
    ) -> [MediaItem] {
        (0 ..< count).map { index in
            MediaItem(
                id: "\(prefix)-\(index)",
                name: "\(prefix.capitalized) \(index)",
                mediaType: mediaType,
                year: 2_100 - index,
                libraryID: libraryID
            )
        }
    }
}

private enum LibraryItemFetchPlan: Sendable {
    case immediate([MediaItem])
    case suspended
}

private actor LibraryViewModelAPIClientStub: JellyfinAPIClientProtocol {
    private let views: [SharedLibraryView]
    private let itemsByViewID: [String: [MediaItem]]
    private var libraryFetchPlans: [LibraryItemFetchPlan]
    private var queries: [LibraryQuery] = []
    private var playbackSourceItemIDs: [String] = []
    private var suspendedLibraryFetches: [Int: CheckedContinuation<[MediaItem], Never>] = [:]
    private var libraryFetchCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(
        views: [SharedLibraryView],
        itemsByViewID: [String: [MediaItem]],
        libraryFetchPlans: [LibraryItemFetchPlan] = []
    ) {
        self.views = views
        self.itemsByViewID = itemsByViewID
        self.libraryFetchPlans = libraryFetchPlans
    }

    func currentConfiguration() async -> ServerConfiguration? {
        ServerConfiguration(serverURL: URL(string: "https://example.com")!)
    }

    func currentSession() async -> UserSession? {
        UserSession(userID: "user-1", username: "Flo", token: "token-1")
    }

    func configure(server: ServerConfiguration) async throws { _ = server }
    func testConnection(serverURL: URL) async throws { _ = serverURL }
    func authenticate(credentials: UserCredentials) async throws -> UserSession { _ = credentials; throw AppError.unknown }
    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { _ = serverURL; throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { _ = secret; return nil }

    func fetchUserViews() async throws -> [SharedLibraryView] {
        views
    }

    func fetchHomeFeed(since: Date?) async throws -> HomeFeed {
        _ = since
        return .empty
    }

    func fetchNextUpEpisodes(limit: Int) async throws -> [MediaItem] {
        _ = limit
        return []
    }

    func fetchItem(id: String) async throws -> MediaItem {
        MediaItem(id: id, name: id)
    }

    func fetchItemDetail(id: String) async throws -> MediaDetail {
        MediaDetail(item: MediaItem(id: id, name: id))
    }

    func fetchSeasons(seriesID: String) async throws -> [MediaItem] {
        _ = seriesID
        return []
    }

    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] {
        _ = seriesID
        _ = seasonID
        return []
    }

    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? {
        _ = seriesID
        return nil
    }

    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        queries.append(query)
        resumeLibraryFetchCountWaiters()
        let callIndex = queries.count - 1

        if !libraryFetchPlans.isEmpty {
            switch libraryFetchPlans.removeFirst() {
            case let .immediate(items):
                return items
            case .suspended:
                return await withCheckedContinuation { continuation in
                    suspendedLibraryFetches[callIndex] = continuation
                }
            }
        }

        let viewIDs = query.resolvedViewIDs
        if viewIDs.isEmpty {
            return []
        }

        return viewIDs.flatMap { itemsByViewID[$0] ?? [] }
    }

    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] {
        playbackSourceItemIDs.append(itemID)
        return []
    }

    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? {
        _ = itemID
        _ = type
        _ = width
        _ = quality
        return nil
    }

    func prefetchImages(for items: [MediaItem]) async {
        _ = items
    }

    func reportPlayback(progress: PlaybackProgressUpdate) async throws { _ = progress }
    func reportPlaybackStopped(progress: PlaybackProgressUpdate) async throws { _ = progress }
    func reportPlayed(itemID: String) async throws { _ = itemID }
    func setPlayedState(itemID: String, isPlayed: Bool) async throws {
        _ = itemID
        _ = isPlayed
    }
    func setFavorite(itemID: String, isFavorite: Bool) async throws {
        _ = itemID
        _ = isFavorite
    }

    func recordedQueries() -> [LibraryQuery] {
        queries
    }

    func recordedPlaybackSourceItemIDs() -> [String] {
        playbackSourceItemIDs
    }

    func waitForLibraryFetchCount(_ count: Int) async {
        guard queries.count < count else { return }

        await withCheckedContinuation { continuation in
            libraryFetchCountWaiters.append((count, continuation))
        }
    }

    func resumeLibraryFetch(at callIndex: Int, returning items: [MediaItem]) {
        suspendedLibraryFetches.removeValue(forKey: callIndex)?.resume(returning: items)
    }

    private func resumeLibraryFetchCountWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in libraryFetchCountWaiters {
            if queries.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        libraryFetchCountWaiters = remaining
    }
}

private actor LibraryViewModelRepositoryStub: MetadataRepositoryProtocol {
    private var savedViews: [SharedLibraryView] = []
    private var views: [SharedLibraryView]
    private var itemsByID: [String: MediaItem] = [:]
    private var libraryFetchPlans: [LibraryItemFetchPlan]
    private var searchPlans: [LibraryItemFetchPlan]
    private var libraryQueries: [LibraryQuery] = []
    private var searchQueries: [(query: String, limit: Int)] = []
    private var upsertBatches: [[MediaItem]] = []
    private var suspendedLibraryFetches: [Int: CheckedContinuation<[MediaItem], Never>] = [:]
    private var suspendedSearches: [Int: CheckedContinuation<[MediaItem], Never>] = [:]
    private var libraryFetchCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var searchCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(
        views: [SharedLibraryView] = [],
        libraryFetchPlans: [LibraryItemFetchPlan] = [],
        searchPlans: [LibraryItemFetchPlan] = []
    ) {
        self.views = views
        self.libraryFetchPlans = libraryFetchPlans
        self.searchPlans = searchPlans
    }

    func saveLibraryViews(_ views: [SharedLibraryView]) async throws {
        self.views = views
        savedViews = views
    }

    func fetchLibraryViews() async throws -> [SharedLibraryView] {
        views
    }

    func saveHomeFeed(_ feed: HomeFeed) async throws { _ = feed }
    func fetchHomeFeed() async throws -> HomeFeed { .empty }

    func upsertItems(_ items: [MediaItem]) async throws {
        upsertBatches.append(items)
        for item in items {
            itemsByID[item.id] = item
        }
    }

    func fetchItem(id: String) async throws -> MediaItem? {
        itemsByID[id]
    }

    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        libraryQueries.append(query)
        resumeLibraryFetchCountWaiters()
        let callIndex = libraryQueries.count - 1

        if !libraryFetchPlans.isEmpty {
            switch libraryFetchPlans.removeFirst() {
            case let .immediate(items):
                return items
            case .suspended:
                return await withCheckedContinuation { continuation in
                    suspendedLibraryFetches[callIndex] = continuation
                }
            }
        }

        let allowedViewIDs = Set(query.resolvedViewIDs)
        return itemsByID.values
            .filter { item in
                (allowedViewIDs.isEmpty || allowedViewIDs.contains(item.libraryID ?? "")) &&
                    (query.mediaType == nil || item.mediaType == query.mediaType)
            }
            .prefix(query.pageSize)
            .map { $0 }
    }

    func searchItems(query: String, limit: Int) async throws -> [MediaItem] {
        searchQueries.append((query, limit))
        resumeSearchCountWaiters()
        let callIndex = searchQueries.count - 1

        if !searchPlans.isEmpty {
            switch searchPlans.removeFirst() {
            case let .immediate(items):
                return items
            case .suspended:
                return await withCheckedContinuation { continuation in
                    suspendedSearches[callIndex] = continuation
                }
            }
        }

        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        return Array(itemsByID.values.prefix(limit))
    }

    func savePlaybackProgress(_ progress: PlaybackProgress) async throws { _ = progress }
    func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? { _ = itemID; return nil }
    func fetchLastSyncDate() async throws -> Date? { nil }
    func setLastSyncDate(_ date: Date) async throws { _ = date }

    func recordedSavedViews() -> [SharedLibraryView] {
        savedViews
    }

    func recordedLibraryQueries() -> [LibraryQuery] {
        libraryQueries
    }

    func recordedSearchQueries() -> [(query: String, limit: Int)] {
        searchQueries
    }

    func recordedUpsertBatches() -> [[MediaItem]] {
        upsertBatches
    }

    func waitForLibraryFetchCount(_ count: Int) async {
        guard libraryQueries.count < count else { return }

        await withCheckedContinuation { continuation in
            libraryFetchCountWaiters.append((count, continuation))
        }
    }

    func waitForSearchCount(_ count: Int) async {
        guard searchQueries.count < count else { return }

        await withCheckedContinuation { continuation in
            searchCountWaiters.append((count, continuation))
        }
    }

    func resumeLibraryFetch(at callIndex: Int, returning items: [MediaItem]) {
        suspendedLibraryFetches.removeValue(forKey: callIndex)?.resume(returning: items)
    }

    func resumeSearch(at callIndex: Int, returning items: [MediaItem]) {
        suspendedSearches.removeValue(forKey: callIndex)?.resume(returning: items)
    }

    private func resumeLibraryFetchCountWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in libraryFetchCountWaiters {
            if libraryQueries.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        libraryFetchCountWaiters = remaining
    }

    private func resumeSearchCountWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in searchCountWaiters {
            if searchQueries.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        searchCountWaiters = remaining
    }
}

@MainActor
private func makeDependencies(
    apiClient: LibraryViewModelAPIClientStub,
    repository: LibraryViewModelRepositoryStub,
    warmupManager: PlaybackWarmupManaging? = nil
) -> ReelFinDependencies {
    let detailRepository = DefaultMediaDetailRepository(
        apiClient: apiClient,
        repository: repository,
        itemTTL: 60,
        detailTTL: 60,
        collectionTTL: 60
    )
    let resolvedWarmupManager = warmupManager ?? PlaybackWarmupManager(apiClient: apiClient, ttl: 60)

    return ReelFinDependencies(
        apiClient: apiClient,
        repository: repository,
        detailRepository: detailRepository,
        imagePipeline: MockImagePipeline(),
        artworkPrefetcher: ArtworkPrefetcherTestDouble(),
        syncEngine: MockSyncEngine(),
        settingsStore: MockSettingsStore(),
        episodeReleaseNotificationManager: NoopEpisodeReleaseNotificationManager(),
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
