import CoreGraphics
import Shared
import XCTest
@testable import ReelFinUI

final class IOSDetailCarouselLayoutTests: XCTestCase {
    func testDetailTelemetryCoalescesDuplicateNavigationUntilPresentationEnds() async {
        let itemID = "telemetry-\(UUID().uuidString)"

        let firstStart = await DetailPresentationTelemetry.shared.beginNavigation(for: itemID)
        let duplicateStart = await DetailPresentationTelemetry.shared.beginNavigation(for: itemID)
        await DetailPresentationTelemetry.shared.endNavigation(for: itemID)
        let reopenedStart = await DetailPresentationTelemetry.shared.beginNavigation(for: itemID)
        await DetailPresentationTelemetry.shared.endNavigation(for: itemID)

        XCTAssertTrue(firstStart)
        XCTAssertFalse(duplicateStart)
        XCTAssertTrue(reopenedStart)
    }

    func testBrowseSurfacesNeverStartBulkCustomPlayerCacheBeforePlay() throws {
        let detailSource = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift"
        )
        let homeSource = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift"
        )

        XCTAssertTrue(detailSource.contains("prewarmer.prewarmResolveOnly(itemID: target.id)"))
        XCTAssertFalse(detailSource.contains("prewarmer.prewarm(itemID: target.id"))
        XCTAssertTrue(homeSource.contains("ensureHomeCustomPrewarmer()?.prewarmResolveOnly(itemID: playbackItem.id)"))
        XCTAssertFalse(homeSource.contains("ensureHomeCustomPrewarmer()?.prewarm(\n"))
    }

    func testReduceTransparencyDetailHeaderSwitchesToFullyOpaqueAtFirstChromeStep() {
        XCTAssertEqual(
            EditorialOpaqueHeaderPolicy.opacity(
                revealProgress: 0,
                activationThreshold: 1.0 / CGFloat(IOSDetailCarouselLayout.chromeStepCount)
            ),
            0
        )
        XCTAssertEqual(
            EditorialOpaqueHeaderPolicy.opacity(
                revealProgress: 1.0 / CGFloat(IOSDetailCarouselLayout.chromeStepCount),
                activationThreshold: 1.0 / CGFloat(IOSDetailCarouselLayout.chromeStepCount)
            ),
            1
        )
    }

    func testDetailOpaqueFallbackStopsBeforeTheHeroControls() throws {
        XCTAssertEqual(
            IOSDetailCompactHeaderLayout.opaqueStatusBandHeight(safeAreaTop: 59),
            59
        )

        let source = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift"
        )

        XCTAssertTrue(source.contains("EditorialOpaqueHeaderPolicy.opacity"))
        XCTAssertTrue(source.contains("opaqueStatusBandHeight"))
        XCTAssertFalse(source.contains("safeAreaTop + 64"))
    }

    func testIOSDetailHidesRootTabBarAlongsideNavigationBar() throws {
        let source = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift"
        )

        XCTAssertTrue(
            source.contains(
                ".navigationBarBackButtonHidden(true)\n"
                    + "        .toolbar(.hidden, for: .navigationBar)\n"
                    + "        .toolbar(.hidden, for: .tabBar)"
            )
        )
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

    private func sourceText(at path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
