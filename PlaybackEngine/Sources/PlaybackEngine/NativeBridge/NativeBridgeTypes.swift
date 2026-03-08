import CoreMedia
import Foundation

// MARK: - Codec Classification

/// Classifies an audio codec's compatibility with Apple's AVPlayer pipeline.
public enum AudioCodecSupport: String, Sendable, CaseIterable {
    /// Natively playable by AVPlayer without any conversion.
    case native       // AAC, ALAC, MP3, FLAC, AC-3, E-AC-3, Opus
    /// Requires conversion to a native codec (e.g. TrueHD → E-AC-3, DTS → AAC).
    case needsConvert // TrueHD, DTS, DTS-HD, PCM (high rate)
    /// Unknown codec — treat as needs conversion.
    case unknown

    public static func classify(_ codec: String) -> AudioCodecSupport {
        let normalized = codec.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Apple-native audio codecs
        let nativeCodecs: Set<String> = [
            "aac", "mp4a", "alac", "mp3", "mp4a.40.2", "mp4a.40.5",
            "flac", "ac3", "eac3", "ec3", "opus"
        ]
        if nativeCodecs.contains(normalized) { return .native }
        if normalized.hasPrefix("mp4a") { return .native }
        if normalized.contains("aac") { return .native }
        if normalized.contains("ac3") && !normalized.contains("truehd") { return .native }
        if normalized.contains("eac3") || normalized.contains("ec3") { return .native }
        if normalized.contains("alac") { return .native }
        if normalized.contains("flac") { return .native }

        // Codecs that need conversion
        let convertCodecs: Set<String> = [
            "truehd", "dts", "dtshd", "dtshdma", "dtshdhra", "dtse", "dtsx",
            "pcm", "pcms16le", "pcms24le", "pcms32le", "pcmf32le",
            "vorbis", "wma", "wmapro", "wmav2", "cook", "atrac", "atrac3"
        ]
        if convertCodecs.contains(normalized) { return .needsConvert }
        if normalized.contains("truehd") { return .needsConvert }
        if normalized.contains("dts") { return .needsConvert }
        if normalized.contains("pcm") { return .needsConvert }

        return .unknown
    }
}

/// Classification for subtitle handling strategy.
public enum SubtitleHandling: String, Sendable {
    /// Text-based, can be converted to WebVTT and attached externally.
    case textExternal    // SRT, VTT, ASS/SSA (best-effort convert)
    /// Bitmap-based, requires burn-in (server-side preferred).
    case bitmapBurnIn    // PGS, VobSub, DVB
    /// Unsupported format — disable with message.
    case unsupported

    public static func classify(_ codec: String) -> SubtitleHandling {
        let normalized = codec.lowercased()
        if normalized.contains("srt") || normalized.contains("subrip") { return .textExternal }
        if normalized.contains("vtt") || normalized.contains("webvtt") { return .textExternal }
        if normalized.contains("ass") || normalized.contains("ssa") { return .textExternal }
        if normalized.contains("pgs") || normalized.contains("hdmv") { return .bitmapBurnIn }
        if normalized.contains("dvdsub") || normalized.contains("vobsub") { return .bitmapBurnIn }
        if normalized.contains("dvb") { return .bitmapBurnIn }
        return .unsupported
    }
}

public enum SubtitleKind: String, Sendable {
    case text
    case bitmap
    case unknown
}

public enum TrackMetadataConfidence: String, Sendable {
    case server
    case demux
    case validated
}

// MARK: - Track Metadata

/// Describes a single media track extracted by the demuxer.
public struct TrackInfo: Sendable, Equatable, Identifiable {
    public enum TrackType: String, Sendable {
        case video, audio, subtitle
    }

    public let id: Int
    public let trackType: TrackType
    public let codecID: String           // e.g. "V_MPEG4/ISO/AVC", "A_AAC", "A_TRUEHD"
    public let codecName: String         // Normalized: "hevc", "aac", "truehd"
    public let language: String?
    public let isDefault: Bool
    public let isForced: Bool

    // Video-specific
    public let width: Int?
    public let height: Int?
    public let bitDepth: Int?
    public let chromaSubsampling: String? // "4:2:0", "4:2:2"
    public let codecPrivate: Data?        // Parameter sets (VPS/SPS/PPS for HEVC)

    // HDR metadata
    public let colourPrimaries: Int?        // BT.2020 = 9
    public let transferCharacteristic: Int? // PQ = 16, HLG = 18
    public let matrixCoefficients: Int?
    public let maxCLL: Int?                 // MaxCLL for HDR10 (nits)
    public let maxFALL: Int?                // MaxFALL for HDR10 (nits)
    // Mastering display luminance from MasteringMetadata EBML element
    public let masteringLuminanceMax: Double? // nits (e.g. 1000.0)
    public let masteringLuminanceMin: Double? // nits (e.g. 0.005)

