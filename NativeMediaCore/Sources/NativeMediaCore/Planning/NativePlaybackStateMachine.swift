import Foundation

public enum NativePlaybackState: String, Codable, Hashable, Sendable {
    case idle
    case resolvingOriginal
    case openingByteSource
    case probing
    case demuxing
    case planning
    case buffering
    case playing
    case paused
    case seeking
    case ended
    case failed
}

public enum NativePlaybackEvent: Equatable, Sendable {
    case beginResolve
    case originalResolved
    case probeStarted
    case demuxStarted
    case planStarted
    case bufferStarted
    case play
    case pause
    case seek
    case end
    case fail(String)
    case reset
}

public struct NativePlaybackStateMachine: Sendable, Equatable {
    public private(set) var state: NativePlaybackState
    public private(set) var failureReason: String?

    public init(state: NativePlaybackState = .idle, failureReason: String? = nil) {
        self.state = state
        self.failureReason = failureReason
    }

    public mutating func apply(_ event: NativePlaybackEvent) {
        switch event {
        case .beginResolve:
            state = .resolvingOriginal
            failureReason = nil
        case .originalResolved:
            state = .openingByteSource
        case .probeStarted:
            state = .probing
        case .demuxStarted:
            state = .demuxing
        case .planStarted:
            state = .planning
        case .bufferStarted:
            state = .buffering
        case .play:
            state = .playing
        case .pause:
            state = .paused
        case .seek:
            state = .seeking
        case .end:
            state = .ended
        case .fail(let reason):
            state = .failed
            failureReason = reason
        case .reset:
            state = .idle
            failureReason = nil
        }
    }
}
