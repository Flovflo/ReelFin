import CoreGraphics
import XCTest
@testable import ReelFinUI

final class IOSDetailSynopsisLayoutTests: XCTestCase {
    func testCompactSynopsisNeverExpandsWithoutALimit() {
        XCTAssertEqual(
            IOSDetailSynopsisLayout.lineLimit(isExpanded: false, contentWidth: 353),
            2
        )
        XCTAssertEqual(
            IOSDetailSynopsisLayout.lineLimit(isExpanded: true, contentWidth: 353),
            4
        )
        XCTAssertEqual(
            IOSDetailSynopsisLayout.lineLimit(isExpanded: false, contentWidth: 402),
            2
        )
    }

    func testRegularSynopsisAllowsMoreLinesButRemainsBounded() {
        XCTAssertEqual(
            IOSDetailSynopsisLayout.lineLimit(isExpanded: false, contentWidth: 700),
            3
        )
        XCTAssertEqual(
            IOSDetailSynopsisLayout.lineLimit(isExpanded: true, contentWidth: 700),
            6
        )
    }

    func testMaximumHeightScalesFromFiniteLineLimit() {
        let height = IOSDetailSynopsisLayout.maximumHeight(fontSize: 15.5, lineLimit: 4)

        XCTAssertEqual(height, 84, accuracy: 0.001)
    }

    func testExpansionThresholdTracksCollapsedCompactCapacity() {
        XCTAssertFalse(
            IOSDetailSynopsisLayout.needsExpansion(String(repeating: "a", count: 80), contentWidth: 353)
        )
        XCTAssertTrue(
            IOSDetailSynopsisLayout.needsExpansion(String(repeating: "a", count: 81), contentWidth: 353)
        )
    }

    func testExpansionThresholdAllowsMoreRegularWidthTextBeforeMoreButton() {
        XCTAssertFalse(
            IOSDetailSynopsisLayout.needsExpansion(String(repeating: "a", count: 237), contentWidth: 700)
        )
        XCTAssertTrue(
            IOSDetailSynopsisLayout.needsExpansion(String(repeating: "a", count: 238), contentWidth: 700)
        )
    }
}
