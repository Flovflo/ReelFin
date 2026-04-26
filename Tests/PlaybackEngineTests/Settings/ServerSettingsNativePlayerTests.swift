import PlaybackEngine
@testable import ReelFinUI
import Shared
import XCTest

@MainActor
final class ServerSettingsNativePlayerTests: XCTestCase {
    func testNativePlayerTogglePersistsOriginalOnlyConfig() async throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: NativePlayerRuntimeDefaults.enabledKey)
        let dependencies = ReelFinPreviewFactory.dependencies()
        dependencies.settingsStore.serverConfiguration = ServerConfiguration(
            serverURL: URL(string: "https://jellyfin.example")!,
            forceH264FallbackWhenNotDirectPlay: true,
            nativePlayerConfig: NativePlayerConfig(enabled: false)
        )
        let viewModel = ServerSettingsViewModel(dependencies: dependencies, defaults: defaults)

        viewModel.setNativePlayerEnabled(true)
        let result = await viewModel.save()

        XCTAssertEqual(result, .saved)
        XCTAssertTrue(defaults.bool(forKey: NativePlayerRuntimeDefaults.enabledKey))
        XCTAssertFalse(viewModel.forceH264FallbackWhenNotDirectPlay)
        let saved = try XCTUnwrap(dependencies.settingsStore.serverConfiguration)
        XCTAssertTrue(saved.nativePlayerConfig.enabled)
        XCTAssertTrue(saved.nativePlayerConfig.alwaysRequestOriginalFile)
        XCTAssertFalse(saved.nativePlayerConfig.allowServerTranscodeFallback)
        XCTAssertFalse(saved.forceH264FallbackWhenNotDirectPlay)
    }

    func testExperimentalDefaultsMigrateStaleDisableOnce() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: NativePlayerRuntimeDefaults.enabledKey)

        NativePlayerRuntimeDefaults.registerExperimentalBranchDefaults(
            environment: [:],
            userDefaults: defaults
        )

        #if DEBUG
        XCTAssertTrue(defaults.bool(forKey: NativePlayerRuntimeDefaults.enabledKey))
        XCTAssertTrue(defaults.bool(forKey: NativePlayerRuntimeDefaults.experimentalBranchDefaultAppliedKey))
        #else
        XCTAssertFalse(defaults.bool(forKey: NativePlayerRuntimeDefaults.enabledKey))
        #endif
    }

    func testExperimentalDefaultsForceNativeModeOnDebugBranchAfterMigration() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: NativePlayerRuntimeDefaults.enabledKey)
        defaults.set(true, forKey: NativePlayerRuntimeDefaults.experimentalBranchDefaultAppliedKey)

        NativePlayerRuntimeDefaults.registerExperimentalBranchDefaults(
            environment: [:],
            userDefaults: defaults
        )

        #if DEBUG
        XCTAssertTrue(defaults.bool(forKey: NativePlayerRuntimeDefaults.enabledKey))
        #else
        XCTAssertFalse(defaults.bool(forKey: NativePlayerRuntimeDefaults.enabledKey))
        #endif
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ServerSettingsNativePlayerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
