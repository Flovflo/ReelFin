import Foundation

public enum ReviewDemoMode {
    public static let serverURL = URL(string: "https://review.reelfin.app")!
    public static let username = "review"
    public static let password = "ReelFin-Review-2026"

    private static let userID = "review-demo-user"
    private static let token = "review-demo-token"

    public static var session: UserSession {
        UserSession(userID: userID, username: username, token: token)
    }

    public static func isReviewServer(_ url: URL) -> Bool {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == serverURL.host
            && path.isEmpty
    }

    public static func matches(serverURL: URL, credentials: UserCredentials) -> Bool {
        isReviewServer(serverURL)
            && credentials.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == username
            && credentials.password == password
    }

    public static func isReviewSession(_ session: UserSession) -> Bool {
        session.userID == userID && session.token == token
    }
}
