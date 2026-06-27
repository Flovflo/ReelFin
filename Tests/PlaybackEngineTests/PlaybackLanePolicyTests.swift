@testable import PlaybackEngine
import XCTest

/// The decision brain, fully offline. Proves the ORIGINAL-FIRST / dynamic / loading-bar-not-downgrade
/// / SDR-last-resort behavior the player must have — deterministically, no device, no network.
final class PlaybackLanePolicyTests: XCTestCase {

    // MARK: Startup — always the original lane; dynamic per file bitrate.

    func testStartupComfortableLinkPlaysOriginalNow() {
        // 40 Mbps measured on a 26 Mbps file = 1.54x >= comfortable -> start immediately.
        XCTAssertEqual(
            PlaybackLanePolicy.startupAction(measuredMbps: 40, sourceBitrateMbps: 26),
            .playOriginalNow)
        // Same ratio holds for a totally different file (dynamic): 12 Mbps link, 8 Mbps file = 1.5x.
        XCTAssertEqual(
            PlaybackLanePolicy.startupAction(measuredMbps: 12, sourceBitrateMbps: 8),
            .playOriginalNow)
    }

    func testStartupWeakLinkPrebuffersOriginalWithDynamicTarget() {
        // 20 Mbps on a 26 Mbps file (0.77x, below comfortable) -> pre-buffer the ORIGINAL (loading bar).
        let weak = PlaybackLanePolicy.startupAction(measuredMbps: 20, sourceBitrateMbps: 26)
        guard case let .prebufferOriginal(target) = weak else {
            return XCTFail("Weak link must pre-buffer the original, not play now / not SDR. Got \(weak)")
        }
        XCTAssertGreaterThanOrEqual(target, PlaybackLanePolicy.baseStartupPrebufferSeconds)

        // Weaker link -> deeper cushion (dynamic).
        let weaker = PlaybackLanePolicy.startupAction(measuredMbps: 10, sourceBitrateMbps: 26)
        guard case let .prebufferOriginal(deepTarget) = weaker else { return XCTFail("expected prebuffer") }
        XCTAssertGreaterThan(deepTarget, target, "A weaker link must pre-buffer a deeper cushion.")
    }

    func testStartupFailedProbeStillTriesOriginalWithCushion_neverSDR() {
        // Probe failed/timed out (nil) -> conservative pre-buffer of the ORIGINAL, never SDR up front.
        let action = PlaybackLanePolicy.startupAction(measuredMbps: nil, sourceBitrateMbps: 26)
        guard case .prebufferOriginal = action else {
            return XCTFail("A failed probe must pre-buffer the original (loading bar), not bail. Got \(action)")
        }
    }

    func testStartupBelowBitrateStillOriginalNotSDR() {
        // 8 Mbps on a 26 Mbps file (0.3x) — can't sustain realtime, but we STILL try the original
        // (pre-buffer + loading bar). SDR is decided later, over time, never at startup.
        let action = PlaybackLanePolicy.startupAction(measuredMbps: 8, sourceBitrateMbps: 26)
        guard case .prebufferOriginal = action else {
            return XCTFail("Below-bitrate startup must still try the original. Got \(action)")
        }
    }

    func testStartupPlaysNowIfCushionAlreadyHeld() {
        // Weak link but we already cached the needed cushion (e.g. resume into cached region).
        let action = PlaybackLanePolicy.startupAction(measuredMbps: 20, sourceBitrateMbps: 26, reservoirSecondsAlready: 60)
        XCTAssertEqual(action, .playOriginalNow)
    }

    // MARK: Steady-state — buffer the original, never downgrade on a dip; SDR only sustained.

    func testSteadyHealthyReservoirKeepsPlayingOriginal() {
        XCTAssertEqual(
            PlaybackLanePolicy.steadyAction(reservoirSeconds: 120, isReservoirEmpty: false, sustainedBelowBitrateSeconds: 0),
            .keepPlayingOriginal)
    }

    func testSteadyEmptyReservoirBuffersOriginal_notSDR() {
        // Reservoir ran dry after a transient dropout -> loading bar, rebuild the ORIGINAL. NOT SDR.
        XCTAssertEqual(
            PlaybackLanePolicy.steadyAction(reservoirSeconds: 0, isReservoirEmpty: true, sustainedBelowBitrateSeconds: 20),
            .bufferOriginal)
    }

    func testSteadyMomentaryDipDoesNotDropToSDR() {
        // Below bitrate for only 30s (< lastResortSustainedSeconds) -> keep fighting for the original.
        XCTAssertEqual(
            PlaybackLanePolicy.steadyAction(reservoirSeconds: 0, isReservoirEmpty: true, sustainedBelowBitrateSeconds: 30),
            .bufferOriginal)
    }

    func testSteadySustainedBelowBitrateDropsToSDRLastResort() {
        // Below bitrate continuously past the sustained threshold -> genuine last resort.
        XCTAssertEqual(
            PlaybackLanePolicy.steadyAction(reservoirSeconds: 0, isReservoirEmpty: true,
                sustainedBelowBitrateSeconds: PlaybackLanePolicy.lastResortSustainedSeconds + 1),
            .dropToSDRLastResort)
    }

    // MARK: Resume + loading-bar progress.

    func testCanResumeOnlyAfterRebuildingCushion() {
        XCTAssertFalse(PlaybackLanePolicy.canResumeAfterBuffering(reservoirSeconds: 2))
        XCTAssertTrue(PlaybackLanePolicy.canResumeAfterBuffering(reservoirSeconds: PlaybackLanePolicy.bufferResumeSeconds))
    }

    func testBufferingProgressClamped() {
        XCTAssertEqual(PlaybackLanePolicy.bufferingProgress(reservoirSeconds: 0, targetSeconds: 10), 0)
        XCTAssertEqual(PlaybackLanePolicy.bufferingProgress(reservoirSeconds: 5, targetSeconds: 10), 0.5, accuracy: 0.001)
        XCTAssertEqual(PlaybackLanePolicy.bufferingProgress(reservoirSeconds: 20, targetSeconds: 10), 1)
    }
}
