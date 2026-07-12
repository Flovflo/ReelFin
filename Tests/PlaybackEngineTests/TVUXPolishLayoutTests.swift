import XCTest
@testable import ReelFinUI

final class TVUXPolishLayoutTests: XCTestCase {
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
