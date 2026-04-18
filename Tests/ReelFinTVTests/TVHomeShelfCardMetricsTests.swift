import XCTest
@testable import ReelFinUI

final class TVHomeShelfCardMetricsTests: XCTestCase {
    func testHomeShelfRowSurfaceMatchesPosterArtworkMetrics() {
        let metrics = TVHomeShelfCardMetrics(layoutStyle: .row)
        let posterMetrics = PosterCardMetrics(layoutStyle: .row, compact: false)

        XCTAssertEqual(metrics.surfaceWidth, posterMetrics.posterWidth, accuracy: 0.001)
        XCTAssertEqual(metrics.surfaceHeight, posterMetrics.posterHeight, accuracy: 0.001)
        XCTAssertEqual(metrics.cornerRadius, 26, accuracy: 0.001)
    }

    func testHomeShelfGridSurfaceMatchesPosterArtworkMetrics() {
        let metrics = TVHomeShelfCardMetrics(layoutStyle: .grid)
        let posterMetrics = PosterCardMetrics(layoutStyle: .grid, compact: false)

        XCTAssertEqual(metrics.surfaceWidth, posterMetrics.posterWidth, accuracy: 0.001)
        XCTAssertEqual(metrics.surfaceHeight, posterMetrics.posterHeight, accuracy: 0.001)
        XCTAssertEqual(metrics.cornerRadius, 26, accuracy: 0.001)
    }

    func testHomeShelfLandscapeSurfaceMatchesPosterArtworkMetrics() {
        let metrics = TVHomeShelfCardMetrics(layoutStyle: .landscape)
        let posterMetrics = PosterCardMetrics(layoutStyle: .landscape, compact: false)

        XCTAssertEqual(metrics.surfaceWidth, posterMetrics.posterWidth, accuracy: 0.001)
        XCTAssertEqual(metrics.surfaceHeight, posterMetrics.posterHeight, accuracy: 0.001)
        XCTAssertEqual(metrics.cornerRadius, 30, accuracy: 0.001)
    }
}
