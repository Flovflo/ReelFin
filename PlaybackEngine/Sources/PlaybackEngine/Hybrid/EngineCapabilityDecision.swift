import Foundation
import Shared

// MARK: - Engine Selection Decision

/// The deterministic output of the capability engine.
/// Every decision is machine-readable, logged, and explainable.
public struct EngineCapabilityDecision: Sendable, Equatable {
    public let recommendation: EngineRecommendation
    public let reasons: [ReasonCode]
    public let startupRisk: RiskLevel
    public let subtitleRisk: RiskLevel
    public let audioRisk: RiskLevel
    public let hdrExpectation: HDRExpectation
    public let estimatedFeatureCompleteness: Double // 0.0–1.0

    public init(
        recommendation: EngineRecommendation,
        reasons: [ReasonCode],
        startupRisk: RiskLevel = .low,
        subtitleRisk: RiskLevel = .low,
        audioRisk: RiskLevel = .low,
        hdrExpectation: HDRExpectation = .sdr,
        estimatedFeatureCompleteness: Double = 1.0
    ) {
        self.recommendation = recommendation
        self.reasons = reasons
        self.startupRisk = startupRisk
        self.subtitleRisk = subtitleRisk
        self.audioRisk = audioRisk
        self.hdrExpectation = hdrExpectation
        self.estimatedFeatureCompleteness = estimatedFeatureCompleteness
    }
}

// MARK: - Engine Recommendation

public enum EngineRecommendation: String, Sendable, Equatable, CaseIterable {
    /// Media is fully Apple-native compatible. Use AVPlayer directly.
    case nativePreferred
    /// Media is likely native-compatible but has minor risk factors.
    case nativeAllowedButRisky
    /// Media requires VLCKit for playback (native path will fail or degrade).
    case vlcRequired
    /// Try native first; fall back to VLC if startup watchdog fires.
    case nativeThenFallbackIfStartupFails
    /// Server-side transcode is the best option (neither native nor VLC direct is ideal).
    case serverTranscodePreferred
    /// Media cannot be played by any local engine.
    case unsupported
}

// MARK: - Risk Level

public enum RiskLevel: String, Sendable, Equatable, Comparable {
    case none
    case low
    case medium
    case high
    case critical

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        let order: [RiskLevel] = [.none, .low, .medium, .high, .critical]
        guard let li = order.firstIndex(of: lhs), let ri = order.firstIndex(of: rhs) else { return false }
        return li < ri
    }
}

// MARK: - HDR Expectation

public enum HDRExpectation: String, Sendable, Equatable {
    case sdr
    case hdr10
    case hlg
    case dolbyVision
    /// HDR metadata present but engine may not preserve it (VLC fallback scenario).
    case hdrDegradedByEngine
    case unknown
}

// MARK: - Reason Codes

public enum ReasonCode: String, Sendable, Equatable, CaseIterable {
    // Container reasons
    case containerAppleNative          // mp4/mov/m4v: native-safe
    case containerMKV                  // mkv: needs remux or VLC
    case containerWebM                 // webm: VLC required
    case containerAVI                  // avi: VLC required
    case containerTS                   // ts: native HLS ok, raw TS risky
    case containerUnsupported          // unknown container

    // Video codec reasons
    case videoH264Native               // h264: native-safe
    case videoHEVCNative               // hevc: native-safe (A9+)
    case videoAV1Native                // av1: native-safe (A17 Pro+)
    case videoVP9RequiresVLC           // vp9: no native support
    case videoMPEG2RequiresVLC         // mpeg2: no native support
    case videoVC1RequiresVLC           // vc1: no native support
    case videoUnsupported              // unknown codec

    // Audio codec reasons
    case audioAACNative                // aac: native-safe
    case audioAC3Native                // ac3: native-safe
    case audioEAC3Native               // eac3: native-safe
    case audioALACNative               // alac: native-safe
    case audioFLACNative               // flac: native-safe (iOS 11+)
    case audioOpusNative               // opus: native-safe (iOS 16+ in CAF/MP4)
    case audioDTSRequiresVLC           // dts: VLC required
    case audioDTSHDRequiresVLC         // dts-hd: VLC required
    case audioTrueHDRequiresVLC        // truehd: VLC required
    case audioVorbisRequiresVLC        // vorbis: VLC required
    case audioUnsupported              // unknown audio codec

    // Subtitle reasons
    case subtitleSRTNative             // srt: convertible to WebVTT
    case subtitleWebVTTNative          // webvtt: native
    case subtitleASSRequiresVLC        // ass/ssa: VLC for rendering
    case subtitlePGSRequiresVLC        // pgs: bitmap, VLC required
    case subtitleVobSubRequiresVLC     // vobsub: bitmap, VLC required

