@testable import PlaybackEngine
import XCTest

/// The decision brain, fully offline. Proves the ORIGINAL-FIRST / dynamic / loading-bar-not-downgrade
/// / SDR-last-resort behavior the player must have — deterministically, no device, no network.
final class PlaybackLanePolicyTests: XCTestCase {

    // MARK: Startup — always the original lane; dynamic per file bitrate.

    func testStartupComfortableLinkStartsFastWithSmallCushion() {
        // Fast start ("démarre rapidement"): a strong link (40 Mbps on a 26 Mbps file = 1.54x)
        // only builds the small jitter cushion — reached in ~1-2s — because the reservoir then
        // builds itself behind playback. No 30s gate on a link that outruns the file.
        let strong = PlaybackLanePolicy.startupAction(measuredMbps: 40, sourceBitrateMbps: 26)
        guard case let .prebufferOriginal(target) = strong else {
            return XCTFail("A cold start still builds the small jitter cushion first. Got \(strong)")
        }
        XCTAssertEqual(target, PlaybackLanePolicy.fastStartCushionSeconds, accuracy: 0.001,
                       "A comfortable link gets the FAST cushion, not a deep one.")
        // Dynamic per file: the same 1.5x ratio on a different bitrate also gets the fast cushion.
        guard case let .prebufferOriginal(smallTarget) = PlaybackLanePolicy.startupAction(measuredMbps: 12, sourceBitrateMbps: 8) else {
            return XCTFail("expected fast-cushion prebuffer for a comfortable link")
        }
        XCTAssertEqual(smallTarget, PlaybackLanePolicy.fastStartCushionSeconds, accuracy: 0.001)
    }

    func testStartupUnverifiedLinkUsesMiddleGroundCushion_reDecidedByCaller() {
        // The link hasn't revealed itself yet (cold origin / first samples): a middle-ground
        // cushion, NOT the deep weak-link one — the startup loop re-decides as measurements arrive.
        let action = PlaybackLanePolicy.startupAction(measuredMbps: nil, sourceBitrateMbps: 26)
        guard case let .prebufferOriginal(target) = action else { return XCTFail("expected prebuffer") }
        XCTAssertEqual(target, PlaybackLanePolicy.steadyStartCushionSeconds, accuracy: 0.001)
    }

    func testStartupResumeIntoCachedRegionStartsInstantly() {
        // Everything needed is already on disk → zero wait, whatever the link looks like.
        let action = PlaybackLanePolicy.startupAction(measuredMbps: nil, sourceBitrateMbps: 26,
                                                      reservoirSecondsAlready: PlaybackLanePolicy.steadyStartCushionSeconds)
        XCTAssertEqual(action, .playOriginalNow)
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

    // MARK: Per-title disk budget — evict behind the playhead only when over budget.

    func testEvictionCutoffOnlyWhenOverBudgetAndBehindRewindWindow() {
        // Under budget → keep everything (small titles stay fully cached for offline replay).
        XCTAssertNil(CacheProxySession.EvictionPolicy.evictionCutoff(
            playheadByte: 2_000, rewindBytes: 500, cachedBytes: 900, budgetBytes: 1_000))
        // Over budget → evict strictly behind (playhead - rewind window).
        XCTAssertEqual(CacheProxySession.EvictionPolicy.evictionCutoff(
            playheadByte: 2_000, rewindBytes: 500, cachedBytes: 1_500, budgetBytes: 1_000), 1_500)
        // Early in playback (cutoff would be ≤ 0) → nothing to evict yet.
        XCTAssertNil(CacheProxySession.EvictionPolicy.evictionCutoff(
            playheadByte: 300, rewindBytes: 500, cachedBytes: 1_500, budgetBytes: 1_000))
        // No budget configured → never evict.
        XCTAssertNil(CacheProxySession.EvictionPolicy.evictionCutoff(
            playheadByte: 2_000, rewindBytes: 500, cachedBytes: 1_500, budgetBytes: 0))
    }
}
