import JellyfinAPI
import Shared
import XCTest

final class SessionPersistenceTests: XCTestCase {
    func testCurrentSessionRestoresFromSettingsStore() async {
        let savedSession = UserSession(userID: "u1", username: "Flo", token: "token-from-settings")
        let settings = MockSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: savedSession
        )
        let tokenStore = MockTokenStore(storedToken: nil)

        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings)
        let restored = await client.currentSession()

        XCTAssertEqual(restored?.userID, "u1")
        XCTAssertEqual(restored?.username, "Flo")
        XCTAssertEqual(restored?.token, "token-from-settings")
    }

    func testCurrentSessionUsesKeychainTokenWhenAvailable() async {
        let savedSession = UserSession(userID: "u1", username: "Flo", token: "old-token")
        let settings = MockSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: savedSession
        )
        let tokenStore = MockTokenStore(storedToken: "token-from-keychain")

        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings)
        let restored = await client.currentSession()

        XCTAssertEqual(restored?.token, "token-from-keychain")
        XCTAssertEqual(settings.lastSession?.token, "token-from-keychain")
    }
}

private final class MockSettingsStore: SettingsStoreProtocol {
    var serverConfiguration: ServerConfiguration?
    var lastSession: UserSession?

    init(serverConfiguration: ServerConfiguration?, lastSession: UserSession?) {
        self.serverConfiguration = serverConfiguration
        self.lastSession = lastSession
    }
}

private final class MockTokenStore: TokenStoreProtocol {
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
