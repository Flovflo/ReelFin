import Foundation

public enum NativePlayerSurfacePreference: String, Codable, CaseIterable, Hashable, Sendable {
    case directPlayWhenPossible
    case customPlayer
}

public struct NativePlayerConfig: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var surfacePreference: NativePlayerSurfacePreference
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
        surfacePreference: NativePlayerSurfacePreference = .directPlayWhenPossible,
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
        self.surfacePreference = surfacePreference
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

    private enum CodingKeys: String, CodingKey {
        case enabled
        case surfacePreference
        case alwaysRequestOriginalFile
        case allowServerTranscodeFallback
        case preferAppleHardwareDecode
        case allowCustomDemuxers
        case allowSoftwareDecode
        case enableMetalRenderer
        case enableDiagnosticsOverlay
        case enableExperimentalMKV
        case enableExperimentalASS
        case enableExperimentalPGS
        case enableExperimentalTrueHD
        case enableExperimentalDTS
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        if let rawSurfacePreference = try container.decodeIfPresent(String.self, forKey: .surfacePreference),
           let decodedSurfacePreference = NativePlayerSurfacePreference(rawValue: rawSurfacePreference) {
            surfacePreference = decodedSurfacePreference
        } else {
            surfacePreference = .directPlayWhenPossible
        }
        alwaysRequestOriginalFile = try container.decodeIfPresent(Bool.self, forKey: .alwaysRequestOriginalFile) ?? true
        allowServerTranscodeFallback = try container.decodeIfPresent(Bool.self, forKey: .allowServerTranscodeFallback) ?? false
        preferAppleHardwareDecode = try container.decodeIfPresent(Bool.self, forKey: .preferAppleHardwareDecode) ?? true
        allowCustomDemuxers = try container.decodeIfPresent(Bool.self, forKey: .allowCustomDemuxers) ?? true
        allowSoftwareDecode = try container.decodeIfPresent(Bool.self, forKey: .allowSoftwareDecode) ?? true
        enableMetalRenderer = try container.decodeIfPresent(Bool.self, forKey: .enableMetalRenderer) ?? true
        enableDiagnosticsOverlay = try container.decodeIfPresent(Bool.self, forKey: .enableDiagnosticsOverlay) ?? true
        enableExperimentalMKV = try container.decodeIfPresent(Bool.self, forKey: .enableExperimentalMKV) ?? true
        enableExperimentalASS = try container.decodeIfPresent(Bool.self, forKey: .enableExperimentalASS) ?? true
        enableExperimentalPGS = try container.decodeIfPresent(Bool.self, forKey: .enableExperimentalPGS) ?? true
        enableExperimentalTrueHD = try container.decodeIfPresent(Bool.self, forKey: .enableExperimentalTrueHD) ?? true
        enableExperimentalDTS = try container.decodeIfPresent(Bool.self, forKey: .enableExperimentalDTS) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(surfacePreference, forKey: .surfacePreference)
        try container.encode(alwaysRequestOriginalFile, forKey: .alwaysRequestOriginalFile)
        try container.encode(allowServerTranscodeFallback, forKey: .allowServerTranscodeFallback)
        try container.encode(preferAppleHardwareDecode, forKey: .preferAppleHardwareDecode)
        try container.encode(allowCustomDemuxers, forKey: .allowCustomDemuxers)
        try container.encode(allowSoftwareDecode, forKey: .allowSoftwareDecode)
        try container.encode(enableMetalRenderer, forKey: .enableMetalRenderer)
        try container.encode(enableDiagnosticsOverlay, forKey: .enableDiagnosticsOverlay)
        try container.encode(enableExperimentalMKV, forKey: .enableExperimentalMKV)
        try container.encode(enableExperimentalASS, forKey: .enableExperimentalASS)
        try container.encode(enableExperimentalPGS, forKey: .enableExperimentalPGS)
        try container.encode(enableExperimentalTrueHD, forKey: .enableExperimentalTrueHD)
        try container.encode(enableExperimentalDTS, forKey: .enableExperimentalDTS)
    }

    public static func runtimeOverrideEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        runtimeEnabledOverride(environment: environment, userDefaults: userDefaults) ?? false
    }

    public func applyingRuntimeOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) -> NativePlayerConfig {
        guard let runtimeEnabled = Self.runtimeEnabledOverride(
            environment: environment,
            userDefaults: userDefaults
        ) else {
            return self
        }
        var config = self
        config.enabled = runtimeEnabled
        guard runtimeEnabled else {
            return config
        }
        if let storedSurfacePreference = NativePlayerRuntimeDefaults.surfacePreference(userDefaults: userDefaults) {
            config.surfacePreference = storedSurfacePreference
        }
        config.alwaysRequestOriginalFile = true
        // Reverted to false: enabling transcode availability + the adaptive guard relaxations
        // caused a black screen on device. Restore the known-good direct-play config.
        config.allowServerTranscodeFallback = false
        return config
    }

    private static func runtimeEnabledOverride(
        environment: [String: String],
        userDefaults: UserDefaults
    ) -> Bool? {
        if environment["REELFIN_NATIVE_PLAYER"] == "0" {
            return false
        }
        if environment["REELFIN_NATIVE_PLAYER"] == "1" {
            return true
        }
        #if DEBUG
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return userDefaults.object(forKey: NativePlayerRuntimeDefaults.enabledKey) as? Bool
        }
        return (userDefaults.object(forKey: NativePlayerRuntimeDefaults.enabledKey) as? Bool) ?? true
        #else
        return userDefaults.object(forKey: NativePlayerRuntimeDefaults.enabledKey) as? Bool
        #endif
    }
}

public enum NativePlayerRuntimeDefaults {
    public static let enabledKey = "reelfin.nativePlayer.enabled"
    public static let surfacePreferenceKey = "reelfin.nativePlayer.surfacePreference"
    public static let experimentalBranchDefaultAppliedKey = "reelfin.nativePlayer.experimentalBranchDefaultApplied.v2"

    public static func surfacePreference(userDefaults: UserDefaults = .standard) -> NativePlayerSurfacePreference? {
        guard let raw = userDefaults.string(forKey: surfacePreferenceKey) else {
            return nil
        }
        return NativePlayerSurfacePreference(rawValue: raw)
    }

    public static func setSurfacePreference(
        _ preference: NativePlayerSurfacePreference,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(preference.rawValue, forKey: surfacePreferenceKey)
    }

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
            registerDefaultSurfacePreferenceIfNeeded(userDefaults: userDefaults)
            userDefaults.set(true, forKey: experimentalBranchDefaultAppliedKey)
            return
        }
        if userDefaults.bool(forKey: experimentalBranchDefaultAppliedKey) {
            registerDefaultSurfacePreferenceIfNeeded(userDefaults: userDefaults)
            return
        }
        userDefaults.set(true, forKey: enabledKey)
        registerDefaultSurfacePreferenceIfNeeded(userDefaults: userDefaults)
        userDefaults.set(true, forKey: experimentalBranchDefaultAppliedKey)
        #else
        _ = environment
        _ = userDefaults
        #endif
    }

    private static func registerDefaultSurfacePreferenceIfNeeded(userDefaults: UserDefaults) {
        guard userDefaults.object(forKey: surfacePreferenceKey) == nil else {
            return
        }
        setSurfacePreference(.directPlayWhenPossible, userDefaults: userDefaults)
    }
}
