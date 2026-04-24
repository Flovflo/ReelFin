import PlaybackEngine
@testable import ReelFinUI
import Shared
import XCTest

@MainActor
final class ServerSettingsNativeVLCTests: XCTestCase {
    func testNativePlayerTogglePersistsOriginalOnlyConfig() async throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey)
        let dependencies = ReelFinPreviewFactory.dependencies()
        dependencies.settingsStore.serverConfiguration = ServerConfiguration(
            serverURL: URL(string: "https://jellyfin.example")!,
            forceH264FallbackWhenNotDirectPlay: true,
            nativeVLCClassPlayerConfig: NativeVLCClassPlayerConfig(enabled: false)
        )
        let viewModel = ServerSettingsViewModel(dependencies: dependencies, defaults: defaults)

        viewModel.setNativeVLCClassPlayerEnabled(true)
        let result = await viewModel.save()

        XCTAssertEqual(result, .saved)
        XCTAssertTrue(defaults.bool(forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey))
        XCTAssertFalse(viewModel.forceH264FallbackWhenNotDirectPlay)
        let saved = try XCTUnwrap(dependencies.settingsStore.serverConfiguration)
        XCTAssertTrue(saved.nativeVLCClassPlayerConfig.enabled)
        XCTAssertTrue(saved.nativeVLCClassPlayerConfig.alwaysRequestOriginalFile)
        XCTAssertFalse(saved.nativeVLCClassPlayerConfig.allowServerTranscodeFallback)
        XCTAssertFalse(saved.forceH264FallbackWhenNotDirectPlay)
    }

    func testExperimentalDefaultsMigrateStaleDisableOnce() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey)

        NativeVLCClassPlayerRuntimeDefaults.registerExperimentalBranchDefaults(
            environment: [:],
            userDefaults: defaults
        )

        #if DEBUG
        XCTAssertTrue(defaults.bool(forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey))
        XCTAssertTrue(defaults.bool(forKey: NativeVLCClassPlayerRuntimeDefaults.experimentalBranchDefaultAppliedKey))
        #else
        XCTAssertFalse(defaults.bool(forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey))
        #endif
    }

    func testExperimentalDefaultsForceNativeModeOnDebugBranchAfterMigration() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey)
        defaults.set(true, forKey: NativeVLCClassPlayerRuntimeDefaults.experimentalBranchDefaultAppliedKey)

        NativeVLCClassPlayerRuntimeDefaults.registerExperimentalBranchDefaults(
            environment: [:],
            userDefaults: defaults
        )

        #if DEBUG
        XCTAssertTrue(defaults.bool(forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey))
        #else
        XCTAssertFalse(defaults.bool(forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey))
        #endif
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ServerSettingsNativeVLCTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
