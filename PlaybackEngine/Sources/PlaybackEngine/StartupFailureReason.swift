import Foundation

/// Structured failure reasons for playback startup.
/// Used to drive deterministic fallback decisions instead of string matching.
public enum StartupFailureReason: String, Sendable, Equatable {
    case manifestLoadFailed = "manifest_load_failed"
    case firstSegmentTimeout = "first_segment_timeout"
    case decodedFrameWatchdog = "decoded_frame_watchdog"
    case readyButNoVideoFrame = "item_ready_but_no_video_frame"
    case decoderStall = "decoder_stall"
    case presentationSizeZero = "video_presentation_size_zero"
    case subtitlePipelineFailure = "subtitle_pipeline_failure"
    case audioPipelineFailure = "audio_pipeline_failure"
    case networkTimeout = "network_timeout"
    case playerItemFailed = "player_item_failed"
    case playerItemFailedTransient = "player_item_failed_transient"
    case startupReadinessTimeout = "startup_readiness_timeout"
    case startupVideoPrerollTimeout = "startup_video_preroll_timeout"
    case directPlayPreflightInsufficient = "directplay_preflight_insufficient"
    case directPlayStall = "directplay_stall"
    case directPlayPostStartStall = "directplay_poststart_stall"
    case startupWatchdogExpired = "startup_watchdog"
    case nativeBridgePackagingFailure = "nativebridge_packaging_failure"
    case unknownStartupFailure = "unknown_startup_failure"

    /// Whether this failure reason should trigger automatic profile fallback recovery.
    public var shouldTriggerRecovery: Bool {
        switch self {
        case .decodedFrameWatchdog, .readyButNoVideoFrame, .decoderStall, .presentationSizeZero,
             .startupReadinessTimeout, .startupVideoPrerollTimeout,
             .directPlayPostStartStall,
             .startupWatchdogExpired, .playerItemFailed, .firstSegmentTimeout:
            return true
        case .manifestLoadFailed, .networkTimeout, .playerItemFailedTransient:
            return false // handled by transient retry path
        case .directPlayPreflightInsufficient, .directPlayStall:
            return false // Direct Play is preserved; controller handles same-route retry/logging.
        case .subtitlePipelineFailure, .audioPipelineFailure:
            return true
        case .nativeBridgePackagingFailure:
            return false // handled separately
        case .unknownStartupFailure:
            return true
        }
    }
}
