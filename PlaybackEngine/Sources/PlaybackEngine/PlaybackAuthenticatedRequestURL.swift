import Foundation

enum PlaybackAuthenticatedRequestURL {
    private static let sensitiveQueryNames: Set<String> = [
        "api_key", "apikey", "access_token", "token", "x-emby-token"
    ]
    private static let headerAuthNames: Set<String> = [
        "authorization", "x-emby-token", "x-mediabrowser-token"
    ]

    static func forInternalURLSession(_ url: URL, headers: [String: String]) -> URL {
        guard hasHeaderAuth(headers) else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              !queryItems.isEmpty
        else {
            return url
        }

        let filteredItems = queryItems.filter {
            !sensitiveQueryNames.contains($0.name.lowercased())
        }
        components.queryItems = filteredItems.isEmpty ? nil : filteredItems
        return components.url ?? url
    }

    private static func hasHeaderAuth(_ headers: [String: String]) -> Bool {
        headers.contains { key, value in
            headerAuthNames.contains(key.lowercased()) && !value.isEmpty
        }
    }
}
