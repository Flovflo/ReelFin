import CoreMedia
import Foundation

public enum MediaTrackKind: String, Codable, Hashable, Sendable {
    case video
    case audio
    case subtitle
    case attachment
    case chapter
    case metadata
    case unknown
}

public struct TimeBase: Codable, Hashable, Sendable {
    public var numerator: Int32
    public var denominator: Int32

    public init(numerator: Int32 = 1, denominator: Int32 = 1_000_000_000) {
        self.numerator = numerator
        self.denominator = denominator
    }

    public static let nanoseconds = TimeBase()
}

public struct PacketTimestamp: Hashable, Sendable {
    public var pts: CMTime
    public var dts: CMTime?
    public var duration: CMTime?

    public init(pts: CMTime, dts: CMTime? = nil, duration: CMTime? = nil) {
        self.pts = pts
        self.dts = dts
        self.duration = duration
    }
}

public struct MediaTrack: Identifiable, Hashable, Sendable {
    public var id: String
    public var trackId: Int
    public var kind: MediaTrackKind
    public var codec: String
    public var codecID: String?
    public var language: String?
    public var title: String?
    public var isDefault: Bool
    public var isForced: Bool
    public var codecPrivateData: Data?
    public var duration: CMTime?
    public var bitrate: Int?
    public var timebase: TimeBase
    public var audioSampleRate: Double?
    public var audioChannels: Int?
    public var audioBitDepth: Int?
    public var hdrMetadata: HDRMetadata?

    public init(
        id: String,
        trackId: Int,
        kind: MediaTrackKind,
        codec: String,
        codecID: String? = nil,
        language: String? = nil,
        title: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        codecPrivateData: Data? = nil,
        duration: CMTime? = nil,
        bitrate: Int? = nil,
        timebase: TimeBase = .nanoseconds,
        audioSampleRate: Double? = nil,
        audioChannels: Int? = nil,
        audioBitDepth: Int? = nil,
        hdrMetadata: HDRMetadata? = nil
    ) {
        self.id = id
        self.trackId = trackId
        self.kind = kind
        self.codec = codec
        self.codecID = codecID
        self.language = language
        self.title = title
        self.isDefault = isDefault
        self.isForced = isForced
        self.codecPrivateData = codecPrivateData
        self.duration = duration
        self.bitrate = bitrate
        self.timebase = timebase
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
        self.audioBitDepth = audioBitDepth
        self.hdrMetadata = hdrMetadata
    }
}

public struct VideoTrack: Hashable, Sendable {
    public var base: MediaTrack
    public var width: Int?
    public var height: Int?
    public var frameRate: Double?
    public var bitDepth: Int?
    public var hdr: HDRMetadata?

    public init(base: MediaTrack, width: Int? = nil, height: Int? = nil, frameRate: Double? = nil, bitDepth: Int? = nil, hdr: HDRMetadata? = nil) {
        self.base = base
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.bitDepth = bitDepth
        self.hdr = hdr
    }
}

public struct AudioTrack: Hashable, Sendable {
    public var base: MediaTrack
    public var channelCount: Int?
    public var sampleRate: Double?
    public var channelLayout: String?

    public init(base: MediaTrack, channelCount: Int? = nil, sampleRate: Double? = nil, channelLayout: String? = nil) {
        self.base = base
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.channelLayout = channelLayout
    }
}

public struct SubtitleTrack: Hashable, Sendable {
    public var base: MediaTrack
    public var format: SubtitleFormat

    public init(base: MediaTrack, format: SubtitleFormat) {
        self.base = base
        self.format = format
    }
}
