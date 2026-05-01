import CoreGraphics
import XCTest
@testable import ReelFinUI

final class TVDetailActionButtonLayoutTests: XCTestCase {
    func testHeroActionsUseOneFixedControlSize() {
        XCTAssertEqual(TVDetailActionButtonLayout.controlSize.width, 206)
        XCTAssertEqual(TVDetailActionButtonLayout.controlSize.height, 72)
        XCTAssertEqual(TVDetailActionButtonLayout.focusedScale, 1)
    }
}
