import Foundation

public struct NativePlayerConfig: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var alwaysRequestOriginalFile: Bool
    public var allowServerTranscodeFallback: Bool
    public var preferAppleHardwareDecode: Bool
    public var allowCustomDemuxers: Bool
    public var allowSoftwareDecode: Bool
    public var enableMetalRenderer: Bool
    public var enableDiagnosticsOverlay: Bool
    public var enableExperimentalMKV: Bool
    public var enableExperimentalASS: Bool
    public var enableExperimentalPGS: Bool
    public var enableExperimentalTrueHD: Bool
    public var enableExperimentalDTS: Bool

    public init(
        enabled: Bool = false,
        alwaysRequestOriginalFile: Bool = true,
        allowServerTranscodeFallback: Bool = false,
        preferAppleHardwareDecode: Bool = true,
        allowCustomDemuxers: Bool = true,
        allowSoftwareDecode: Bool = true,
        enableMetalRenderer: Bool = true,
        enableDiagnosticsOverlay: Bool = true,
        enableExperimentalMKV: Bool = true,
        enableExperimentalASS: Bool = true,
        enableExperimentalPGS: Bool = true,
        enableExperimentalTrueHD: Bool = true,
        enableExperimentalDTS: Bool = true
    ) {
        self.enabled = enabled
        self.alwaysRequestOriginalFile = alwaysRequestOriginalFile
        self.allowServerTranscodeFallback = allowServerTranscodeFallback
        self.preferAppleHardwareDecode = preferAppleHardwareDecode
        self.allowCustomDemuxers = allowCustomDemuxers
        self.allowSoftwareDecode = allowSoftwareDecode
        self.enableMetalRenderer = enableMetalRenderer
        self.enableDiagnosticsOverlay = enableDiagnosticsOverlay
        self.enableExperimentalMKV = enableExperimentalMKV
        self.enableExperimentalASS = enableExperimentalASS
        self.enableExperimentalPGS = enableExperimentalPGS
        self.enableExperimentalTrueHD = enableExperimentalTrueHD
        self.enableExperimentalDTS = enableExperimentalDTS
    }

    public static func runtimeOverrideEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        if environment["REELFIN_NATIVE_PLAYER"] == "0" {
            return false
        }
        if environment["REELFIN_NATIVE_PLAYER"] == "1" {
            return true
        }
        #if DEBUG
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return userDefaults.bool(forKey: NativePlayerRuntimeDefaults.enabledKey)
        }
        return true
        #else
        return userDefaults.bool(forKey: NativePlayerRuntimeDefaults.enabledKey)
        #endif
    }

    public func applyingRuntimeOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) -> NativePlayerConfig {
        guard Self.runtimeOverrideEnabled(environment: environment, userDefaults: userDefaults) else {
            return self
        }
        var config = self
        config.enabled = true
        config.alwaysRequestOriginalFile = true
        config.allowServerTranscodeFallback = false
        return config
    }
}

public enum NativePlayerRuntimeDefaults {
    public static let enabledKey = "reelfin.nativePlayer.enabled"
    public static let experimentalBranchDefaultAppliedKey = "reelfin.nativePlayer.experimentalBranchDefaultApplied.v2"

    public static func registerExperimentalBranchDefaults(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) {
        #if DEBUG
        guard environment["REELFIN_NATIVE_PLAYER"] != "0" else {
            userDefaults.set(false, forKey: enabledKey)
            return
        }
        if environment["REELFIN_NATIVE_PLAYER"] == "1" {
            userDefaults.set(true, forKey: enabledKey)
            userDefaults.set(true, forKey: experimentalBranchDefaultAppliedKey)
            return
        }
        userDefaults.set(true, forKey: enabledKey)
        userDefaults.set(true, forKey: experimentalBranchDefaultAppliedKey)
        #else
        _ = environment
        _ = userDefaults
        #endif
    }
}
