import Shared
import XCTest

final class NativePlayerConfigTests: XCTestCase {
    func testDefaultsAreExperimentalButFeatureFlagOff() {
        let config = NativePlayerConfig()

        XCTAssertFalse(config.enabled)
        XCTAssertTrue(config.alwaysRequestOriginalFile)
        XCTAssertFalse(config.allowServerTranscodeFallback)
        XCTAssertTrue(config.preferAppleHardwareDecode)
        XCTAssertTrue(config.allowCustomDemuxers)
        XCTAssertTrue(config.allowSoftwareDecode)
        XCTAssertTrue(config.enableMetalRenderer)
        XCTAssertTrue(config.enableDiagnosticsOverlay)
        XCTAssertTrue(config.enableExperimentalMKV)
        XCTAssertTrue(config.enableExperimentalASS)
        XCTAssertTrue(config.enableExperimentalPGS)
        XCTAssertTrue(config.enableExperimentalTrueHD)
        XCTAssertTrue(config.enableExperimentalDTS)
    }

    func testServerConfigurationDecodesMissingNativeConfigAsDefault() throws {
        let json = #"{"serverURL":"https://example.com"}"#.data(using: .utf8)!

        let config = try JSONDecoder().decode(ServerConfiguration.self, from: json)

        XCTAssertFalse(config.nativePlayerConfig.enabled)
        XCTAssertTrue(config.nativePlayerConfig.alwaysRequestOriginalFile)
    }

    func testRuntimeDefaultsCanEnableNativeModeWithoutChangingPersistedConfig() throws {
        let suiteName = "NativePlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        NativePlayerRuntimeDefaults.registerExperimentalBranchDefaults(
            environment: [:],
            userDefaults: defaults
        )
        let effective = NativePlayerConfig().applyingRuntimeOverride(
            environment: [:],
            userDefaults: defaults
        )

        #if DEBUG
        XCTAssertTrue(effective.enabled)
        XCTAssertTrue(effective.alwaysRequestOriginalFile)
        XCTAssertFalse(effective.allowServerTranscodeFallback)
        #else
        XCTAssertFalse(effective.enabled)
        #endif
    }

    func testRuntimeDefaultsMigrateStaleDebugFalseOnce() throws {
        let suiteName = "NativePlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
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

    func testRuntimeDefaultsMigrateOldV1BranchMarkerToCurrentNativeDefault() throws {
        let suiteName = "NativePlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: NativePlayerRuntimeDefaults.enabledKey)
        defaults.set(true, forKey: "reelfin.nativePlayer.experimentalBranchDefaultApplied.v1")

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

    func testRuntimeDefaultsForceNativeModeOnDebugBranchAfterMigration() throws {
        let suiteName = "NativePlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
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

    func testDebugRuntimeOverrideIgnoresSettingsToggleUnlessEnvironmentOptsOut() throws {
        let suiteName = "NativePlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: NativePlayerRuntimeDefaults.enabledKey)

        let effective = NativePlayerConfig(enabled: false).applyingRuntimeOverride(
            environment: [:],
            userDefaults: defaults
        )

        #if DEBUG
        XCTAssertTrue(effective.enabled)
        XCTAssertTrue(effective.alwaysRequestOriginalFile)
        XCTAssertFalse(effective.allowServerTranscodeFallback)
        #else
        XCTAssertFalse(effective.enabled)
        #endif
    }

    func testRuntimeOverrideLetsXCTestControlNativeModeWithDefaults() throws {
        let suiteName = "NativePlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let xctestEnvironment = ["XCTestConfigurationFilePath": "/tmp/ReelFin.xctestconfiguration"]
        var effective = NativePlayerConfig(enabled: false).applyingRuntimeOverride(
            environment: xctestEnvironment,
            userDefaults: defaults
        )
        XCTAssertFalse(effective.enabled)

        defaults.set(true, forKey: NativePlayerRuntimeDefaults.enabledKey)
        effective = NativePlayerConfig(enabled: false).applyingRuntimeOverride(
            environment: xctestEnvironment,
            userDefaults: defaults
        )
        XCTAssertTrue(effective.enabled)
        XCTAssertFalse(effective.allowServerTranscodeFallback)
    }

    func testRuntimeDefaultsRespectExplicitDebugOptOut() throws {
        let suiteName = "NativePlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: NativePlayerRuntimeDefaults.enabledKey)

        NativePlayerRuntimeDefaults.registerExperimentalBranchDefaults(
            environment: ["REELFIN_NATIVE_PLAYER": "0"],
            userDefaults: defaults
        )
        let effective = NativePlayerConfig(enabled: false).applyingRuntimeOverride(
            environment: ["REELFIN_NATIVE_PLAYER": "0"],
            userDefaults: defaults
        )

        XCTAssertFalse(effective.enabled)
    }
}
