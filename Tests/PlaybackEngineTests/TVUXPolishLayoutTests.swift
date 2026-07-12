import XCTest
@testable import ReelFinUI

final class TVUXPolishLayoutTests: XCTestCase {
    func testCompactResumeChoiceMetrics() {
        let layout = TVPlaybackResumeChoiceLayout.standard
        XCTAssertEqual(layout.maxWidth, 760)
        XCTAssertEqual(layout.cornerRadius, 34)
        XCTAssertEqual(layout.horizontalPadding, 44)
        XCTAssertEqual(layout.verticalPadding, 34)
        XCTAssertEqual(layout.buttonHeight, 66)
        XCTAssertEqual(layout.focusOpacity, 0.20)
    }

    func testCompactPlayerLaunchMetrics() {
        let layout = TVPlayerLaunchLayout.standard
        XCTAssertEqual(layout.maxWidth, 420)
        XCTAssertEqual(layout.cornerRadius, 24)
        XCTAssertEqual(layout.spinnerSize, 34)
        XCTAssertEqual(layout.progressWidth, 280)
        XCTAssertEqual(layout.screenInset, 64)
    }

    func testTVFocusScalesMatchApprovedCouchDistanceGeometry() {
        XCTAssertEqual(TVFocusGeometry.scale(for: .homePosterCard, reduceMotion: false), 1.07)
        XCTAssertEqual(TVFocusGeometry.scale(for: .homeLandscapeCard, reduceMotion: false), 1.06)
        XCTAssertEqual(TVFocusGeometry.scale(for: .libraryPoster, reduceMotion: false), 1.06)
        XCTAssertEqual(TVFocusGeometry.scale(for: .homePosterCard, reduceMotion: true), 1.02)
    }

    func testReduceMotionDoesNotRaiseNavigationRoleAboveItsNormalScale() {
        XCTAssertEqual(TVFocusGeometry.scale(for: .navItem, reduceMotion: true), 1.0)
    }

    func testLibraryFirstRowReserveContainsScaleOverflowAndShadow() {
        let reserve = TVLibraryFocusLayout.firstRowTopReserve(
            cardWidth: 240,
            scale: 1.06,
            minimumReserve: 34
        )
        XCTAssertGreaterThanOrEqual(reserve, 34 + ((240 * 1.06 - 240) / 2))
    }
}
