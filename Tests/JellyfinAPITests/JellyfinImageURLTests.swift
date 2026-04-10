import Foundation
import JellyfinAPI
import Shared
import XCTest

final class JellyfinImageURLTests: XCTestCase {
    func testImageURLDoesNotEmbedAuthenticationToken() async throws {
        let settings = TestSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "")
        )
        let tokenStore = TestTokenStore(storedToken: "secret-token")
        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings)

        let generatedURL = await client.imageURL(for: "item-1", type: .primary, width: 640, quality: 80)
        let url = try XCTUnwrap(generatedURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertFalse(url.absoluteString.contains("api_key="))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "format" })?.value, "webp")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "maxWidth" })?.value, "640")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "quality" })?.value, "80")
    }
}

private final class TestSettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    var serverConfiguration: ServerConfiguration?
    var lastSession: UserSession?
    var hasCompletedOnboarding = false
    var completedOnboardingVersion = 0

    init(serverConfiguration: ServerConfiguration?, lastSession: UserSession?) {
        self.serverConfiguration = serverConfiguration
        self.lastSession = lastSession
    }
}

private final class TestTokenStore: TokenStoreProtocol, @unchecked Sendable {
    var storedToken: String?

    init(storedToken: String?) {
        self.storedToken = storedToken
    }

    func saveToken(_ token: String) throws {
        storedToken = token
    }

    func fetchToken() throws -> String? {
        storedToken
    }

    func clearToken() throws {
        storedToken = nil
    }
}
