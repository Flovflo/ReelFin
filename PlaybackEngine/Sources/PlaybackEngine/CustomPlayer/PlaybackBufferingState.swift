import Foundation

/// UI-facing playback/loading state — what the player view binds to in order to show a loading bar
/// while the original is being cached (blueprint §0-R3: keep the original, show progress, never a
/// silent freeze or a quality drop). Pure value type derived from the decision brain's output +
/// the live reservoir depth, so it is fully unit-testable.
public struct PlaybackBufferingState: Equatable, Sendable {
    public enum Phase: String, Sendable, Equatable {
        case idle          // nothing loaded
        case prebuffering  // building the original cushion before first play (loading bar)
        case playing       // original playing smoothly
        case buffering     // reservoir ran dry mid-play; rebuilding the original (loading bar)
        case degradedSDR   // last-resort clean SDR (link sustainably couldn't carry the original)
    }

    public let phase: Phase
    /// Seconds of the ORIGINAL cached ahead of the playhead right now.
    public let reservoirSeconds: Double
    /// The cushion we're building toward (for the loading-bar denominator).
    public let targetSeconds: Double

    public init(phase: Phase, reservoirSeconds: Double = 0, targetSeconds: Double = 0) {
        self.phase = phase
        self.reservoirSeconds = reservoirSeconds
        self.targetSeconds = targetSeconds
    }

    public static let idle = PlaybackBufferingState(phase: .idle)

    /// Show the loading bar only while actively building cache (pre-buffer or mid-play buffer).
    public var isLoadingBarVisible: Bool { phase == .prebuffering || phase == .buffering }

    /// 0...1 progress for the loading bar.
    public var progress: Double {
        PlaybackLanePolicy.bufferingProgress(reservoirSeconds: reservoirSeconds, targetSeconds: targetSeconds)
    }

    /// Is the user currently seeing motion (or about to)?
    public var isPlaying: Bool { phase == .playing || phase == .degradedSDR }

    // MARK: - Derivation from the decision brain

    /// Map a startup decision to the initial UI state.
    public static func fromStartup(_ action: PlaybackLanePolicy.StartupAction, reservoirSeconds: Double) -> PlaybackBufferingState {
        switch action {
        case .playOriginalNow:
            return PlaybackBufferingState(phase: .playing, reservoirSeconds: reservoirSeconds)
        case let .prebufferOriginal(target):
            return PlaybackBufferingState(phase: .prebuffering, reservoirSeconds: reservoirSeconds, targetSeconds: target)
        }
    }

    /// Map a steady-state decision (+ live reservoir) to the UI state. `bufferResumeSeconds` is the
    /// cushion the loading bar measures against while rebuffering.
    public static func fromSteady(_ action: PlaybackLanePolicy.SteadyAction, reservoirSeconds: Double) -> PlaybackBufferingState {
        switch action {
        case .keepPlayingOriginal:
            return PlaybackBufferingState(phase: .playing, reservoirSeconds: reservoirSeconds)
        case .bufferOriginal:
            return PlaybackBufferingState(phase: .buffering, reservoirSeconds: reservoirSeconds,
                                          targetSeconds: PlaybackLanePolicy.bufferResumeSeconds)
        case .dropToSDRLastResort:
            return PlaybackBufferingState(phase: .degradedSDR, reservoirSeconds: reservoirSeconds)
        }
    }
}
