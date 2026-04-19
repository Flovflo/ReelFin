import CryptoKit
import Foundation

public struct MediaGatewayCacheKey: Sendable, Codable, Hashable {
    public static let currentVersion = 1
    public static let resumeBucketDurationSeconds: Double = 30

    public let version: Int
    public let scope: String?
    public let userID: String?
    public let serverID: String?
    public let itemID: String
    public let sourceID: String
    public let routeSignature: String
    public let audioSignature: String
    public let subtitleSignature: String
    public let resumeBucket: Int

    public init(
        scope: String? = nil,
        userID: String? = nil,
        serverID: String? = nil,
        itemID: String,
        sourceID: String,
        routeSignature: String,
        audioSignature: String = "default",
        subtitleSignature: String = "default",
        resumeSeconds: Double? = nil,
        version: Int = Self.currentVersion
    ) {
        self.version = version
        self.scope = Self.normalized(scope)
        self.userID = Self.normalized(userID)
        self.serverID = Self.normalized(serverID)
        self.itemID = Self.normalizedRequired(itemID)
        self.sourceID = Self.normalizedRequired(sourceID)
        self.routeSignature = Self.normalizedRequired(routeSignature)
        self.audioSignature = Self.normalizedRequired(audioSignature)
        self.subtitleSignature = Self.normalizedRequired(subtitleSignature)
        self.resumeBucket = Self.resumeBucket(for: resumeSeconds)
    }

    public init(
        scope: String? = nil,
        userID: String? = nil,
        serverID: String? = nil,
        itemID: String,
        sourceID: String,
        routeURL: URL,
        routeHeaders: [String: String] = [:],
        audioSignature: String = "default",
        subtitleSignature: String = "default",
        resumeSeconds: Double? = nil,
        version: Int = Self.currentVersion
    ) {
        self.init(
            scope: scope,
            userID: userID,
            serverID: serverID,
            itemID: itemID,
            sourceID: sourceID,
            routeSignature: Self.routeSignature(for: routeURL, headers: routeHeaders),
            audioSignature: audioSignature,
            subtitleSignature: subtitleSignature,
            resumeSeconds: resumeSeconds,
            version: version
        )
    }

    public static func routeSignature(
        for url: URL,
        headers: [String: String] = [:],
        method: String = "GET"
    ) -> String {
        let preimage = canonicalRoutePreimage(url: url, headers: headers, method: method)
        return digest(preimage)
    }

    public static func resumeBucket(for resumeSeconds: Double?) -> Int {
        guard let resumeSeconds, resumeSeconds.isFinite, resumeSeconds > 0 else {
            return 0
        }
        return Int(floor(resumeSeconds / resumeBucketDurationSeconds))
    }

    var storageIdentity: String {
        [
            "v:\(version)",
            "scope:\(scope ?? "-")",
            "user:\(userID ?? "-")",
            "server:\(serverID ?? "-")",
            "item:\(itemID)",
            "source:\(sourceID)",
            "route:\(routeSignature)",
            "audio:\(audioSignature)",
            "subtitle:\(subtitleSignature)",
            "resume:\(resumeBucket)"
        ].joined(separator: "|")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedRequired(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    private static func canonicalRoutePreimage(url: URL, headers: [String: String], method: String) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let scheme = components?.scheme?.lowercased() ?? url.scheme?.lowercased() ?? ""
        let host = components?.host?.lowercased() ?? url.host?.lowercased() ?? ""
        let port = components?.port.map(String.init) ?? ""
        let path: String
        if let encodedPath = components?.percentEncodedPath, !encodedPath.isEmpty {
            path = encodedPath
        } else {
            path = url.path.isEmpty ? "/" : url.path
        }

        let query = canonicalQuerySignature(components?.queryItems ?? [])
        let headerSignature = canonicalHeaderSignature(headers)

        return [
            "method=\(method.uppercased())",
            "scheme=\(scheme)",
            "host=\(host)",
            "port=\(port)",
            "path=\(path)",
            "query=\(query)",
            "headers=\(headerSignature)"
        ].joined(separator: "|")
    }

    private static func canonicalQuerySignature(_ items: [URLQueryItem]) -> String {
        guard !items.isEmpty else { return "-" }

        return items
            .map { item in
                let name = item.name.lowercased()
                let value = item.value ?? ""
                return "\(name)=\(digest(value))"
            }
            .sorted()
            .joined(separator: "&")
    }

    private static func canonicalHeaderSignature(_ headers: [String: String]) -> String {
        guard !headers.isEmpty else { return "-" }

        return headers
            .map { key, value in
                "\(key.lowercased())=\(digest(value))"
            }
            .sorted()
            .joined(separator: "&")
    }

    private static func digest(_ value: String) -> String {
        let hash = SHA256.hash(data: Data(value.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
