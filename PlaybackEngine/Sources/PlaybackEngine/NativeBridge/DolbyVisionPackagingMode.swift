import Foundation

// MARK: - Packaging Mode

/// The three explicit packaging modes for Dolby Vision content.
///
/// ARCHITECTURAL RULE: Profile 8.1 MUST NOT use the same signaling model
/// as Profile 5 primary Dolby Vision. This distinction is enforced here.
public enum DolbyVisionPackagingMode: String, Sendable, CaseIterable {
    /// Mode A — Apple backward-compatible HDR10 base-layer model (DEFAULT).
    ///
    /// - Sample entry: `hvc1` (NOT `dvh1`)
    /// - hvcC: present
    /// - dvcC: present inside `hvc1` (for DV-aware devices)
    /// - ftyp brands: iso5 iso6 mp41 hvc1 dby1
    /// - CODECS: `hvc1.2.4.L153.B0,ec-3`
    /// - SUPPLEMENTAL-CODECS: `dvh1.PP.LL/db1p`
    /// - VIDEO-RANGE: PQ
    /// - RPU NALs: KEPT
    /// - Floor: HDR10 guaranteed
    /// - Ceiling: DV best-effort
    case dvProfile81Compatible

    /// Mode B — Pure HDR10 fallback, no DV signaling at all.
    ///
    /// - Sample entry: `hvc1`
    /// - hvcC: present
    /// - dvcC: absent
    /// - CODECS: `hvc1.2.4.L153.B0,ec-3`
    /// - SUPPLEMENTAL-CODECS: none
    /// - VIDEO-RANGE: PQ
    /// - RPU NALs: STRIPPED
    /// - Floor: HDR10
    /// - Ceiling: HDR10
    case hdr10OnlyFallback

    /// Mode C — Strict primary DV signaling (experimental, less compatible for P8.1).
    ///
    /// - Sample entry: `dvh1`
    /// - hvcC: present
    /// - dvcC: present
    /// - CODECS: `dvh1.PP.LL,ec-3`
    /// - SUPPLEMENTAL-CODECS: none
    /// - VIDEO-RANGE: PQ
    /// - RPU NALs: KEPT
    /// - Floor: DV only (WILL fail on non-DV devices)
    /// - Ceiling: DV
    case primaryDolbyVisionExperimental
}

// MARK: - Video Sample Entry Strategy

/// Describes exactly what the MP4 init segment writer must produce for the video track.
public struct VideoSampleEntryStrategy: Sendable, Equatable {
    /// Four-character code for the video sample entry box: `"hvc1"`, `"dvh1"`, `"avc1"`.
    public let sampleEntryType: String

    /// Whether to include the `hvcC` box (HEVC decoder configuration record).
    public let includeHvcC: Bool

    /// Whether to include the `dvcC` box (Dolby Vision configuration record).
    public let includeDvcC: Bool

    /// DV configuration parameters for dvcC (only meaningful when `includeDvcC == true`).
    public let dvProfile: Int?
    public let dvLevel: Int?
    public let dvCompatibilityId: Int?

    /// Whether `ftyp` should include the `dby1` compatible brand.
    public let ftypIncludesDby1: Bool

    /// Whether Dolby Vision RPU NAL units (type 62/63) should be stripped from video frames.
    public let stripDolbyVisionRPUNALs: Bool

    public init(
        sampleEntryType: String,
        includeHvcC: Bool = true,
        includeDvcC: Bool,
        dvProfile: Int? = nil,
        dvLevel: Int? = nil,
        dvCompatibilityId: Int? = nil,
        ftypIncludesDby1: Bool = false,
        stripDolbyVisionRPUNALs: Bool = false
    ) {
        self.sampleEntryType = sampleEntryType
        self.includeHvcC = includeHvcC
        self.includeDvcC = includeDvcC
        self.dvProfile = dvProfile
        self.dvLevel = dvLevel
        self.dvCompatibilityId = dvCompatibilityId
        self.ftypIncludesDby1 = ftypIncludesDby1
        self.stripDolbyVisionRPUNALs = stripDolbyVisionRPUNALs
    }
}

// MARK: - HLS Master Signaling

/// Describes exactly what the HLS master playlist must emit.
public struct HLSMasterSignaling: Sendable, Equatable {
    /// Primary CODECS string, e.g. `"hvc1.2.4.L153.B0,ec-3"`.
    public let codecs: String

    /// SUPPLEMENTAL-CODECS string, e.g. `"dvh1.08.06/db1p"`, or nil.
    public let supplementalCodecs: String?

    /// VIDEO-RANGE value: `"PQ"`, `"HLG"`, or nil for SDR.
    public let videoRange: String?

    /// FRAME-RATE value, e.g. `23.976`, or nil.
    public let frameRate: Double?