    // Audio-specific
    public let sampleRate: Int?
    public let channels: Int?
    public let channelLayout: String?     // e.g. "7.1", "5.1"
    public let audioSupport: AudioCodecSupport?

    // Subtitle-specific
    public let subtitleHandling: SubtitleHandling?
    public let subtitleKind: SubtitleKind?
    public let metadataConfidence: TrackMetadataConfidence?

    public init(
        id: Int, trackType: TrackType, codecID: String, codecName: String,
        language: String? = nil, isDefault: Bool = false, isForced: Bool = false,
        width: Int? = nil, height: Int? = nil, bitDepth: Int? = nil,
        chromaSubsampling: String? = nil, codecPrivate: Data? = nil,
        colourPrimaries: Int? = nil, transferCharacteristic: Int? = nil,
        matrixCoefficients: Int? = nil, maxCLL: Int? = nil, maxFALL: Int? = nil,
        masteringLuminanceMax: Double? = nil, masteringLuminanceMin: Double? = nil,
        sampleRate: Int? = nil, channels: Int? = nil, channelLayout: String? = nil,
        audioSupport: AudioCodecSupport? = nil,
        subtitleHandling: SubtitleHandling? = nil,
        subtitleKind: SubtitleKind? = nil,
        metadataConfidence: TrackMetadataConfidence? = nil
    ) {
        self.id = id; self.trackType = trackType; self.codecID = codecID
        self.codecName = codecName; self.language = language
        self.isDefault = isDefault; self.isForced = isForced
        self.width = width; self.height = height; self.bitDepth = bitDepth
        self.chromaSubsampling = chromaSubsampling; self.codecPrivate = codecPrivate
        self.colourPrimaries = colourPrimaries
        self.transferCharacteristic = transferCharacteristic
        self.matrixCoefficients = matrixCoefficients
        self.maxCLL = maxCLL; self.maxFALL = maxFALL
        self.masteringLuminanceMax = masteringLuminanceMax
        self.masteringLuminanceMin = masteringLuminanceMin
        self.sampleRate = sampleRate; self.channels = channels
        self.channelLayout = channelLayout; self.audioSupport = audioSupport
        self.subtitleHandling = subtitleHandling
        self.subtitleKind = subtitleKind
        self.metadataConfidence = metadataConfidence
    }
}

// MARK: - Demuxer Packet

/// Timing-rich representation of a compressed media sample.
public struct Sample: Sendable {
    public let trackID: Int
    public let pts: CMTime
    public let dts: CMTime
    public let duration: CMTime
    public let isKeyframe: Bool
    public let data: Data

    public init(
        trackID: Int,
        pts: CMTime,
        dts: CMTime? = nil,
        duration: CMTime,
        isKeyframe: Bool,
        data: Data
    ) {
        self.trackID = trackID
        self.pts = pts
        self.dts = dts ?? pts
        self.duration = duration
        self.isKeyframe = isKeyframe
        self.data = data
    }

    public var ptsNanoseconds: Int64 { pts.nanosecondsValue }
    public var dtsNanoseconds: Int64 { dts.nanosecondsValue }
    public var durationNanoseconds: Int64 { max(0, duration.nanosecondsValue) }
}

/// A single demuxed packet (compressed frame / audio block / subtitle event).
public struct DemuxedPacket: Sendable {
    public let trackID: Int
    public let timestamp: Int64        // In nanoseconds
    public let duration: Int64         // In nanoseconds (0 if unknown)
    public let isKeyframe: Bool
    public let data: Data

    public init(trackID: Int, timestamp: Int64, duration: Int64, isKeyframe: Bool, data: Data) {
        self.trackID = trackID
        self.timestamp = timestamp
        self.duration = duration
        self.isKeyframe = isKeyframe
        self.data = data
    }

    public init(sample: Sample) {
        self.trackID = sample.trackID
        self.timestamp = sample.ptsNanoseconds
        self.duration = sample.durationNanoseconds
        self.isKeyframe = sample.isKeyframe
        self.data = sample.data
    }

    public var asSample: Sample {
        Sample(
            trackID: trackID,
            pts: .nanoseconds(timestamp),
            dts: .nanoseconds(timestamp),
            duration: .nanoseconds(max(0, duration)),
            isKeyframe: isKeyframe,
            data: data
        )
    }
}

// MARK: - Stream Info (Demuxer Output)

/// High-level file info returned after opening. Used by the decision engine.
public struct StreamInfo: Sendable, Equatable {
    public enum KeyframeIndexAvailability: String, Sendable, Equatable {
        case present
        case missing
        case unknown
    }

