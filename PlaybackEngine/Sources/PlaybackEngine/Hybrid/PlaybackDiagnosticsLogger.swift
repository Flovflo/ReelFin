import Foundation
import Shared

// MARK: - Structured Playback Diagnostics Logger

/// Emits structured diagnostics for every playback decision and event.
/// Log lines use [PLAYBACK-*] tags with key=value pairs for machine parsing.
public struct PlaybackDiagnosticsLogger: Sendable {

    public init() {}

    // MARK: - Decision Logging

    public func logDecision(
        itemID: String,
        decision: EngineCapabilityDecision,
        media: MediaCharacteristics,
        selectedEngine: PlaybackEngineType
    ) {
        let reasons = decision.reasons.map(\.rawValue).joined(separator: ",")
        AppLog.playback.notice(
            """
            [PLAYBACK-DECISION] item=\(itemID, privacy: .public) \
            engine=\(selectedEngine.rawValue, privacy: .public) \
            recommendation=\(decision.recommendation.rawValue, privacy: .public) \
            startupRisk=\(decision.startupRisk.rawValue, privacy: .public) \
            subtitleRisk=\(decision.subtitleRisk.rawValue, privacy: .public) \
            audioRisk=\(decision.audioRisk.rawValue, privacy: .public) \
            hdrExpectation=\(decision.hdrExpectation.rawValue, privacy: .public) \
            featureCompleteness=\(decision.estimatedFeatureCompleteness, format: .fixed(precision: 2)) \
            container=\(media.container ?? "unknown", privacy: .public) \
            videoCodec=\(media.videoCodec ?? "unknown", privacy: .public) \
            audioCodec=\(media.audioCodec ?? "unknown", privacy: .public) \
            bitDepth=\(media.bitDepth.map(String.init) ?? "unknown", privacy: .public) \
            reasons=\(reasons, privacy: .public)
            """
        )
    }

    // MARK: - Engine Events

    public func logEngineStartup(engine: PlaybackEngineType, url: String, itemID: String) {
        AppLog.playback.notice(
            "[PLAYBACK-ENGINE] event=startup engine=\(engine.rawValue, privacy: .public) item=\(itemID, privacy: .public) url=\(url, privacy: .public)"
        )
    }

    public func logEngineReady(engine: PlaybackEngineType, setupMs: Double, itemID: String) {
        AppLog.playback.notice(
            "[PLAYBACK-ENGINE] event=ready engine=\(engine.rawValue, privacy: .public) item=\(itemID, privacy: .public) setupMs=\(setupMs, format: .fixed(precision: 1))"
        )
    }

    public func logEngineError(engine: PlaybackEngineType, error: String, itemID: String) {
        AppLog.playback.error(
            "[PLAYBACK-ENGINE] event=error engine=\(engine.rawValue, privacy: .public) item=\(itemID, privacy: .public) error=\(error, privacy: .public)"
        )
    }

    // MARK: - Startup Timing

    public func logStartupMetrics(_ metrics: PlaybackStartupMetrics, itemID: String) {
        AppLog.playback.notice(
            """
            [PLAYBACK-STARTUP] item=\(itemID, privacy: .public) \
            engine=\(metrics.selectedEngine?.rawValue ?? "unknown", privacy: .public) \
            tapToDecisionMs=\(metrics.tapToDecisionMs.map { String(format: "%.1f", $0) } ?? "n/a", privacy: .public) \
            decisionToSetupMs=\(metrics.decisionToPlayerSetupMs.map { String(format: "%.1f", $0) } ?? "n/a", privacy: .public) \
            setupToFirstFrameMs=\(metrics.playerSetupToFirstFrameMs.map { String(format: "%.1f", $0) } ?? "n/a", privacy: .public) \
            tapToFirstFrameMs=\(metrics.tapToFirstFrameMs.map { String(format: "%.1f", $0) } ?? "n/a", privacy: .public) \
            bufferingEvents=\(metrics.bufferingEventsBeforeFirstFrame, privacy: .public) \
            retries=\(metrics.startupRetryCount, privacy: .public) \
            fallback=\(metrics.fallbackOccurred, privacy: .public) \
            fallbackReason=\(metrics.fallbackReason ?? "none", privacy: .public)
            """
        )
    }

    // MARK: - Fallback Logging

    public func logFallback(
        from: PlaybackEngineType,
        to: PlaybackEngineType,
        reason: String,
        itemID: String
    ) {
        AppLog.playback.warning(
            "[PLAYBACK-FALLBACK] item=\(itemID, privacy: .public) from=\(from.rawValue, privacy: .public) to=\(to.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    // MARK: - State Transitions

    public func logStateTransition(from: UnifiedPlaybackState, to: UnifiedPlaybackState, engine: PlaybackEngineType, itemID: String) {
        AppLog.playback.debug(
            "[PLAYBACK-STATE] item=\(itemID, privacy: .public) engine=\(engine.rawValue, privacy: .public) from=\(from.rawValue, privacy: .public) to=\(to.rawValue, privacy: .public)"
        )
    }

    // MARK: - HDR Decisions

    public func logHDRDecision(
        itemID: String,
        engine: PlaybackEngineType,
        hdrExpectation: HDRExpectation,
        preservationFactor: Bool,
        reason: String
    ) {
        AppLog.playback.notice(
            "[PLAYBACK-HDR] item=\(itemID, privacy: .public) engine=\(engine.rawValue, privacy: .public) expectation=\(hdrExpectation.rawValue, privacy: .public) preserved=\(preservationFactor, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    // MARK: - Audio/Subtitle

    public func logAudioSelection(itemID: String, engine: PlaybackEngineType, trackID: String?, codec: String?) {
        AppLog.playback.debug(
            "[PLAYBACK-AUDIO] item=\(itemID, privacy: .public) engine=\(engine.rawValue, privacy: .public) trackID=\(trackID ?? "none", privacy: .public) codec=\(codec ?? "unknown", privacy: .public)"
        )
    }

    public func logSubtitleSelection(itemID: String, engine: PlaybackEngineType, trackID: String?, codec: String?) {
        AppLog.playback.debug(
            "[PLAYBACK-SUBS] item=\(itemID, privacy: .public) engine=\(engine.rawValue, privacy: .public) trackID=\(trackID ?? "disabled", privacy: .public) codec=\(codec ?? "unknown", privacy: .public)"
        )
    }
}
