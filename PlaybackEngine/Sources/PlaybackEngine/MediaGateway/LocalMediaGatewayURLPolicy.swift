import Foundation

public enum LocalMediaGatewayURLPolicy {
    public static func isSupportedRemoteURL(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return false
        }
        return !isLoopbackURL(url)
    }

    public static func isLoopbackURL(_ url: URL) -> Bool {
        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !host.isEmpty else { return false }
        return host == "localhost" || host == "::1" || host == "0:0:0:0:0:0:0:1" || host.hasPrefix("127.")
    }
}