    public let durationNanoseconds: Int64
    public let tracks: [TrackInfo]
    public let hasChapters: Bool
    public let seekable: Bool         // true if cues/index exist
    public let keyframeIndexAvailability: KeyframeIndexAvailability

    public init(
        durationNanoseconds: Int64,
        tracks: [TrackInfo],
        hasChapters: Bool,
        seekable: Bool,
        keyframeIndexAvailability: KeyframeIndexAvailability? = nil
    ) {
        self.durationNanoseconds = durationNanoseconds
        self.tracks = tracks
        self.hasChapters = hasChapters
        self.seekable = seekable
        self.keyframeIndexAvailability = keyframeIndexAvailability ?? (seekable ? .present : .missing)
    }

    public var videoTracks: [TrackInfo] { tracks.filter { $0.trackType == .video } }
    public var audioTracks: [TrackInfo] { tracks.filter { $0.trackType == .audio } }
    public var subtitleTracks: [TrackInfo] { tracks.filter { $0.trackType == .subtitle } }

    public var primaryVideoTrack: TrackInfo? {
        videoTracks.first(where: \.isDefault) ?? videoTracks.first
    }

    public var primaryAudioTrack: TrackInfo? {
        audioTracks.first(where: \.isDefault) ?? audioTracks.first
    }
}

// MARK: - Native Bridge Plan

/// Describes the exact pipeline steps the native bridge will execute.
public struct NativeBridgePlan: Sendable, Equatable {
    public enum VideoAction: String, Sendable {
        case directPassthrough   // Copy HEVC/H.264 NALUs as-is
        case unsupported         // Cannot handle this codec
    }

    public enum AudioAction: String, Sendable {
        case directPassthrough   // AAC, AC-3, E-AC-3 → copy
        case serverTranscode     // Ask Jellyfin server to transcode audio only
        case clientFallback      // Future: in-app audio decode
    }

    public let itemID: String
    public let sourceID: String
    public let sourceURL: URL               // Jellyfin direct-stream or file URL
    public let videoTrack: TrackInfo
    public let audioTrack: TrackInfo?
    public let videoAction: VideoAction
    public let audioAction: AudioAction
    public let subtitleTracks: [TrackInfo]
    public let videoRangeType: String?
    public let dvProfile: Int?
    public let dvLevel: Int?
    public let dvBlSignalCompatibilityId: Int?
    public let hdr10PlusPresentFlag: Bool?
    public let diagnostics: NativeBridgeDiagnosticsConfig
    public let whyChosen: String            // Human-readable reason for debug UI

    public init(
        itemID: String, sourceID: String, sourceURL: URL,
        videoTrack: TrackInfo, audioTrack: TrackInfo?,
        videoAction: VideoAction, audioAction: AudioAction,
        subtitleTracks: [TrackInfo],
        videoRangeType: String? = nil,
        dvProfile: Int? = nil,
        dvLevel: Int? = nil,
        dvBlSignalCompatibilityId: Int? = nil,
        hdr10PlusPresentFlag: Bool? = nil,
        diagnostics: NativeBridgeDiagnosticsConfig = .disabled,
        whyChosen: String
    ) {
        self.itemID = itemID; self.sourceID = sourceID; self.sourceURL = sourceURL
        self.videoTrack = videoTrack; self.audioTrack = audioTrack
        self.videoAction = videoAction; self.audioAction = audioAction
        self.subtitleTracks = subtitleTracks
        self.videoRangeType = videoRangeType
        self.dvProfile = dvProfile
        self.dvLevel = dvLevel
        self.dvBlSignalCompatibilityId = dvBlSignalCompatibilityId
        self.hdr10PlusPresentFlag = hdr10PlusPresentFlag
        self.diagnostics = diagnostics
        self.whyChosen = whyChosen
    }
}

// MARK: - Telemetry / Metrics

/// Performance metrics collected during a native bridge playback session.
public struct NativeBridgeMetrics: Sendable {
    public var demuxInitMs: Double = 0
    public var firstFragmentMs: Double = 0
    public var timeToFirstFrameMs: Double = 0
    public var totalPacketsDemuxed: Int = 0
    public var totalFragmentsGenerated: Int = 0
    public var cacheMissCount: Int = 0
    public var cacheHitCount: Int = 0
    public var rangeRequestCount: Int = 0
    public var retryCount: Int = 0
    public var seekCount: Int = 0
    public var rebufferCount: Int = 0
    public var stallDurationMs: Double = 0
    public var methodChosen: String = ""
    public var whyChosen: String = ""
    public var activeDiagnostics: Bool = false

    public init() {}
}

// MARK: - Diagnostics

public struct NativeBridgeDiagnosticsConfig: Sendable, Equatable {
    public let enabled: Bool
    public let dumpSegments: Bool
    public let maxFragmentDumpCount: Int
    public let outputDirectoryURL: URL?

