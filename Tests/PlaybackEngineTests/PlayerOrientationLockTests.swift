#if os(iOS)
import XCTest
@testable import ReelFinUI

@MainActor
final class PlayerOrientationLockTests: XCTestCase {
    override func tearDown() {
        OrientationManager.shared.restorePortraitAfterPlayerDismissal(requestGeometryUpdate: false)
        super.tearDown()
    }

    func testPlayerPresentationLocksLandscapeOnlyBeforeCoverAppears() {
        OrientationManager.shared.lock = .portrait

        OrientationManager.shared.lockLandscapeForPlayerPresentation(requestGeometryUpdate: false)

        XCTAssertEqual(OrientationManager.shared.lock, .landscape)
        XCTAssertFalse(OrientationManager.shared.lock.contains(.portrait))
        XCTAssertFalse(OrientationManager.shared.lock.contains(.portraitUpsideDown))
    }

    func testPlayerDismissalRestoresPortraitOutsidePlayer() {
        OrientationManager.shared.lock = .landscape

        OrientationManager.shared.restorePortraitAfterPlayerDismissal(requestGeometryUpdate: false)

        XCTAssertEqual(OrientationManager.shared.lock, .portrait)
    }
}
#endif
