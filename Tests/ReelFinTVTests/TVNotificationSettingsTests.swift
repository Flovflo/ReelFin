import Shared
import XCTest

final class TVNotificationSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "TVNotificationSettingsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testEpisodeReleaseNotificationsFlagPersists() throws {
        let store = DefaultSettingsStore(defaults: defaults)
        XCTAssertFalse(store.episodeReleaseNotificationsEnabled)

        store.episodeReleaseNotificationsEnabled = true

        let restoredStore = DefaultSettingsStore(defaults: defaults)
        XCTAssertTrue(restoredStore.episodeReleaseNotificationsEnabled)
    }

    func testNoopNotificationManagerKeepsTVAuthorizationDisabled() async {
        let manager = NoopEpisodeReleaseNotificationManager()

        let status = await manager.authorizationStatus()
        let enabled = await manager.notificationsEnabled()

        XCTAssertFalse(enabled)
        XCTAssertEqual(status, .unsupported)
    }
}