    public init(
        enabled: Bool = false,
        dumpSegments: Bool = false,
        maxFragmentDumpCount: Int = 8,
        outputDirectoryURL: URL? = nil
    ) {
        self.enabled = enabled
        self.dumpSegments = dumpSegments
        self.maxFragmentDumpCount = max(0, maxFragmentDumpCount)
        self.outputDirectoryURL = outputDirectoryURL
    }

    public static let disabled = NativeBridgeDiagnosticsConfig()
}

public struct NativeBridgeRequestTraceEntry: Sendable, Equatable {
    public let requestedOffset: Int64
    public let requestedLength: Int
    public let startedAt: Date
    public let finishedAt: Date?

    public init(requestedOffset: Int64, requestedLength: Int, startedAt: Date, finishedAt: Date?) {
        self.requestedOffset = requestedOffset
        self.requestedLength = requestedLength
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public struct NativeBridgeFragmentTraceEntry: Sendable, Equatable {
    public let sequenceNumber: Int
    public let moofSize: Int
    public let mdatSize: Int
    public let sampleCount: Int
    public let firstPTS: Int64

    public init(sequenceNumber: Int, moofSize: Int, mdatSize: Int, sampleCount: Int, firstPTS: Int64) {
        self.sequenceNumber = sequenceNumber
        self.moofSize = moofSize
        self.mdatSize = mdatSize
        self.sampleCount = sampleCount
        self.firstPTS = firstPTS
    }
}

public struct NativeBridgeDebugBundle: Sendable {
    public let itemID: String
    public let createdAt: Date
    public let initSegmentURL: URL?
    public let fragmentURLs: [URL]
    public let requestTrace: [NativeBridgeRequestTraceEntry]
    public let fragmentTrace: [NativeBridgeFragmentTraceEntry]
    public let trackDump: String

    public init(
        itemID: String,
        createdAt: Date = Date(),
        initSegmentURL: URL?,
        fragmentURLs: [URL],
        requestTrace: [NativeBridgeRequestTraceEntry],
        fragmentTrace: [NativeBridgeFragmentTraceEntry],
        trackDump: String
    ) {
        self.itemID = itemID
        self.createdAt = createdAt
        self.initSegmentURL = initSegmentURL
        self.fragmentURLs = fragmentURLs
        self.requestTrace = requestTrace
        self.fragmentTrace = fragmentTrace
        self.trackDump = trackDump
    }
}

public protocol NativeBridgeDebugBundleExporter: Sendable {
    func export(bundle: NativeBridgeDebugBundle) throws -> URL
}

// MARK: - Error

/// Errors specific to the native bridge pipeline.
public enum NativeBridgeError: LocalizedError, Sendable {
    case invalidMKV(String)
    case unsupportedCodec(String)
    case dvRejected(reason: String)
    case networkStall(String)
    case unsupportedContainer(String)
    case unsupportedVideoCodec(String)
    case noVideoTrack
    case noAudioTrack
    case demuxerFailed(String)
    case demuxerEOF
    case repackagerFailed(String)
    case resourceLoaderTimeout
    case seekFailed(String)
    case httpError(statusCode: Int, message: String)
    case cacheFull
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidMKV(let reason): return "Invalid MKV stream: \(reason)"
        case .unsupportedCodec(let codec): return "Codec '\(codec)' is not supported by native bridge."
        case .dvRejected(let reason): return "Dolby Vision disabled: \(reason)"
        case .networkStall(let message): return "Network stall detected: \(message)"
        case .unsupportedContainer(let c): return "Container '\(c)' is not supported by native bridge."
        case .unsupportedVideoCodec(let c): return "Video codec '\(c)' cannot be passed through to AVPlayer."
        case .noVideoTrack: return "No video track found in the file."
        case .noAudioTrack: return "No audio track found in the file."
        case .demuxerFailed(let msg): return "Demuxer error: \(msg)"
        case .demuxerEOF: return "Demuxer reached end of file unexpectedly."
        case .repackagerFailed(let msg): return "Repackager error: \(msg)"
        case .resourceLoaderTimeout: return "Resource loader timed out waiting for data."
        case .seekFailed(let msg): return "Seek failed: \(msg)"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .cacheFull: return "Chunk cache is full and cannot evict."
        case .cancelled: return "Native bridge operation was cancelled."
        }
    }
}

private extension CMTime {
    static func nanoseconds(_ value: Int64) -> CMTime {
        CMTime(value: value, timescale: 1_000_000_000)
    }

    var nanosecondsValue: Int64 {
        guard isNumeric && !isIndefinite && !isNegativeInfinity && !isPositiveInfinity else {
            return 0
        }
        let seconds = CMTimeGetSeconds(self)
        guard seconds.isFinite else { return 0 }
        return Int64(seconds * 1_000_000_000.0)
    }
}
