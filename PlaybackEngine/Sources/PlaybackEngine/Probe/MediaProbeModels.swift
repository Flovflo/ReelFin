import Foundation
import Shared

public enum MetadataConfidence: String, Sendable, Codable {
    case server
    case demux
    case validated
}

public enum ProbeSubtitleKind: String, Sendable, Codable {
    case text
    case bitmap
    case unknown
}

public struct ProbeTrack: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let codec: String
    public let language: String?
    public let isDefault: Bool
    public let isForced: Bool
    public let subtitleKind: ProbeSubtitleKind?

    public init(
        id: String,
        codec: String,
        language: String?,
        isDefault: Bool,
        isForced: Bool = false,
        subtitleKind: ProbeSubtitleKind? = nil
    ) {
        self.id = id
        self.codec = codec
        self.language = language
        self.isDefault = isDefault
        self.isForced = isForced
        self.subtitleKind = subtitleKind
    }
}

public struct MediaProbeResult: Sendable, Equatable, Codable {
    public let itemID: String
    public let sourceID: String
    public let container: String
    public let directPlayURL: URL?
    public let directStreamURL: URL?
    public let transcodeURL: URL?

    public let videoCodec: String
    public let audioCodec: String
    public let videoBitDepth: Int?
    public let videoRangeType: String?
    public let dvProfile: Int?
    public let dvLevel: Int?
    public let dvBlSignalCompatibilityId: Int?
    public let hdr10PlusPresent: Bool

    public let audioTracks: [ProbeTrack]
    public let subtitleTracks: [ProbeTrack]

    public let hasKeyframeIndex: Bool
    public let confidence: MetadataConfidence

    public init(
        itemID: String,
        sourceID: String,
        container: String,
        directPlayURL: URL?,
        directStreamURL: URL?,
        transcodeURL: URL?,
        videoCodec: String,
        audioCodec: String,
        videoBitDepth: Int?,
        videoRangeType: String?,
        dvProfile: Int?,
        dvLevel: Int?,
        dvBlSignalCompatibilityId: Int?,
        hdr10PlusPresent: Bool,
        audioTracks: [ProbeTrack],
        subtitleTracks: [ProbeTrack],
        hasKeyframeIndex: Bool,
        confidence: MetadataConfidence
    ) {
        self.itemID = itemID
        self.sourceID = sourceID
        self.container = container
        self.directPlayURL = directPlayURL
        self.directStreamURL = directStreamURL
        self.transcodeURL = transcodeURL
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.videoBitDepth = videoBitDepth
        self.videoRangeType = videoRangeType
        self.dvProfile = dvProfile
        self.dvLevel = dvLevel
        self.dvBlSignalCompatibilityId = dvBlSignalCompatibilityId
        self.hdr10PlusPresent = hdr10PlusPresent
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.hasKeyframeIndex = hasKeyframeIndex
        self.confidence = confidence
    }
}

public struct OutputConstraints: Sendable, Equatable, Codable {
    public let airPlayActive: Bool
    public let externalDisplayActive: Bool

    public init(airPlayActive: Bool = false, externalDisplayActive: Bool = false) {
        self.airPlayActive = airPlayActive
        self.externalDisplayActive = externalDisplayActive
    }
}

public struct PlaybackPlanningInput: Sendable {
    public let itemID: String
    public let probes: [MediaProbeResult]
    public let device: DeviceCapabilityFingerprint
    public let constraints: OutputConstraints
    public let allowTranscoding: Bool

    public init(
        itemID: String,
        probes: [MediaProbeResult],
        device: DeviceCapabilityFingerprint,
        constraints: OutputConstraints = .init(),
        allowTranscoding: Bool
    ) {
        self.itemID = itemID
        self.probes = probes
        self.device = device
        self.constraints = constraints
        self.allowTranscoding = allowTranscoding
    }
}

public protocol MediaProbeProtocol: Sendable {
    func probe(itemID: String, source: MediaSource) -> MediaProbeResult
}
