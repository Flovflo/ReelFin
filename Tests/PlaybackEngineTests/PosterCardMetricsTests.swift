import CoreGraphics
@testable import ReelFinUI
import XCTest

final class PosterCardMetricsTests: XCTestCase {
    func testPosterRowsReserveRequestedTitleLines() {
        let titleHeight = PosterCardMetrics.titleBlockHeight(
            fontSize: 15,
            lineLimit: 2
        )

        XCTAssertEqual(titleHeight, 36, accuracy: 0.001)
    }

    func testPosterArtworkKeepsUniformPortraitRatio() {
        let compactMetrics = PosterCardMetrics(layoutStyle: .row, compact: true)
        let regularMetrics = PosterCardMetrics(layoutStyle: .row, compact: false)

        XCTAssertEqual(compactMetrics.posterHeight, compactMetrics.posterWidth * 1.55, accuracy: 0.001)
        XCTAssertEqual(regularMetrics.posterHeight, regularMetrics.posterWidth * 1.55, accuracy: 0.001)
    }

    func testDenseDisplayDensityShrinksArtworkMoreThanText() {
        let standardMetrics = PosterCardMetrics(layoutStyle: .grid, compact: true, displayDensity: .standard)
        let denseMetrics = PosterCardMetrics(layoutStyle: .grid, compact: true, displayDensity: .dense)

        let artworkRatio = denseMetrics.posterWidth / standardMetrics.posterWidth

        XCTAssertLessThan(artworkRatio, ReelFinDisplayDensity.dense.textScale)
        XCTAssertEqual(artworkRatio, ReelFinDisplayDensity.dense.visualScale, accuracy: 0.001)
        XCTAssertEqual(ReelFinDisplayDensity.dense.scaledTextSize(15), 13.8, accuracy: 0.001)
    }

    func testDisplayDensityStorageFallsBackToStandardForUnknownValues() {
        XCTAssertEqual(ReelFinDisplayDensity(rawStoredValue: "dense"), .dense)
        XCTAssertEqual(ReelFinDisplayDensity(rawStoredValue: "unexpected"), .standard)
    }
}
