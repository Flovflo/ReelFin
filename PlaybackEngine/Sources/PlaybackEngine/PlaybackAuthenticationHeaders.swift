import Foundation

enum PlaybackAuthenticationHeaders {
    static func jellyfin(token: String) -> [String: String] {
        guard !token.isEmpty else { return [:] }
        return [
            "User-Agent": "ReelFin/1.0",
            "X-Emby-Token": token,
            "X-Emby-Authorization": embyAuthorizationHeader(token: token)
        ]
    }

    private static func embyAuthorizationHeader(token: String) -> String {
        let parts = [
            "Client=\"ReelFin\"",
            "Device=\"Apple\"",
            "DeviceId=\"ReelFin\"",
            "Version=\"1.0\"",
            "Token=\"\(escaped(token))\""
        ]
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
