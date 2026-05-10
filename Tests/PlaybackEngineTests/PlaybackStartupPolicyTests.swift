import PlaybackEngine
import XCTest

final class PlaybackStartupPolicyTests: XCTestCase {
    func testStartupPolicyUsesRouteClassBufferTargets() {
        XCTAssertEqual(PlaybackStartupPolicy.configuration(for: .directLocal).preferredForwardBufferDuration, 0.75)
        XCTAssertEqual(PlaybackStartupPolicy.configuration(for: .directLAN).preferredForwardBufferDuration, 1.0)
        XCTAssertEqual(PlaybackStartupPolicy.configuration(for: .remoteDirect).preferredForwardBufferDuration, 2.0)
        XCTAssertEqual(PlaybackStartupPolicy.configuration(for: .hlsRemux).preferredForwardBufferDuration, 3.0)
        XCTAssertEqual(PlaybackStartupPolicy.configuration(for: .transcode).preferredForwardBufferDuration, 5.0)
    }

    func testStartupPolicyOnlyUsesPlayImmediatelyForDirectOriginalClasses() {
        XCTAssertTrue(PlaybackStartupPolicy.configuration(for: .directLAN).usePlayImmediatelyWhenReady)
        XCTAssertTrue(PlaybackStartupPolicy.configuration(for: .remoteDirect).usePlayImmediatelyWhenReady)
        XCTAssertFalse(PlaybackStartupPolicy.configuration(for: .hlsRemux).usePlayImmediatelyWhenReady)
        XCTAssertFalse(PlaybackStartupPolicy.configuration(for: .transcode).usePlayImmediatelyWhenReady)
    }
}
