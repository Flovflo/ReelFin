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
            return (url, ["X-Emby-Token": token])
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
