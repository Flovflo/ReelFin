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

    func testStartupTraceNeverReportsNegativeElapsedTimeWhenWallClockMovesBackward() {
        let trace = PlaybackStartupTrace()
        let start = Date(timeIntervalSince1970: 10)
        let end = Date(timeIntervalSince1970: 9)

        XCTAssertEqual(trace.milliseconds(from: start, to: end), 0)
    }

    func testMonotonicStartupStagesCarryBuildPlatformAndSession() {
        var trace = PlaybackStartupStageTrace(
            sessionID: "session-1",
            build: "42",
            platform: "iOS",
            startedAtUptime: 100
        )

        let resolution = trace.mark("native-resolution-complete", uptime: 100.125)
        let presented = trace.mark("player-presented", uptime: 100.5)

        XCTAssertEqual(trace.sessionID, "session-1")
        XCTAssertEqual(trace.build, "42")
        XCTAssertEqual(trace.platform, "iOS")
        XCTAssertEqual(resolution.elapsedMilliseconds, 125, accuracy: 0.001)
        XCTAssertEqual(presented.elapsedMilliseconds, 500, accuracy: 0.001)
    }
}
