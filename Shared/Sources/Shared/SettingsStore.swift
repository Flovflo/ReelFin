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

public enum SensitiveURLSanitizer {
    private static let sensitiveQueryNames: Set<String> = [
        "api_key",
        "apikey",
        "x-emby-token",
        "token",
        "access_token"
    ]
    private static let compactLogQueryNames: Set<String> = [
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
    private static let redactionValue = "REDACTED"

    public static func cacheKey(for url: URL) -> String {
        sanitize(url, mode: .drop)
    }

    public static func logString(for url: URL) -> String {
        sanitize(url, mode: .redact)
    }

    public static func compactLogString(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return sanitize(url, mode: .redact)
        }

        let scheme = components.scheme.map { "\($0)://" } ?? ""
        let host = components.host ?? ""
        let port = components.port.map { ":\($0)" } ?? ""
        let path = components.path.isEmpty ? "/" : components.path
        let base = "\(scheme)\(host)\(port)\(path)"
        let queryItems = components.queryItems ?? []

        guard !queryItems.isEmpty else { return base }

        var displayed: [String] = []
        var seenNames = Set<String>()
        for item in queryItems {
            let normalizedName = item.name.lowercased()
            guard compactLogQueryNames.contains(normalizedName), !seenNames.contains(normalizedName) else {
                continue
            }

            seenNames.insert(normalizedName)
            let rawValue = sensitiveQueryNames.contains(normalizedName) ? redactionValue : compactValue(item.value)
            displayed.append("\(normalizedName)=\(rawValue)")
        }

        if displayed.isEmpty {
            return "\(base) [queryItems=\(queryItems.count)]"
        }

        let visible = Array(displayed.prefix(6))
        let omittedCount = max(0, queryItems.count - visible.count)
        let suffix = omittedCount > 0 ? " +\(omittedCount) params" : ""
        return "\(base) [\(visible.joined(separator: ", "))\(suffix)]"
    }

    private static func sanitize(_ url: URL, mode: SanitizationMode) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        if let queryItems = components.queryItems {
            let sanitizedItems = queryItems.compactMap { item -> URLQueryItem? in
                let normalizedName = item.name.lowercased()
                guard sensitiveQueryNames.contains(normalizedName) else {
                    return item
                }

                switch mode {
                case .drop:
                    return nil
                case .redact:
                    return URLQueryItem(name: item.name, value: redactionValue)
                }
            }
            components.queryItems = sanitizedItems.isEmpty ? nil : sanitizedItems
        }

        return components.string ?? url.absoluteString
    }

    private static func compactValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "true" }
        guard value.count > 32 else { return value }
        return "\(value.prefix(29))..."
    }

    private enum SanitizationMode {
        case drop
        case redact
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
