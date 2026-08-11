import Foundation
import Shared

public struct OriginalMediaRequest: Sendable, Equatable {
    public var itemID: String
    public var mediaSourceID: String?
    public var startTimeTicks: Int64?

    public init(itemID: String, mediaSourceID: String? = nil, startTimeTicks: Int64? = nil) {
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.startTimeTicks = startTimeTicks
    }
}

public enum OriginalMediaAuthPolicy: Sendable, Equatable {
    case queryAPIKey
    case header

    func apply(to url: URL, token: String) -> (url: URL, headers: [String: String]) {
        if url.isFileURL {
            return (url, [:])
        }
        switch self {
        case .header:
            let headers = PlaybackAuthenticationHeaders.jellyfin(token: token)
            return (PlaybackAuthenticatedRequestURL.forInternalURLSession(url, headers: headers), headers)
        case .queryAPIKey:
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return (url, [:])
            }
            var query = components.queryItems ?? []
            if !query.contains(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame }) {
                query.append(URLQueryItem(name: "api_key", value: token))
            }
            components.queryItems = query
            return (components.url ?? url, [:])
        }
    }
}

public struct OriginalMediaResolution: Sendable, Equatable {
    public var url: URL
    public var headers: [String: String]
    public var mediaSource: MediaSource
    public var selectedPath: String
    public var originalMediaRequested: Bool
    public var serverTranscodeUsed: Bool

    public var redactedURLDescription: String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<invalid-url>"
        }
        components.queryItems = components.queryItems?.map {
            $0.name.caseInsensitiveCompare("api_key") == .orderedSame
                ? URLQueryItem(name: $0.name, value: "<redacted>")
                : $0
        }
        return components.url?.absoluteString ?? "<invalid-url>"
    }
}

final class NativeOriginalSourceHandoffClaim: @unchecked Sendable {
    fileprivate let id = UUID()
    private let lock = NSLock()
    private var source: MediaSource?
    private let createdAtUptime: TimeInterval
    private let ttl: TimeInterval
    private let now: @Sendable () -> TimeInterval

    init(
        source: MediaSource,
        createdAtUptime: TimeInterval,
        ttl: TimeInterval,
        now: @escaping @Sendable () -> TimeInterval
    ) {
        self.source = source
        self.createdAtUptime = createdAtUptime
        self.ttl = ttl
        self.now = now
    }

    var isAvailable: Bool {
        lock.withLock {
            source != nil && max(0, now() - createdAtUptime) < ttl
        }
    }

    fileprivate func consume() -> MediaSource? {
        lock.withLock {
            guard source != nil, max(0, now() - createdAtUptime) < ttl else {
                source = nil
                return nil
            }
            defer { source = nil }
            return source
        }
    }

    fileprivate func invalidate() {
        lock.withLock { source = nil }
    }
}

/// One-shot bridge between CustomPlayer's already-completed PlaybackInfo selection and the native
/// packet-demuxed player that replaces it. Only source metadata crosses the handoff; the native
/// controller rebuilds authentication from its current session, so an adaptive PlaySession URL or
/// stale token can never be reused.
actor NativeOriginalSourceHandoffStore {
    static let shared = NativeOriginalSourceHandoffStore()

    struct Key: Hashable, Sendable {
        let itemID: String
        let startTimeTicks: Int64?
        let session: PlaybackCoordinator.AuthenticatedSessionScope
    }

    private var entries: [Key: NativeOriginalSourceHandoffClaim] = [:]
    private var insertionOrder: [Key] = []
    private let ttl: TimeInterval
    private let capacity: Int
    private let now: @Sendable () -> TimeInterval

    init(
        ttl: TimeInterval = 180,
        capacity: Int = 64,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.ttl = ttl
        self.capacity = max(1, capacity)
        self.now = now
    }

    @discardableResult
    func offer(source: MediaSource, for key: Key) -> NativeOriginalSourceHandoffClaim {
        trimExpired()
        if let replaced = entries.removeValue(forKey: key) {
            replaced.invalidate()
            insertionOrder.removeAll { $0 == key }
        }
        let claim = NativeOriginalSourceHandoffClaim(
            source: source,
            createdAtUptime: now(),
            ttl: ttl,
            now: now
        )
        entries[key] = claim
        insertionOrder.append(key)
        while entries.count > capacity, let oldest = insertionOrder.first {
            insertionOrder.removeFirst()
            entries.removeValue(forKey: oldest)?.invalidate()
        }
        return claim
    }

    func consume(for key: Key) -> MediaSource? {
        trimExpired()
        if let exact = removeClaim(for: key)?.consume() {
            return exact
        }
        // A raw original-file resolution is independent of the client-side resume offset. A
        // focus warm therefore may resolve from start, while the native snapshot still carries
        // the exact requested ticks into its demux seek. Item and authenticated session remain
        // part of the key; adaptive/session URLs are never offered to this store.
        guard key.startTimeTicks != nil else { return nil }
        let fromStartKey = Key(itemID: key.itemID, startTimeTicks: nil, session: key.session)
        return removeClaim(for: fromStartKey)?.consume()
    }

    private func trimExpired() {
        for key in insertionOrder where entries[key]?.isAvailable == false {
            entries.removeValue(forKey: key)?.invalidate()
        }
        insertionOrder.removeAll { entries[$0] == nil }
    }

    private func removeClaim(for key: Key) -> NativeOriginalSourceHandoffClaim? {
        insertionOrder.removeAll { $0 == key }
        return entries.removeValue(forKey: key)
    }
}

