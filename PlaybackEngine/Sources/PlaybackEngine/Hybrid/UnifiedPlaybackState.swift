import Foundation

// MARK: - Unified Playback State Machine

/// Engine-agnostic playback state.
/// Both AVPlayer and VLCKit events are normalized into these states.
public enum UnifiedPlaybackState: String, Sendable, Equatable, CaseIterable {
    case idle
    case preparing
    case ready
    case playing
    case paused
    case buffering
    case seeking
    case stalled
    case retrying
    case ended
    case failed

    /// Whether the state represents active media engagement (not idle/failed/ended).
    public var isActive: Bool {
        switch self {
        case .preparing, .ready, .playing, .paused, .buffering, .seeking, .stalled, .retrying:
            return true
        case .idle, .ended, .failed:
            return false
        }
    }

    /// Whether the state should show a loading indicator.
    public var isLoading: Bool {
        switch self {
        case .preparing, .buffering, .stalled, .retrying:
            return true
        default:
            return false
        }
    }
}

// MARK: - State Machine

/// Validates and manages playback state transitions.
/// Thread-safe: use from @MainActor context.
@MainActor
public final class PlaybackStateMachine {
    public private(set) var state: UnifiedPlaybackState = .idle
    public private(set) var previousState: UnifiedPlaybackState = .idle
    public private(set) var stateEnteredAt: Date = Date()

    /// Called on every state transition. Useful for diagnostics.
    public var onTransition: ((UnifiedPlaybackState, UnifiedPlaybackState) -> Void)?

    public init() {}

    /// Attempt a state transition. Returns true if the transition was valid.
    @discardableResult
    public func transition(to newState: UnifiedPlaybackState) -> Bool {
        guard isValidTransition(from: state, to: newState) else {
            return false
        }
        let oldState = state
        previousState = oldState
        state = newState
        stateEnteredAt = Date()
        onTransition?(oldState, newState)
        return true
    }

    /// Force a state without validation (for error recovery).
    public func forceState(_ newState: UnifiedPlaybackState) {
        previousState = state
        state = newState
        stateEnteredAt = Date()
        onTransition?(previousState, newState)
    }

    /// Reset to idle.
    public func reset() {
        previousState = state
        state = .idle
        stateEnteredAt = Date()
    }

    /// Duration spent in current state.
    public var timeInCurrentState: TimeInterval {
        Date().timeIntervalSince(stateEnteredAt)
    }

    // MARK: - Transition Validation

    private func isValidTransition(from: UnifiedPlaybackState, to: UnifiedPlaybackState) -> Bool {
        // Always allow transition to failed or idle (reset)
        if to == .failed || to == .idle { return true }

        switch from {
        case .idle:
            return to == .preparing
        case .preparing:
            return [.ready, .playing, .buffering, .failed, .retrying].contains(to)
        case .ready:
            return [.playing, .paused, .buffering, .failed].contains(to)
        case .playing:
            return [.paused, .buffering, .seeking, .stalled, .ended, .failed].contains(to)
        case .paused:
            return [.playing, .seeking, .buffering, .ended, .failed].contains(to)
        case .buffering:
            return [.playing, .paused, .stalled, .ready, .failed, .retrying].contains(to)
        case .seeking:
            return [.playing, .paused, .buffering, .failed].contains(to)
        case .stalled:
            return [.buffering, .playing, .retrying, .failed].contains(to)
        case .retrying:
            return [.preparing, .playing, .buffering, .failed].contains(to)
        case .ended:
            return to == .preparing // allow replay
        case .failed:
            return to == .preparing || to == .retrying // allow retry
        }
    }
}