    // HDR / Dynamic range reasons
    case hdrNativePreserved            // HDR10/HLG preserved via native path
    case dolbyVisionNativePreserved    // DV preserved via native path
    case hdrDegradedByVLCFallback      // VLC may not preserve premium HDR/DV
    case hdrNotApplicable              // SDR content

    // Source type reasons
    case sourceDirectPlay              // direct playable URL
    case sourceHLS                     // HLS stream
    case sourceProgressive             // progressive download
    case sourceRemux                   // server remux
    case sourceTranscode               // server transcode

    // Composite reasons
    case metadataMissing               // insufficient metadata for confident decision
    case nativeBridgeAvailable         // MKV→fMP4 remux pipeline available
    case fallbackToServerTranscode     // best to let server handle it
}

// MARK: - Media Characteristics Input

/// Normalized media characteristics for engine capability analysis.
public struct MediaCharacteristics: Sendable, Equatable {
    public var container: String?
    public var videoCodec: String?
    public var audioCodec: String?
    public var bitDepth: Int?
    public var videoProfile: String?
    public var videoRange: String?
    public var videoRangeType: String?
    public var dvProfile: Int?
    public var dvLevel: Int?
    public var audioChannels: Int?
    public var subtitleCodecs: [String]
    public var sourceType: SourceType
    public var supportsDirectPlay: Bool
    public var supportsDirectStream: Bool
    public var hasTranscodeURL: Bool

    public init(
        container: String? = nil,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        bitDepth: Int? = nil,
        videoProfile: String? = nil,
        videoRange: String? = nil,
        videoRangeType: String? = nil,
        dvProfile: Int? = nil,
        dvLevel: Int? = nil,
        audioChannels: Int? = nil,
        subtitleCodecs: [String] = [],
        sourceType: SourceType = .unknown,
        supportsDirectPlay: Bool = false,
        supportsDirectStream: Bool = false,
        hasTranscodeURL: Bool = false
    ) {
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.bitDepth = bitDepth
        self.videoProfile = videoProfile
        self.videoRange = videoRange
        self.videoRangeType = videoRangeType
        self.dvProfile = dvProfile
        self.dvLevel = dvLevel
        self.audioChannels = audioChannels
        self.subtitleCodecs = subtitleCodecs
        self.sourceType = sourceType
        self.supportsDirectPlay = supportsDirectPlay
        self.supportsDirectStream = supportsDirectStream
        self.hasTranscodeURL = hasTranscodeURL
    }

    /// Build from a Jellyfin MediaSource.
    public static func from(source: MediaSource) -> MediaCharacteristics {
        let subtitleCodecs = source.subtitleTracks.compactMap { track -> String? in
            if let codec = track.codec?.lowercased(), !codec.isEmpty { return codec }
            let title = track.title.lowercased()
            if title.contains("pgs") || title.contains("hdmv") { return "pgs" }
            if title.contains("ass") || title.contains("ssa") { return "ass" }
            if title.contains("srt") || title.contains("subrip") { return "srt" }
            if title.contains("vobsub") || title.contains("dvd_subtitle") { return "vobsub" }
            if title.contains("webvtt") || title.contains("vtt") { return "webvtt" }
            return nil
        }

        let sourceType: SourceType
        if source.supportsDirectPlay { sourceType = .directPlay }
        else if source.supportsDirectStream { sourceType = .directStream }
        else if source.transcodeURL != nil { sourceType = .transcode }
        else { sourceType = .unknown }

        return MediaCharacteristics(
            container: source.container?.lowercased(),
            videoCodec: source.normalizedVideoCodec.lowercased(),
            audioCodec: source.normalizedAudioCodec.lowercased(),
            bitDepth: source.videoBitDepth,
            videoProfile: source.videoProfile?.lowercased(),
            videoRange: source.videoRange?.lowercased(),
            videoRangeType: source.videoRangeType?.lowercased(),
            dvProfile: source.dvProfile,
            dvLevel: source.dvLevel,
            audioChannels: source.audioChannels,
            subtitleCodecs: subtitleCodecs,
            sourceType: sourceType,
            supportsDirectPlay: source.supportsDirectPlay,
            supportsDirectStream: source.supportsDirectStream,
            hasTranscodeURL: source.transcodeURL != nil
        )
    }
}

public enum SourceType: String, Sendable, Equatable {
    case directPlay
    case directStream
    case hls
    case progressive
    case remux
    case transcode
    case unknown
}
