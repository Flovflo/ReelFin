import CoreGraphics
import XCTest
@testable import ReelFinUI

final class IOSDetailCarouselLayoutTests: XCTestCase {
    func testPosterCardMetricsFavorDenserBrowsingWidthsOnIOS() {
        XCTAssertEqual(PosterCardMetrics.posterWidth(for: .row, compact: true), 122, accuracy: 0.001)
        XCTAssertEqual(PosterCardMetrics.posterWidth(for: .row, compact: false), 148, accuracy: 0.001)
        XCTAssertEqual(PosterCardMetrics.posterWidth(for: .grid, compact: true), 146, accuracy: 0.001)
        XCTAssertEqual(PosterCardMetrics.posterWidth(for: .grid, compact: false), 188, accuracy: 0.001)
        XCTAssertEqual(PosterCardMetrics.posterWidth(for: .landscape, compact: true), 220, accuracy: 0.001)
        XCTAssertEqual(PosterCardMetrics.posterWidth(for: .landscape, compact: false), 272, accuracy: 0.001)
    }

    func testCompactLayoutUsesTrueCenteredInset() {
        let availableWidth: CGFloat = 393
        let cardWidth = IOSDetailCarouselLayout.cardWidth(
            for: availableWidth,
            minimumPadding: 20,
            viewportWidth: availableWidth
        )

        let sideInset = IOSDetailCarouselLayout.sideInset(
            for: availableWidth,
            cardWidth: cardWidth,
            minimumPadding: 20,
            viewportWidth: availableWidth
        )

        XCTAssertEqual(cardWidth, 353, accuracy: 0.001)
        XCTAssertEqual(sideInset, 20, accuracy: 0.001)
        XCTAssertEqual((sideInset * 2) + cardWidth, availableWidth, accuracy: 0.001)
    }

    func testRegularLayoutStillHonorsMinimumPadding() {
        let availableWidth: CGFloat = 430
        let cardWidth = IOSDetailCarouselLayout.cardWidth(
            for: availableWidth,
            minimumPadding: 20,
            viewportWidth: availableWidth
        )

        let sideInset = IOSDetailCarouselLayout.sideInset(
            for: availableWidth,
            cardWidth: cardWidth,
            minimumPadding: 20,
            viewportWidth: availableWidth
        )

        XCTAssertEqual(cardWidth, 390, accuracy: 0.001)
        XCTAssertEqual(sideInset, 20, accuracy: 0.001)
        XCTAssertEqual((sideInset * 2) + cardWidth, availableWidth, accuracy: 0.001)
    }
}
