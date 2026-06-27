@testable import PlaybackEngine
import XCTest

/// The loading-bar/UI state derived from the decision brain — proves the bar shows exactly when
/// caching the original, hides when playing, and never appears for the playing/degraded phases.
final class PlaybackBufferingStateTests: XCTestCase {

    func testStartupPlayNowIsPlayingNoLoadingBar() {
        let s = PlaybackBufferingState.fromStartup(.playOriginalNow, reservoirSeconds: 12)
        XCTAssertEqual(s.phase, .playing)
        XCTAssertFalse(s.isLoadingBarVisible)
        XCTAssertTrue(s.isPlaying)
    }

    func testStartupPrebufferShowsLoadingBarWithProgress() {
        let s = PlaybackBufferingState.fromStartup(.prebufferOriginal(targetSeconds: 20), reservoirSeconds: 5)
        XCTAssertEqual(s.phase, .prebuffering)
        XCTAssertTrue(s.isLoadingBarVisible)
        XCTAssertEqual(s.progress, 0.25, accuracy: 0.001)
        XCTAssertFalse(s.isPlaying)
    }

    func testSteadyKeepPlayingHidesBar() {
        let s = PlaybackBufferingState.fromSteady(.keepPlayingOriginal, reservoirSeconds: 120)
        XCTAssertEqual(s.phase, .playing)
        XCTAssertFalse(s.isLoadingBarVisible)
    }

    func testSteadyBufferShowsBarRebuildingOriginal() {
        let s = PlaybackBufferingState.fromSteady(.bufferOriginal, reservoirSeconds: 2)
        XCTAssertEqual(s.phase, .buffering)
        XCTAssertTrue(s.isLoadingBarVisible)
        XCTAssertEqual(s.targetSeconds, PlaybackLanePolicy.bufferResumeSeconds)
        XCTAssertFalse(s.isPlaying)
    }

    func testSteadyDegradedIsPlayingSDRNoBar() {
        let s = PlaybackBufferingState.fromSteady(.dropToSDRLastResort, reservoirSeconds: 0)
        XCTAssertEqual(s.phase, .degradedSDR)
        XCTAssertFalse(s.isLoadingBarVisible, "SDR plays — it's a quality drop, not a loading state.")
        XCTAssertTrue(s.isPlaying)
    }

    func testProgressClampsAtFull() {
        let s = PlaybackBufferingState(phase: .prebuffering, reservoirSeconds: 100, targetSeconds: 20)
        XCTAssertEqual(s.progress, 1)
    }
}
