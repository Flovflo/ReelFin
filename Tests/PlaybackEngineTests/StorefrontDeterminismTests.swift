@testable import ReelFinUI
import Shared
import XCTest

final class StorefrontDeterminismTests: XCTestCase {
    func testStableSeedHashHasHandCheckedFNV1aValues() {
        XCTAssertEqual(StorefrontStableSeed.hash(""), 14_695_981_039_346_656_037)
        XCTAssertEqual(StorefrontStableSeed.hash("ReelFin"), 17_809_080_437_298_695_942)
    }

    func testPaletteIndexIsStableAndBounded() {
        XCTAssertEqual(StorefrontStableSeed.paletteIndex(for: "ReelFin", paletteCount: 4), 2)
        XCTAssertEqual(StorefrontStableSeed.paletteIndex(for: "ReelFin", paletteCount: 1), 0)
    }

    func testScreenshotHeroRenderingAvoidsAmbientGPUFilterLayer() {
        XCTAssertFalse(HeroBackgroundRenderingPolicy.includesAmbientArtwork(isScreenshotMode: true))
        XCTAssertTrue(HeroBackgroundRenderingPolicy.includesAmbientArtwork(isScreenshotMode: false))
    }

    func testStorefrontUsesCredibleFictionalReleaseCopy() async throws {
        let client = MockJellyfinAPIClient()
        let featured = try await client.fetchItem(id: "sample-0")
        let searchResult = try await client.fetchItem(id: "sample-24")
        let currentSession = await client.currentSession()
        let session = try XCTUnwrap(currentSession)
        let storedSession = try XCTUnwrap(MockSettingsStore().lastSession)

        XCTAssertEqual(featured.name, "Vesper Meridian")
        XCTAssertEqual(searchResult.name, "Hollow Aurora")
        XCTAssertTrue(featured.overview?.contains("cartographer") == true)
        XCTAssertEqual(session.username, "Avery Morgan")
        XCTAssertEqual(storedSession.username, "Avery Morgan")

        let releaseCopy = [
            featured.name,
            featured.overview ?? "",
            searchResult.name,
            searchResult.overview ?? "",
            session.username,
            storedSession.username
        ]
        .joined(separator: " ")
        .lowercased()

        for forbiddenTerm in ["sample", "mock", "preview"] {
            XCTAssertFalse(releaseCopy.contains(forbiddenTerm))
        }

        for item in [featured, searchResult] {
            XCTAssertGreaterThan(item.overview?.count ?? 0, 60)
        }
    }

    func testStorefrontAPIClientFiltersBeforeApplyingLibraryPageSize() async throws {
        let client = MockJellyfinAPIClient()
        let movies = try await client.fetchLibraryItems(
            query: LibraryQuery(
                viewID: nil,
                page: 0,
                pageSize: 4,
                query: nil,
                mediaType: .movie
            )
        )
        let shows = try await client.fetchLibraryItems(
            query: LibraryQuery(
                viewID: nil,
                page: 0,
                pageSize: 4,
                query: nil,
                mediaType: .series
            )
        )

        XCTAssertEqual(movies.count, 4)
        XCTAssertEqual(shows.count, 4)
        XCTAssertTrue(movies.allSatisfy { $0.mediaType == .movie })
        XCTAssertTrue(shows.allSatisfy { $0.mediaType == .series })
        XCTAssertEqual(movies.map(\.id), ["sample-0", "sample-2", "sample-4", "sample-6"])
        XCTAssertEqual(shows.map(\.id), ["sample-1", "sample-3", "sample-5", "sample-7"])
    }

    func testStorefrontMetadataCacheFiltersBeforeApplyingLibraryPageSize() async throws {
        let repository = MockMetadataRepository()
        try await repository.upsertItems(MockJellyfinAPIClient.storefrontItems(prefix: 8))
        let shows = try await repository.fetchLibraryItems(
            query: LibraryQuery(
                viewID: nil,
                page: 0,
                pageSize: 4,
                query: nil,
                mediaType: .series
            )
        )

        XCTAssertEqual(shows.count, 4)
        XCTAssertTrue(shows.allSatisfy { $0.mediaType == .series })
        XCTAssertEqual(Set(shows.map(\.id)), Set(["sample-1", "sample-3", "sample-5", "sample-7"]))
    }

    func testFictionalSeriesEpisodesRemainCoherentWithSelectedSeries() async throws {
        let client = MockJellyfinAPIClient()
        let series = try await client.fetchItem(id: "sample-39")
        let episodes = try await client.fetchEpisodes(seriesID: series.id, seasonID: "season1")

        XCTAssertEqual(series.name, "The Night Almanac")
        XCTAssertEqual(episodes.map(\.seriesName), Array(repeating: series.name, count: episodes.count))
        XCTAssertEqual(episodes.first?.name, "The First Entry")
        XCTAssertTrue(episodes.first?.overview?.contains("almanac") == true)
        XCTAssertFalse(episodes.contains { $0.name == "Vesper Meridian" })
    }
}
