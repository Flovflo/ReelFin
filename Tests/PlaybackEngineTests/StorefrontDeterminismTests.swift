@testable import ReelFinUI
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

    func testStorefrontCatalogUsesCredibleFictionalReleaseCopy() async throws {
        let client = MockJellyfinAPIClient()
        let featured = try await client.fetchItem(id: "sample-0")
        let searchResult = try await client.fetchItem(id: "sample-24")

        XCTAssertEqual(featured.name, "Vesper Meridian")
        XCTAssertEqual(searchResult.name, "Hollow Aurora")
        XCTAssertTrue(featured.overview?.contains("cartographer") == true)

        for item in [featured, searchResult] {
            let releaseCopy = [item.name, item.overview ?? ""].joined(separator: " ").lowercased()
            XCTAssertFalse(releaseCopy.contains("sample"))
            XCTAssertFalse(releaseCopy.contains("mock"))
            XCTAssertFalse(releaseCopy.contains("preview"))
            XCTAssertGreaterThan(item.overview?.count ?? 0, 60)
        }
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
