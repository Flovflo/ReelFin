import Foundation
import Network

/// Shared boundary for the two HTTP servers that expose playback bytes to AVFoundation.
///
/// A capability is deliberately part of the path rather than a query/header: AVPlayer may issue
/// follow-up range and playlist requests itself, while an exact opaque path segment remains stable.
struct LocalPlaybackServerSecurity: Sendable {
    enum RouteClass: String, Sendable {
        case masterPlaylist = "master_playlist"
        case mediaPlaylist = "media_playlist"
        case initialization = "initialization"
        case mediaSegment = "media_segment"
        case media = "media"
        case unknown = "unknown"
        case unauthorized = "unauthorized"
    }

    enum SecurityError: Error {
        case invalidCapabilityLength
        case invalidListenerEndpoint
    }

    struct ConfiguredListener {
        let listener: NWListener
        let requiredLocalEndpoint: NWEndpoint
    }

    static let capabilityByteCount = 32
    /// iOS 26.5 measured a peak of 12 simultaneous cache-server connections across AVPlayer
    /// startup, metadata, ranges, seek/reread, and replay. Twenty-four preserves 100% headroom.
    static let defaultConnectionCapacity = 24
    static let loopbackEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)

    let capabilityPathComponent: String

    init() {
        var generator = SystemRandomNumberGenerator()
        let bytes = Data((0..<Self.capabilityByteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        self.capabilityPathComponent = bytes.map { String(format: "%02x", $0) }.joined()
    }

    init(capabilityBytes: Data) throws {
        guard capabilityBytes.count == Self.capabilityByteCount else {
            throw SecurityError.invalidCapabilityLength
        }
        self.capabilityPathComponent = capabilityBytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the resource path only when the request target is already canonical and its first
    /// slash-delimited component equals this session's capability byte-for-byte.
    func authorizedResourcePath(for requestTarget: String) -> String? {
        guard requestTarget.hasPrefix("/"),
              !requestTarget.contains("%"),
              !requestTarget.contains("?"),
              !requestTarget.contains("#") else {
            return nil
        }

        let components = requestTarget.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 3,
              components[0].isEmpty,
              components[1] == capabilityPathComponent,
              components.dropFirst(2).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return "/" + components.dropFirst(2).joined(separator: "/")
    }

    func baseURL(port: NWEndpoint.Port) -> URL? {
        URL(string: "http://127.0.0.1:\(port.rawValue)/\(capabilityPathComponent)/")
    }

    func routeClass(for requestTarget: String) -> RouteClass {
        guard let resource = authorizedResourcePath(for: requestTarget) else { return .unauthorized }
        switch resource {
        case "/master.m3u8": return .masterPlaylist
        case "/video.m3u8": return .mediaPlaylist
        case "/init.mp4": return .initialization
        case "/media": return .media
        default:
            return Self.canonicalSegmentSequence(forResourcePath: resource) == nil ? .unknown : .mediaSegment
        }
    }

    static func canonicalSegmentSequence(forResourcePath resourcePath: String) -> Int? {
        let prefix = "/segment_"
        let suffix = ".m4s"
        guard resourcePath.hasPrefix(prefix), resourcePath.hasSuffix(suffix) else { return nil }
        let sequenceStart = resourcePath.index(resourcePath.startIndex, offsetBy: prefix.count)
        let sequenceEnd = resourcePath.index(resourcePath.endIndex, offsetBy: -suffix.count)
        let rawSequence = resourcePath[sequenceStart..<sequenceEnd]
        guard !rawSequence.isEmpty,
              rawSequence.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
              let sequence = Int(rawSequence),
              sequence >= 0,
              rawSequence == String(sequence) else {
            return nil
        }
        return sequence
    }

    /// A bounded diagnostic projection. Callers must never interpolate a capability-bearing URL.
    static func logProjection(for routeClass: RouteClass) -> String {
        "route=\(routeClass.rawValue)"
    }

    static func makeLoopbackListener() throws -> ConfiguredListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = loopbackEndpoint
        let listener = try NWListener(using: parameters)
        return ConfiguredListener(listener: listener, requiredLocalEndpoint: loopbackEndpoint)
    }
}

/// Synchronous admission gate used before allocating a per-connection Task.
final class LocalPlaybackConnectionGate: @unchecked Sendable {
    struct Snapshot: Equatable {
        let active: Int
        let peak: Int
        let rejected: Int
    }

    final class Lease: @unchecked Sendable {
        private let lock = NSLock()
        private var releaseAction: (() -> Void)?

        fileprivate init(releaseAction: @escaping () -> Void) {
            self.releaseAction = releaseAction
        }

        func release() {
            let action = lock.withLock { () -> (() -> Void)? in
                defer { releaseAction = nil }
                return releaseAction
            }
            action?()
        }

        deinit {
            release()
        }
    }

    private let lock = NSLock()
    private let capacity: Int?
    private var active = 0
    private var peak = 0
    private var rejected = 0

    /// A nil capacity disables refusal while retaining the peak counter for measurement runs.
    init(capacity: Int?) {
        self.capacity = capacity
    }

    func acquire() -> Lease? {
        let admitted = lock.withLock { () -> Bool in
            if let capacity, active >= capacity {
                rejected += 1
                return false
            }
            active += 1
            peak = max(peak, active)
            return true
        }
        guard admitted else { return nil }
        return Lease { [weak self] in self?.release() }
    }

    var snapshot: Snapshot {
        lock.withLock { Snapshot(active: active, peak: peak, rejected: rejected) }
    }

    private func release() {
        lock.withLock {
            precondition(active > 0, "Connection admission released more often than acquired.")
            active -= 1
        }
    }
}
