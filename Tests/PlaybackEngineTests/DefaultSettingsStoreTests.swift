import Foundation
import Shared
import XCTest

final class DefaultSettingsStoreTests: XCTestCase {
    func testLastSessionPersistsIdentityWithoutToken() throws {
        let suiteName = "DefaultSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DefaultSettingsStore(defaults: defaults)
        store.lastSession = UserSession(userID: "user-1", username: "Flo", token: "super-secret-token")

        let rawData = try XCTUnwrap(defaults.data(forKey: "settings.lastSession"))
        let rawJSON = try XCTUnwrap(String(data: rawData, encoding: .utf8))

        XCTAssertFalse(rawJSON.contains("super-secret-token"))
        XCTAssertTrue(rawJSON.contains("user-1"))
        XCTAssertTrue(rawJSON.contains("Flo"))

        let restored = try XCTUnwrap(store.lastSession)
        XCTAssertEqual(restored.userID, "user-1")
        XCTAssertEqual(restored.username, "Flo")
        XCTAssertEqual(restored.token, "")
    }

    func testLastSessionDecodesLegacyPayloadWithoutReusingPersistedToken() throws {
        let suiteName = "DefaultSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacySession = UserSession(userID: "legacy-user", username: "Legacy", token: "legacy-token")
        let legacyData = try JSONEncoder().encode(legacySession)
        defaults.set(legacyData, forKey: "settings.lastSession")

        let store = DefaultSettingsStore(defaults: defaults)
        let restored = try XCTUnwrap(store.lastSession)

        XCTAssertEqual(restored.userID, "legacy-user")
        XCTAssertEqual(restored.username, "Legacy")
        XCTAssertEqual(restored.token, "")
    }

    func testEpisodeReleaseNotificationsEnabledPersists() throws {
        let suiteName = "DefaultSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DefaultSettingsStore(defaults: defaults)
        XCTAssertFalse(store.episodeReleaseNotificationsEnabled)

        store.episodeReleaseNotificationsEnabled = true

        let restored = DefaultSettingsStore(defaults: defaults)
        XCTAssertTrue(restored.episodeReleaseNotificationsEnabled)
    }
}
