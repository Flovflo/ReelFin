import CryptoKit
import Foundation

public final class DefaultSettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    private struct StoredSessionIdentity: Codable {
        let userID: String
        let username: String
    }

    private enum Keys {
        static let serverConfiguration = "settings.serverConfiguration"
        static let lastSession = "settings.lastSession"
        static let episodeReleaseNotificationsEnabled = "settings.episodeReleaseNotificationsEnabled"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let completedOnboardingVersion = "settings.completedOnboardingVersion"
        static let useCustomPlayerEngine = "settings.useCustomPlayerEngine"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var serverConfiguration: ServerConfiguration? {
        get { decode(ServerConfiguration.self, key: Keys.serverConfiguration) }
        set { encode(newValue, key: Keys.serverConfiguration) }
    }

    public var lastSession: UserSession? {
        get {
            guard let identity = decode(StoredSessionIdentity.self, key: Keys.lastSession) else {
                return nil
            }
            return UserSession(userID: identity.userID, username: identity.username, token: "")
        }
        set {
            if let newValue {
                encode(
                    StoredSessionIdentity(userID: newValue.userID, username: newValue.username),
                    key: Keys.lastSession
                )
            } else {
                defaults.removeObject(forKey: Keys.lastSession)
            }
        }
    }

    public var episodeReleaseNotificationsEnabled: Bool {
        get { defaults.bool(forKey: Keys.episodeReleaseNotificationsEnabled) }
        set { defaults.set(newValue, forKey: Keys.episodeReleaseNotificationsEnabled) }
    }

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    public var completedOnboardingVersion: Int {
        get { defaults.integer(forKey: Keys.completedOnboardingVersion) }
        set { defaults.set(newValue, forKey: Keys.completedOnboardingVersion) }
    }

    public var useCustomPlayerEngine: Bool {
        get {
            // The custom engine IS the player now — default ON. An explicit user choice (either
            // way) persists; only the never-touched state gets the new default, so nobody who
            // deliberately switched back to the legacy path is overridden by an update.
            guard defaults.object(forKey: Keys.useCustomPlayerEngine) != nil else { return true }
            return defaults.bool(forKey: Keys.useCustomPlayerEngine)
        }
        set { defaults.set(newValue, forKey: Keys.useCustomPlayerEngine) }
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, key: String) {
        if let value, let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

struct SensitiveURLLogProjector: Sendable {
    private static let functionalQueryNames: Set<String> = [
        "allowaudiostreamcopy",
        "allowvideostreamcopy",
        "audiobitrate",
        "audiocodec",
        "container",
        "maxstreamingbitrate",
        "requireavc",
        "segmentcontainer",
        "subtitlemethod",
        "transcodereasons",
        "videobitrate",
        "videocodec"
    ]
    private let pathCorrelationKey: SymmetricKey

    init(keyData: Data) {
        self.init(key: SymmetricKey(data: keyData))
    }

    fileprivate init(key: SymmetricKey) {
        pathCorrelationKey = key
    }

    func logString(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawScheme = components.scheme,
              let rawHost = components.host,
              !rawHost.isEmpty
        else {
            return "invalid-url"
        }

        let scheme = rawScheme.lowercased()
        guard scheme == "http" || scheme == "https" else {
            return "invalid-url"
        }

        let host = rawHost.lowercased()
        guard isSafeHost(host) else {
            return "invalid-url"
        }

        let queryItems: [URLQueryItem]
        if components.percentEncodedQuery != nil {
            guard let parsedQueryItems = components.queryItems else {
                return "invalid-url"
            }
            queryItems = parsedQueryItems
        } else {
            queryItems = []
        }

        let displayedHost: String
        if host.contains(":"), !host.hasPrefix("[") {
            displayedHost = "[\(host)]"
        } else {
            displayedHost = host
        }

        let defaultPort = scheme == "http" ? 80 : 443
        let port = components.port.flatMap { $0 == defaultPort ? nil : ":\($0)" } ?? ""
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let correlation = pathCorrelation(for: path)
        let queryNames = Set(queryItems.lazy.map { $0.name.lowercased() })
            .intersection(Self.functionalQueryNames)
            .sorted()
        let queryNameList = queryNames.isEmpty ? "none" : queryNames.joined(separator: ",")

        return "\(scheme)://\(displayedHost)\(port) path=\(correlation) queryNames=\(queryNameList) queryItems=\(queryItems.count)"
    }

    private func pathCorrelation(for path: String) -> String {
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: Data(path.utf8),
            using: pathCorrelationKey
        )
        return authenticationCode.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private func isSafeHost(_ host: String) -> Bool {
        host.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 48 ... 57, 58, 65 ... 90, 91, 93, 97 ... 122:
                return true
            default:
                return false
            }
        }
    }
}

public enum SensitiveURLSanitizer {
    private static let sensitiveQueryNames: Set<String> = [
        "api_key",
        "apikey",
        "x-emby-token",
        "token",
        "access_token"
    ]
    private static let logProjector = SensitiveURLLogProjector(
        key: SymmetricKey(size: .bits256)
    )

    public static func cacheKey(for url: URL) -> String {
        cacheIdentity(for: url)
    }

    public static func logString(for url: URL) -> String {
        logProjector.logString(for: url)
    }

    public static func compactLogString(for url: URL) -> String {
        logProjector.logString(for: url)
    }

    private static func cacheIdentity(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        if let queryItems = components.queryItems {
            let sanitizedItems = queryItems.compactMap { item -> URLQueryItem? in
                let normalizedName = item.name.lowercased()
                return sensitiveQueryNames.contains(normalizedName) ? nil : item
            }
            components.queryItems = sanitizedItems.isEmpty ? nil : sanitizedItems
        }

        return components.string ?? url.absoluteString
    }
}

public extension URL {
    var reelfinCacheKey: String {
        SensitiveURLSanitizer.cacheKey(for: self)
    }

    var reelfinLogString: String {
        SensitiveURLSanitizer.logString(for: self)
    }

    var reelfinCompactLogString: String {
        SensitiveURLSanitizer.compactLogString(for: self)
    }
}
