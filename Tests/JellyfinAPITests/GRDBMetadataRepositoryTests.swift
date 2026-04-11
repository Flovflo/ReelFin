import DataStore
import Shared
import XCTest

final class GRDBMetadataRepositoryTests: XCTestCase {
    private let ticksPerMinute: Int64 = 60 * 10_000_000

    func testSaveHomeFeedPreservesWatchStateAndMetadata() async throws {
        let repository = try makeRepository()

        let item = MediaItem(
            id: "episode-1",
            name: "Pilot",
            overview: "A test episode.",
            mediaType: .episode,
            year: 2000,
            runtimeTicks: 22 * ticksPerMinute,
            genres: ["Comedy"],
            communityRating: 8.7,
            posterTag: "poster",
            backdropTag: "backdrop",
            libraryID: "shows",
            parentID: "series-1",
            seriesName: "Malcolm",
            seriesPosterTag: "series-poster",
            indexNumber: 1,
            parentIndexNumber: 1,
            has4K: true,
            hasDolbyVision: true,
            hasClosedCaptions: true,
            airDays: ["Friday"],
            isFavorite: true,
            isPlayed: false,
            playbackPositionTicks: 11 * ticksPerMinute
        )

        let feed = HomeFeed(
            featured: [item],
            rows: [HomeRow(kind: .continueWatching, title: "Continue Watching", items: [item])]
        )

        try await repository.saveHomeFeed(feed)

        let cachedFeed = try await repository.fetchHomeFeed()
        let cachedItem = try XCTUnwrap(cachedFeed.featured.first)

        XCTAssertEqual(cachedItem.seriesName, item.seriesName)
        XCTAssertEqual(cachedItem.seriesPosterTag, item.seriesPosterTag)
        XCTAssertEqual(cachedItem.indexNumber, item.indexNumber)
        XCTAssertEqual(cachedItem.parentIndexNumber, item.parentIndexNumber)
        XCTAssertEqual(cachedItem.has4K, item.has4K)
        XCTAssertEqual(cachedItem.hasDolbyVision, item.hasDolbyVision)
        XCTAssertEqual(cachedItem.hasClosedCaptions, item.hasClosedCaptions)
        XCTAssertEqual(cachedItem.airDays, item.airDays)
        XCTAssertEqual(cachedItem.isFavorite, item.isFavorite)
        XCTAssertEqual(cachedItem.isPlayed, item.isPlayed)
        XCTAssertEqual(cachedItem.playbackPositionTicks, item.playbackPositionTicks)
        XCTAssertEqual(cachedItem.playbackProgress ?? 0, item.playbackProgress ?? 0, accuracy: 0.0001)
    }

    func testFetchHomeFeedPrefersLocalPlaybackProgressOverCachedItemValue() async throws {
        let repository = try makeRepository()

        let item = MediaItem(
            id: "movie-1",
            name: "A Movie",
            mediaType: .movie,
            runtimeTicks: 100 * ticksPerMinute,
            playbackPositionTicks: 12 * ticksPerMinute
        )

        let feed = HomeFeed(
            featured: [],
            rows: [HomeRow(kind: .continueWatching, title: "Continue Watching", items: [item])]
        )

        try await repository.saveHomeFeed(feed)
        try await repository.savePlaybackProgress(
            PlaybackProgress(
                itemID: item.id,
                positionTicks: 37 * ticksPerMinute,
                totalTicks: 100 * ticksPerMinute,
                updatedAt: Date()
            )
        )

        let cachedFeed = try await repository.fetchHomeFeed()
        let cachedItem = try XCTUnwrap(cachedFeed.rows.first?.items.first)

        XCTAssertEqual(cachedItem.playbackPositionTicks, 37 * ticksPerMinute)
        XCTAssertEqual(cachedItem.runtimeTicks, 100 * ticksPerMinute)
        XCTAssertEqual(cachedItem.playbackProgress ?? 0, 0.37, accuracy: 0.0001)
    }

    func testFetchItemSuppressesProgressForPlayedItems() async throws {
        let repository = try makeRepository()

        let item = MediaItem(
            id: "movie-2",
            name: "Watched",
            mediaType: .movie,
            runtimeTicks: 90 * ticksPerMinute,
            isPlayed: true,
            playbackPositionTicks: 45 * ticksPerMinute
        )

        try await repository.saveHomeFeed(
            HomeFeed(
                featured: [item],
                rows: [HomeRow(kind: .movies, title: "Movies", items: [item])]
            )
        )
        try await repository.savePlaybackProgress(
            PlaybackProgress(
                itemID: item.id,
                positionTicks: 20 * ticksPerMinute,
                totalTicks: 90 * ticksPerMinute,
                updatedAt: Date()
            )
        )

        let cachedItem = try await repository.fetchItem(id: item.id)

        XCTAssertEqual(cachedItem?.isPlayed, true)
        XCTAssertNil(cachedItem?.playbackPositionTicks)
        XCTAssertNil(cachedItem?.playbackProgress)
        XCTAssertNil(cachedItem?.playbackPositionDisplayText)
    }

    func testEpisodeReleaseStateRoundTrips() async throws {
        let repository = try makeRepository()
        let updatedAt = Date(timeIntervalSince1970: 123_456)
        let state = EpisodeReleaseState(
            seriesID: "series-1",
            seriesName: "For All Mankind",
            lastKnownNextUpEpisodeID: "episode-2",
            lastKnownNextUpSeasonNumber: 5,
            lastKnownNextUpEpisodeNumber: 2,
            lastNotifiedEpisodeID: "episode-2",
            updatedAt: updatedAt
        )

        try await repository.upsertEpisodeReleaseState(state)

        let restored = try await repository.fetchEpisodeReleaseState(seriesID: "series-1")
        let allStates = try await repository.fetchEpisodeReleaseStates()

        XCTAssertEqual(restored, state)
        XCTAssertEqual(allStates, [state])
    }

    private func makeRepository() throws -> GRDBMetadataRepository {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return try GRDBMetadataRepository(
            databaseURL: directoryURL.appendingPathComponent("metadata.sqlite")
        )
    }
}
