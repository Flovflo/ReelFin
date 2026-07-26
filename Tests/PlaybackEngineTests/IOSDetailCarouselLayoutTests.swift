import CoreGraphics
import XCTest
@testable import ReelFinUI

final class IOSDetailCarouselLayoutTests: XCTestCase {
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

    func testVerticalScrollImmediatelyLocksHorizontalSelection() {
        XCTAssertTrue(
            IOSDetailCarouselLayout.allowsHorizontalSelection(topInsetProgress: 0)
        )
        XCTAssertTrue(
            IOSDetailCarouselLayout.allowsHorizontalSelection(topInsetProgress: 0.01)
        )
        XCTAssertFalse(
            IOSDetailCarouselLayout.allowsHorizontalSelection(topInsetProgress: 0.011)
        )
    }

    func testNeighborPreviewFadesOutBeforeCompactHeaderCanRevealStaleTitles() {
        XCTAssertEqual(
            IOSDetailCarouselLayout.neighborPreviewOpacity(topInsetProgress: 0),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            IOSDetailCarouselLayout.neighborPreviewOpacity(topInsetProgress: 0.005),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            IOSDetailCarouselLayout.neighborPreviewOpacity(topInsetProgress: 0.01),
            0,
            accuracy: 0.001
        )
    }

    func testVerticalScrollRejectsCarouselSelectionChanges() {
        XCTAssertEqual(
            IOSDetailCarouselLayout.acceptedSelectionID(
                currentItemID: "dragon",
                proposedItemID: "other-movie",
                topInsetProgress: 0
            ),
            "other-movie"
        )

        XCTAssertNil(
            IOSDetailCarouselLayout.acceptedSelectionID(
                currentItemID: "dragon",
                proposedItemID: "other-movie",
                topInsetProgress: 0.011
            )
        )

        XCTAssertNil(
            IOSDetailCarouselLayout.acceptedSelectionID(
                currentItemID: "dragon",
                proposedItemID: "dragon",
                topInsetProgress: 0
            )
        )
    }

    func testNearbyOffsetsInOneBucketProduceEqualScrollPresentation() {
        let first = IOSDetailCarouselLayout.presentation(
            offsetY: 15,
            topInset: 0,
            heroHeight: 800,
            topTriggerDistance: 50,
            reduceMotion: false
        )
        let second = IOSDetailCarouselLayout.presentation(
            offsetY: 15.2,
            topInset: 0,
            heroHeight: 800,
            topTriggerDistance: 50,
            reduceMotion: false
        )

        XCTAssertEqual(first, second)
    }

    func testHorizontalSelectionLockUsesRawThresholdBeforeQuantization() {
        let unlocked = IOSDetailCarouselLayout.presentation(
            offsetY: 10.49,
            topInset: 0,
            heroHeight: 800,
            topTriggerDistance: 50,
            reduceMotion: false
        )
        let locked = IOSDetailCarouselLayout.presentation(
            offsetY: 10.51,
            topInset: 0,
            heroHeight: 800,
            topTriggerDistance: 50,
            reduceMotion: false
        )

        XCTAssertEqual(unlocked.heroStep, locked.heroStep)
        XCTAssertEqual(unlocked.chromeStep, locked.chromeStep)
        XCTAssertTrue(unlocked.allowsHorizontalSelection)
        XCTAssertFalse(locked.allowsHorizontalSelection)
    }

    func testReduceMotionUsesOnlyExpandedOrCollapsedPresentation() {
        let expanded = IOSDetailCarouselLayout.presentation(
            offsetY: 34,
            topInset: 0,
            heroHeight: 800,
            topTriggerDistance: 50,
            reduceMotion: true
        )
        let collapsed = IOSDetailCarouselLayout.presentation(
            offsetY: 36,
            topInset: 0,
            heroHeight: 800,
            topTriggerDistance: 50,
            reduceMotion: true
        )

        XCTAssertEqual(expanded.heroStep, 0)
        XCTAssertEqual(expanded.chromeStep, 0)
        XCTAssertEqual(collapsed.heroStep, 32)
        XCTAssertEqual(collapsed.chromeStep, 12)
    }

    func testDetailCarouselShadowsKeepFixedGeometryAcrossScroll() {
        XCTAssertEqual(IOSDetailCarouselLayout.selectedShadowRadius, 30)
        XCTAssertEqual(IOSDetailCarouselLayout.selectedShadowYOffset, 24)
        XCTAssertEqual(IOSDetailCarouselLayout.previewShadowRadius, 18)
        XCTAssertEqual(IOSDetailCarouselLayout.previewShadowYOffset, 12)
    }
}
