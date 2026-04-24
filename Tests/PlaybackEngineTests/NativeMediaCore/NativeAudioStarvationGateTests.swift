@testable import ReelFinUI
import XCTest

final class NativeAudioStarvationGateTests: XCTestCase {
    func testDoesNotRebufferOnTightRendererCallbacksBeforeMinimumDuration() {
        var gate = NativeAudioStarvationGate(minimumStarvationDuration: 0.75)

        let first = gate.update(isStarved: true, now: 10.0)
        let second = gate.update(isStarved: true, now: 10.01)
        let third = gate.update(isStarved: true, now: 10.02)

        XCTAssertFalse(first.shouldRebuffer)
        XCTAssertFalse(second.shouldRebuffer)
        XCTAssertFalse(third.shouldRebuffer)
        XCTAssertEqual(third.ticks, 3)
        XCTAssertEqual(third.elapsedSeconds, 0.02, accuracy: 0.0001)
    }

    func testRebuffersOnlyAfterSustainedAudioStarvation() {
        var gate = NativeAudioStarvationGate(minimumStarvationDuration: 0.75)

        _ = gate.update(isStarved: true, now: 20.0)
        let decision = gate.update(isStarved: true, now: 20.8)

        XCTAssertTrue(decision.shouldRebuffer)
        XCTAssertEqual(decision.elapsedSeconds, 0.8, accuracy: 0.0001)
    }

    func testAudioRefillResetsStarvationWindow() {
        var gate = NativeAudioStarvationGate(minimumStarvationDuration: 0.75)

        _ = gate.update(isStarved: true, now: 30.0)
        _ = gate.update(isStarved: false, now: 30.1)
        let decision = gate.update(isStarved: true, now: 30.8)

        XCTAssertFalse(decision.shouldRebuffer)
        XCTAssertEqual(decision.ticks, 1)
        XCTAssertEqual(decision.elapsedSeconds, 0, accuracy: 0.0001)
    }
}
