import Foundation

/// The decision brain of the custom player — pure, deterministic, fully unit-testable (no AVPlayer,
/// no network). Encodes the ORIGINAL-FIRST, FULLY-DYNAMIC philosophy (blueprint §0):
///
/// - **Keep the original (DV/HDR) whenever at all possible.** SDR transcode is a genuine last
///   resort, decided over TIME, never on a momentary dip (R1, R5).
/// - **Everything relative to THIS file's bitrate.** No hardcoded Mbps — decisions use the ratio
///   `measuredMbps / sourceBitrateMbps` (R2).
/// - **When cache is short, BUILD it behind a loading bar — don't drop quality.** At startup
///   (pre-buffer the original) and mid-stream (buffer the original), surface a loading indicator
///   rather than cut or downgrade (R3, R4).
public enum PlaybackLanePolicy {

    // MARK: - Tunables (ratios + seconds; all dynamic-per-file via the ratio)

    /// At/above this throughput headroom the original starts immediately — the cache fills itself.
    public static let comfortableHeadroom: Double = 1.3
    /// At/above this the link can at least carry realtime, so the original is still viable (with a
    /// pre-buffer cushion). Below it, the link cannot sustain realtime and we lean on the reservoir.
    public static let realtimeHeadroom: Double = 1.0
    /// Pre-buffer cushion (seconds of the original) to build behind the loading bar before starting
    /// on a non-comfortable link. Scales up the weaker the link is (more cushion when it's tighter).
    public static let baseStartupPrebufferSeconds: Double = 10
    public static let maxStartupPrebufferSeconds: Double = 45
    /// Reservoir depth below which playback is "at risk" (informational; the actual buffer event is
    /// AVPlayer running dry).
    public static let lowReservoirSeconds: Double = 4
    /// After a buffer (loading bar) event, rebuild the reservoir to at least this before resuming —
    /// so we don't resume into an immediate re-stall.
    public static let bufferResumeSeconds: Double = 8
    /// Only after the link has SUSTAINABLY failed to carry the original for this long (measured
    /// below the file's own bitrate, continuously) do we fall back to clean SDR. Long on purpose:
    /// keep fighting for the original (R5). A momentary dip never trips this.
    public static let lastResortSustainedSeconds: Double = 90

    // MARK: - Types

    public enum Lane: Equatable { case original, sdrLastResort }

    public enum StartupAction: Equatable {
        /// Start the original immediately (link is comfortable; cache builds itself).
        case playOriginalNow
        /// Build a cushion of the original first, showing a loading bar, then start. Dynamic target.
        case prebufferOriginal(targetSeconds: Double)
    }

    public enum SteadyAction: Equatable {
        /// Keep playing the original.
        case keepPlayingOriginal
        /// Reservoir ran dry — show the loading bar and rebuild the ORIGINAL (do NOT drop quality).
        case bufferOriginal
        /// Genuine, sustained inability to carry the original → clean SDR last resort.
        case dropToSDRLastResort
    }

    // MARK: - Decisions

    /// Startup routing. `measuredMbps == nil` means the probe FAILED/timed out — treat as a weak,
    /// unverified link and pre-buffer the original (never gamble on an instant start, never bail to
    /// SDR up front). Always the original lane at startup.
    public static func startupAction(
        measuredMbps: Double?,
        sourceBitrateMbps: Double,
        reservoirSecondsAlready: Double = 0
    ) -> StartupAction {
        let src = max(0.001, sourceBitrateMbps)
        guard let measuredMbps, measuredMbps > 0 else {
            // Unverified link → conservative cushion (use the weak-end target).
            return .prebufferOriginal(targetSeconds: prebufferTarget(headroom: realtimeHeadroom * 0.6))
        }
        let headroom = measuredMbps / src
        if headroom >= comfortableHeadroom {
            return .playOriginalNow
        }
        let target = prebufferTarget(headroom: headroom)
        // If we somehow already hold the cushion, start now.
        return reservoirSecondsAlready >= target ? .playOriginalNow : .prebufferOriginal(targetSeconds: target)
    }

    /// Weaker link → deeper cushion. Clamped. (≈ base at comfortable, scaling up as headroom falls.)
    public static func prebufferTarget(headroom: Double) -> Double {
        let h = max(0.1, headroom)
        let scaled = baseStartupPrebufferSeconds * (comfortableHeadroom / h)
        return min(maxStartupPrebufferSeconds, max(baseStartupPrebufferSeconds, scaled))
    }

    /// Steady-state. Original-first: only a SUSTAINED below-bitrate window trips the SDR last resort;
    /// a dry reservoir means buffer-the-original (loading bar), not downgrade.
    public static func steadyAction(
        reservoirSeconds: Double,
        isReservoirEmpty: Bool,
        sustainedBelowBitrateSeconds: Double
    ) -> SteadyAction {
        if sustainedBelowBitrateSeconds >= lastResortSustainedSeconds {
            return .dropToSDRLastResort
        }
        if isReservoirEmpty || reservoirSeconds <= 0 {
            return .bufferOriginal
        }
        return .keepPlayingOriginal
    }

    /// True once enough original cushion has rebuilt to resume after a buffering (loading bar) event.
    public static func canResumeAfterBuffering(reservoirSeconds: Double) -> Bool {
        reservoirSeconds >= bufferResumeSeconds
    }

    /// Loading-bar progress (0...1) toward a target cushion.
    public static func bufferingProgress(reservoirSeconds: Double, targetSeconds: Double) -> Double {
        guard targetSeconds > 0 else { return 1 }
        return min(1, max(0, reservoirSeconds / targetSeconds))
    }
}