    public init(
        codecs: String,
        supplementalCodecs: String? = nil,
        videoRange: String? = nil,
        frameRate: Double? = nil
    ) {
        self.codecs = codecs
        self.supplementalCodecs = supplementalCodecs
        self.videoRange = videoRange
        self.frameRate = frameRate
    }
}

// MARK: - Playback Capability Expectation

/// The expected video quality floor and ceiling for a packaging decision.
public struct PlaybackCapabilityExpectation: Sendable, Equatable {
    public enum VideoQuality: String, Sendable {
        case dolbyVision
        case hdr10
        case sdr
    }

    /// Minimum guaranteed video quality.
    public let floor: VideoQuality

    /// Maximum achievable video quality (best-effort).
    public let ceiling: VideoQuality

    /// Human-readable explanation of the contract.
    public let explanation: String

    public init(floor: VideoQuality, ceiling: VideoQuality, explanation: String) {
        self.floor = floor
        self.ceiling = ceiling
        self.explanation = explanation
    }
}

// MARK: - Packaging Decision

/// The complete packaging decision that drives:
/// - Init segment writing (sample entry type, boxes)
/// - HLS playlist signaling (CODECS, SUPPLEMENTAL-CODECS, VIDEO-RANGE)
/// - NALU processing (RPU stripping)
/// - Diagnostic reporting (floor/ceiling, reason)
public struct NativeBridgePackagingDecision: Sendable, Equatable {
    public let mode: DolbyVisionPackagingMode
    public let videoEntry: VideoSampleEntryStrategy
    public let hlsSignaling: HLSMasterSignaling
    public let expectation: PlaybackCapabilityExpectation
    public let reason: String

    public init(
        mode: DolbyVisionPackagingMode,
        videoEntry: VideoSampleEntryStrategy,
        hlsSignaling: HLSMasterSignaling,
        expectation: PlaybackCapabilityExpectation,
        reason: String
    ) {
        self.mode = mode
        self.videoEntry = videoEntry
        self.hlsSignaling = hlsSignaling
        self.expectation = expectation
        self.reason = reason
    }
}

// MARK: - HLS Child URI Mode

/// Controls whether HLS playlists emit relative or absolute child URIs.
public enum HLSChildURIMode: String, Sendable, CaseIterable {
    case relative
    case absolute
}

// MARK: - HLS Startup Playlist Mode

/// Controls the media playlist format during startup.
public enum HLSStartupPlaylistMode: String, Sendable, CaseIterable {
    /// VOD snapshot: `#EXT-X-PLAYLIST-TYPE:VOD` + `#EXT-X-ENDLIST` + single segment.
    case vodSnapshot
    /// EVENT: growing playlist, no ENDLIST until EOS.
    case event
}

// MARK: - Debug Toggles

/// Reads A/B debug toggles from env vars and UserDefaults.
/// Priority: env var > UserDefaults > default.
public enum NativeBridgeDebugToggles {

    public static var packagingMode: DolbyVisionPackagingMode {
        if let raw = envOrDefault("REELFIN_DV_PACKAGING_MODE", key: "reelfin.playback.dv.packagingMode") {
            switch raw {
            case "compatible", "dvprofile81compatible": return .dvProfile81Compatible
            case "hdr10", "hdr10only", "hdr10onlyfallback": return .hdr10OnlyFallback
            case "primarydv", "experimental", "primarydolbyvisionexperimental": return .primaryDolbyVisionExperimental
            default: break
            }
        }
        return .dvProfile81Compatible
    }

    public static var childURIMode: HLSChildURIMode {
        if let raw = envOrDefault("REELFIN_HLS_URI_MODE", key: "reelfin.playback.hls.uriMode") {
            switch raw {
            case "relative": return .relative
            case "absolute": return .absolute
            default: break
            }
        }
        return .absolute
    }

    public static var startupPlaylistMode: HLSStartupPlaylistMode {
        if let raw = envOrDefault("REELFIN_HLS_STARTUP_MODE", key: "reelfin.playback.hls.startupMode") {
            switch raw {
            case "vod", "vodsnapshot": return .vodSnapshot
            case "event": return .event
            default: break
            }
        }
        return .vodSnapshot
    }

    public static var forceVideoOnlyStartup: Bool {
        boolToggle(env: "REELFIN_LOCAL_HLS_VIDEO_ONLY_STARTUP",
                    key: "reelfin.playback.localhls.videoOnlyStartup",
                    fallback: false)
    }

    // MARK: - Helpers

    private static func envOrDefault(_ envName: String, key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[envName] {
            let normalized = env.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty { return normalized }
        }
        if let persisted = UserDefaults.standard.string(forKey: key) {
            let normalized = persisted.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty { return normalized }
        }
        return nil
    }

    private static func boolToggle(env: String, key: String, fallback: Bool) -> Bool {
        if let raw = envOrDefault(env, key: key) {
            return raw == "1" || raw == "true" || raw == "yes"
        }
        return fallback
    }
}
