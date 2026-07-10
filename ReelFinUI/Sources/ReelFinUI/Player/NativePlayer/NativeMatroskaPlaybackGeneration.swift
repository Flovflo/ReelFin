import Foundation
import NativeMediaCore

typealias NativeMatroskaByteSourceFactory = @Sendable (
    _ url: URL,
    _ headers: [String: String]
) -> any MediaByteSource

struct NativeMatroskaPlaybackGeneration: Equatable {
    enum Phase: Equatable {
        case idle
        case starting
        case active
        case retiring
    }

    private(set) var id = 0
    private(set) var phase: Phase = .idle

    mutating func beginStart() -> Int {
        id += 1
        phase = .starting
        return id
    }

    mutating func markActive(_ candidate: Int) {
        if candidate == id {
            phase = .active
        }
    }

    mutating func beginRetirement() {
        if phase != .idle {
            phase = .retiring
        }
    }

    mutating func finishRetirement(_ candidate: Int) {
        if candidate == id {
            phase = .idle
        }
    }

    func owns(_ candidate: Int) -> Bool {
        candidate == id && phase != .idle
    }

    var canSeekInPlace: Bool { phase == .active }
}
