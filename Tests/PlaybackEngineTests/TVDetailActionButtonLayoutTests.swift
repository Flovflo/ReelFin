import CoreGraphics
import XCTest
@testable import ReelFinUI

final class TVDetailActionButtonLayoutTests: XCTestCase {
    func testHeroActionsUseOneFixedControlSize() {
        XCTAssertEqual(TVDetailActionButtonLayout.controlSize.width, 206)
        XCTAssertEqual(TVDetailActionButtonLayout.controlSize.height, 72)
        XCTAssertEqual(TVDetailActionButtonLayout.focusedScale, 1)
    }

    func testCollapsedHeroChromeIsFullBleed() {
        let layout = TVDetailHeroChromeLayout(collapseProgress: 1)

        XCTAssertEqual(layout.outerHorizontalPadding, 0, accuracy: 0.001)
        XCTAssertEqual(layout.cornerRadius, 0, accuracy: 0.001)
        XCTAssertEqual(layout.strokeOpacity, 0, accuracy: 0.001)
    }

    func testRestingHeroChromeKeepsCinematicCardShape() {
        let layout = TVDetailHeroChromeLayout(collapseProgress: 0)

        XCTAssertEqual(layout.outerHorizontalPadding, 28, accuracy: 0.001)
        XCTAssertEqual(layout.cornerRadius, 44, accuracy: 0.001)
        XCTAssertGreaterThan(layout.strokeOpacity, 0)
    }
}
