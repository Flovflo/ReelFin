import Foundation

public enum PlaybackLogSanitizer {
    private static let sensitiveQueryNames: Set<String> = [
        "api_key",
        "x-emby-token",
        "token"
    ]

    public static func sanitize(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.queryItems = components.queryItems?.map { item in
            let lowercasedName = item.name.lowercased()
            guard sensitiveQueryNames.contains(lowercasedName) else {
                return item
            }
            return URLQueryItem(name: item.name, value: "REDACTED")
        }

        return components.string ?? url.absoluteString
    }
}
