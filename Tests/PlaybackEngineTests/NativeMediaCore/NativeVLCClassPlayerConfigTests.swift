import Shared
import XCTest

final class NativeVLCClassPlayerConfigTests: XCTestCase {
    func testDefaultsAreExperimentalButFeatureFlagOff() {
        let config = NativeVLCClassPlayerConfig()

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

        XCTAssertFalse(config.nativeVLCClassPlayerConfig.enabled)
        XCTAssertTrue(config.nativeVLCClassPlayerConfig.alwaysRequestOriginalFile)
    }

    func testRuntimeDefaultsCanEnableNativeModeWithoutChangingPersistedConfig() throws {
        let suiteName = "NativeVLCClassPlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        NativeVLCClassPlayerRuntimeDefaults.registerExperimentalBranchDefaults(
            environment: [:],
            userDefaults: defaults
        )
        let effective = NativeVLCClassPlayerConfig().applyingRuntimeOverride(
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
        let suiteName = "NativeVLCClassPlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
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

    func testRuntimeDefaultsMigrateOldV1BranchMarkerToCurrentNativeDefault() throws {
        let suiteName = "NativeVLCClassPlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey)
        defaults.set(true, forKey: "reelfin.nativeVlcClassPlayer.experimentalBranchDefaultApplied.v1")

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

    func testRuntimeDefaultsForceNativeModeOnDebugBranchAfterMigration() throws {
        let suiteName = "NativeVLCClassPlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
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

    func testDebugRuntimeOverrideIgnoresSettingsToggleUnlessEnvironmentOptsOut() throws {
        let suiteName = "NativeVLCClassPlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey)

        let effective = NativeVLCClassPlayerConfig(enabled: false).applyingRuntimeOverride(
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
        let suiteName = "NativeVLCClassPlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let xctestEnvironment = ["XCTestConfigurationFilePath": "/tmp/ReelFin.xctestconfiguration"]
        var effective = NativeVLCClassPlayerConfig(enabled: false).applyingRuntimeOverride(
            environment: xctestEnvironment,
            userDefaults: defaults
        )
        XCTAssertFalse(effective.enabled)

        defaults.set(true, forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey)
        effective = NativeVLCClassPlayerConfig(enabled: false).applyingRuntimeOverride(
            environment: xctestEnvironment,
            userDefaults: defaults
        )
        XCTAssertTrue(effective.enabled)
        XCTAssertFalse(effective.allowServerTranscodeFallback)
    }

    func testRuntimeDefaultsRespectExplicitDebugOptOut() throws {
        let suiteName = "NativeVLCClassPlayerConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey)

        NativeVLCClassPlayerRuntimeDefaults.registerExperimentalBranchDefaults(
            environment: ["REELFIN_NATIVE_VLC_CLASS_PLAYER": "0"],
            userDefaults: defaults
        )
        let effective = NativeVLCClassPlayerConfig(enabled: false).applyingRuntimeOverride(
            environment: ["REELFIN_NATIVE_VLC_CLASS_PLAYER": "0"],
            userDefaults: defaults
        )

        XCTAssertFalse(effective.enabled)
    }
}
