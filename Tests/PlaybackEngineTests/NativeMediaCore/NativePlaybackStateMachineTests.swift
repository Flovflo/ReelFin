import NativeMediaCore
import XCTest

final class NativePlaybackStateMachineTests: XCTestCase {
    func testTransitionsThroughNativeStartupStates() {
        var machine = NativePlaybackStateMachine()

        machine.apply(.beginResolve)
        machine.apply(.originalResolved)
        machine.apply(.probeStarted)
        machine.apply(.demuxStarted)
        machine.apply(.planStarted)
        machine.apply(.bufferStarted)
        machine.apply(.play)

        XCTAssertEqual(machine.state, .playing)
        XCTAssertNil(machine.failureReason)
    }

    func testFailureKeepsExactReason() {
        var machine = NativePlaybackStateMachine()

        machine.apply(.fail("videoToolboxFormatDescriptionFailed(codecPrivateReason: bad avcC)"))

        XCTAssertEqual(machine.state, .failed)
        XCTAssertEqual(machine.failureReason, "videoToolboxFormatDescriptionFailed(codecPrivateReason: bad avcC)")
    }
}
