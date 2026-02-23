import XCTest
@testable import JellyfinAPI
import Shared

final class MockJellyfinAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    var mockedItem: MediaItem?
    var fetchItemCallCount = 0

    func fetchItem(id: String) async throws -> MediaItem {
        fetchItemCallCount += 1
        if let item = mockedItem {
            return item
        }
        throw AppError.network("Mock error")
    }

    // Unused in this test
    func currentConfiguration() async -> ServerConfiguration? { nil }
    func currentSession() async -> UserSession? { nil }
    func configure(server: ServerConfiguration) async throws {}
    func testConnection(serverURL: URL) async throws {}
    func authenticate(credentials: UserCredentials) async throws -> UserSession { throw AppError.unknown }
    func signOut() async {}
    func fetchUserViews() async throws -> [LibraryView] { [] }
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed { .empty }
    func fetchItemDetail(id: String) async throws -> MediaDetail { throw AppError.unknown }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { [] }
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] { [] }
    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] { [] }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? { nil }
    func reportPlayback(progress: PlaybackProgressUpdate) async throws {}
    func reportPlayed(itemID: String) async throws {}
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { [] }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? { nil }
}

final class SeriesLookupCacheTests: XCTestCase {
    func test_getSeries_fetchesFromAPI_whenNotCached() async throws {
        let mockClient = MockJellyfinAPIClient()
        mockClient.mockedItem = MediaItem(id: "series_1", name: "Test Series", mediaType: .series)
        
        let cache = SeriesLookupCache(apiClient: mockClient)
        let item = try await cache.getSeries(id: "series_1")
        
        XCTAssertEqual(item.name, "Test Series")
        XCTAssertEqual(mockClient.fetchItemCallCount, 1)
    }

    func test_getSeries_returnsCachedResult_andDoesNotFetchAgain() async throws {
        let mockClient = MockJellyfinAPIClient()
        mockClient.mockedItem = MediaItem(id: "series_1", name: "Test Series", mediaType: .series)
        
        let cache = SeriesLookupCache(apiClient: mockClient)
        _ = try await cache.getSeries(id: "series_1")
        let item2 = try await cache.getSeries(id: "series_1")
        
        XCTAssertEqual(item2.name, "Test Series")
        XCTAssertEqual(mockClient.fetchItemCallCount, 1, "Should not hit API for cached item")
    }

    func test_getSeries_concurrentRequests_onlyFetchOnce() async throws {
        let mockClient = MockJellyfinAPIClient()
        mockClient.mockedItem = MediaItem(id: "series_1", name: "Test Series", mediaType: .series)
        
        let cache = SeriesLookupCache(apiClient: mockClient)
        
        async let fetch1 = cache.getSeries(id: "series_1")
        async let fetch2 = cache.getSeries(id: "series_1")
        async let fetch3 = cache.getSeries(id: "series_1")
        
        let results = try await [fetch1, fetch2, fetch3]
        
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(mockClient.fetchItemCallCount, 1, "In-flight deduplication should prevent multiple API calls")
    }
}

final class ItemDTOHDRDetectionTests: XCTestCase {
    func testHasDolbyVisionWhenRangeTypeIsDolbyVision() {
        let item = makeItem(
            streams: [
                makeVideoStream(videoRangeType: "DolbyVision", codec: "hevc")
            ]
        )

        let domain = item.toDomain()

        XCTAssertTrue(domain.hasDolbyVision)
    }

    func testHasDolbyVisionWhenCodecIsDVHE() {
        let item = makeItem(
            streams: [
                makeVideoStream(videoRangeType: "SDR", codec: "dvhe.05.06")
            ]
        )

        let domain = item.toDomain()

        XCTAssertTrue(domain.hasDolbyVision)
    }

    func testHasDolbyVisionIsFalseForHDR10() {
        let item = makeItem(
            streams: [
                makeVideoStream(videoRangeType: "HDR10", codec: "hevc")
            ]
        )

        let domain = item.toDomain()

        XCTAssertFalse(domain.hasDolbyVision)
    }

    func testHasDolbyVisionIsFalseForGenericHDR() {
        let item = makeItem(
            streams: [
                makeVideoStream(videoRangeType: "HDR", codec: "hevc")
            ]
        )

        let domain = item.toDomain()

        XCTAssertFalse(domain.hasDolbyVision)
    }

    private func makeItem(streams: [MediaStreamDTO]) -> ItemDTO {
        ItemDTO(
            id: "item-1",
            name: "Test Item",
            overview: nil,
            type: "Movie",
            productionYear: nil,
            runTimeTicks: nil,
            genres: nil,
            communityRating: nil,
            imageTags: nil,
            backdropImageTags: nil,
            parentID: nil,
            seriesID: nil,
            seriesName: nil,
            seriesPrimaryImageTag: nil,
            indexNumber: nil,
            parentIndexNumber: nil,
            people: nil,
            mediaStreams: streams,
            airDays: nil,
            userData: nil
        )
    }

    private func makeVideoStream(
        videoRangeType: String?,
        codec: String?,
        profile: String? = nil,
        displayTitle: String? = nil
    ) -> MediaStreamDTO {
        MediaStreamDTO(
            index: 0,
            type: "Video",
            title: nil,
            displayTitle: displayTitle,
            language: nil,
            isDefault: true,
            codec: codec,
            profile: profile,
            bitDepth: nil,
            videoRangeType: videoRangeType,
            channels: nil,
            channelLayout: nil,
            bitrate: nil,
            width: 1920,
            height: 1080
        )
    }
}