public struct OriginalMediaURLBuilder: Sendable {
    public init() {}

    public func build(request: OriginalMediaRequest, source: MediaSource, configuration: ServerConfiguration) -> URL {
        var url = configuration.serverURL
            .appendingPathComponent("Videos")
            .appendingPathComponent(request.itemID)
            .appendingPathComponent(staticStreamLeaf(for: source))
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var query = components.queryItems ?? []
        if configuration.serverURL.isFileURL {
            return url
        }
        query.append(URLQueryItem(name: "static", value: "true"))
        query.append(URLQueryItem(name: "MediaSourceId", value: request.mediaSourceID ?? source.id))
        components.queryItems = query
        url = components.url ?? url
        return url
    }

    private func staticStreamLeaf(for source: MediaSource) -> String {
        if let filePath = source.filePath {
            let fileExtension = URL(fileURLWithPath: filePath).pathExtension.lowercased()
            if Self.appleStableStreamExtensions.contains(fileExtension) {
                return "stream.\(fileExtension)"
            }
        }

        let containerTokens = (source.container ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        for candidate in ["mp4", "m4v", "mov"] where containerTokens.contains(candidate) {
            return "stream.\(candidate)"
        }
        return "stream"
    }

    private static let appleStableStreamExtensions: Set<String> = ["mp4", "m4v", "mov"]
}

public struct OriginalMediaResolver: Sendable {
    private let builder: OriginalMediaURLBuilder
    private let authPolicy: OriginalMediaAuthPolicy

    public init(builder: OriginalMediaURLBuilder = OriginalMediaURLBuilder(), authPolicy: OriginalMediaAuthPolicy = .queryAPIKey) {
        self.builder = builder
        self.authPolicy = authPolicy
    }

    public func resolve(
        request: OriginalMediaRequest,
        sources: [MediaSource],
        configuration: ServerConfiguration,
        session: UserSession,
        nativeConfig: NativePlayerConfig
    ) throws -> OriginalMediaResolution {
        guard nativeConfig.alwaysRequestOriginalFile else {
            throw OriginalMediaResolverError.originalFirstDisabled
        }
        guard let source = selectSource(request: request, sources: sources) else {
            throw OriginalMediaResolverError.noMediaSource
        }
        let unsigned = builder.build(request: request, source: source, configuration: configuration)
        let auth = authPolicy.apply(to: unsigned, token: session.token)
        return OriginalMediaResolution(
            url: auth.url,
            headers: auth.headers.merging(source.requiredHTTPHeaders) { current, _ in current },
            mediaSource: source,
            selectedPath: "static-original-stream",
            originalMediaRequested: true,
            serverTranscodeUsed: false
        )
    }

    private func selectSource(request: OriginalMediaRequest, sources: [MediaSource]) -> MediaSource? {
        if let id = request.mediaSourceID, let match = sources.first(where: { $0.id == id }) {
            return match
        }
        return sources.sorted {
            ($0.bitrate ?? 0, $0.fileSize ?? 0) > ($1.bitrate ?? 0, $1.fileSize ?? 0)
        }.first
    }
}

public enum OriginalMediaResolverError: LocalizedError, Sendable, Equatable {
    case noMediaSource
    case originalFirstDisabled

    public var errorDescription: String? {
        switch self {
        case .noMediaSource:
            return "Jellyfin did not return a media source for original-file playback."
        case .originalFirstDisabled:
            return "Native engine playback requires alwaysRequestOriginalFile=true."
        }
    }
}

public actor OriginalMediaSessionReporter {
    public init() {}

    public func reportResolved(_ resolution: OriginalMediaResolution) {
        _ = resolution.redactedURLDescription
    }
}
