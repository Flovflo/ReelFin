#if os(iOS)
import XCTest
@testable import ReelFinUI

@MainActor
final class PlayerOrientationLockTests: XCTestCase {
    override func tearDown() {
        OrientationManager.shared.geometryUpdateHandler = nil
        OrientationManager.shared.restorePortraitAfterPlayerDismissal(requestGeometryUpdate: false)
        super.tearDown()
    }

    func testPlayerCoverPreparationKeepsCurrentOrientationStable() {
        OrientationManager.shared.lock = .portrait
        var requestedOrientations: [UIInterfaceOrientationMask] = []
        OrientationManager.shared.geometryUpdateHandler = { requestedOrientations.append($0) }

        OrientationManager.shared.prepareLandscapeForPlayerCoverPresentation()

        XCTAssertEqual(OrientationManager.shared.lock, .portrait)
        XCTAssertTrue(requestedOrientations.isEmpty)
    }

    func testVisiblePlayerRequestsLandscapeGeometryUpdate() {
        OrientationManager.shared.lock = .portrait
        var requestedOrientations: [UIInterfaceOrientationMask] = []
        OrientationManager.shared.geometryUpdateHandler = { requestedOrientations.append($0) }

        OrientationManager.shared.lockLandscapeForPlayerPresentation()

        XCTAssertEqual(OrientationManager.shared.lock, .landscape)
        XCTAssertEqual(requestedOrientations, [.landscapeRight])
    }

    func testPlayerDismissalRestoresPortraitOutsidePlayer() {
        OrientationManager.shared.lock = .landscape

        OrientationManager.shared.restorePortraitAfterPlayerDismissal(requestGeometryUpdate: false)

        XCTAssertEqual(OrientationManager.shared.lock, .portrait)
    }
}
#endif
