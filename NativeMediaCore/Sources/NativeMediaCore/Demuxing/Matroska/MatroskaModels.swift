import CoreMedia
import Foundation

public enum MatroskaProfile: Sendable, Equatable {
    case matroska
    case webm
}

public struct MatroskaInfo: Sendable, Equatable {
    public var timecodeScale: Int64
    public var duration: Double?

    public init(timecodeScale: Int64 = 1_000_000, duration: Double? = nil) {
        self.timecodeScale = timecodeScale
        self.duration = duration
    }
}

public struct MatroskaParsedTrack: Sendable, Equatable {
    public var number: Int
    public var type: MediaTrackKind
    public var codecID: String
    public var codec: String
    public var codecPrivate: Data?
    public var language: String?
    public var name: String?
    public var isDefault: Bool
    public var isForced: Bool
    public var defaultDuration: UInt64?
    public var video: MatroskaVideoMetadata?
    public var audio: MatroskaAudioMetadata?

    public init(number: Int, type: MediaTrackKind, codecID: String, codec: String) {
        self.number = number
        self.type = type
        self.codecID = codecID
        self.codec = codec
        self.isDefault = false
        self.isForced = false
    }
}

public struct MatroskaVideoMetadata: Sendable, Equatable {
    public var width: Int?
    public var height: Int?
    public var hdr: HDRMetadata?
}

public struct MatroskaAudioMetadata: Sendable, Equatable {
    public var channels: Int?
    public var sampleRate: Double?
    public var bitDepth: Int?
}

public struct MatroskaCuePoint: Sendable, Equatable {
    public var timecode: UInt64
    public var track: UInt64?
    public var clusterPosition: UInt64?
}

public struct MatroskaClusterRange: Sendable, Equatable {
    public var offset: Int
    public var payloadOffset: Int
    public var endOffset: Int?

    public init(offset: Int, payloadOffset: Int, endOffset: Int?) {
        self.offset = offset
        self.payloadOffset = payloadOffset
        self.endOffset = endOffset
    }
}

public struct MatroskaParsedBlock: Sendable, Equatable {
    public var trackNumber: Int
    public var relativeTimecode: Int16
    public var keyframe: Bool
    public var invisible: Bool
    public var payload: Data
}

public struct MatroskaSegment: Sendable, Equatable {
    public var info: MatroskaInfo
    public var tracks: [MatroskaParsedTrack]
    public var cues: [MatroskaCuePoint]
    public var firstClusterOffset: Int?
    public var segmentPayloadOffset: Int?
    public var segmentEndOffset: Int?
    public var parsedUntilOffset: Int
    public var clusterRanges: [MatroskaClusterRange]
    public var packets: [MediaPacket]

    public init(
        info: MatroskaInfo = MatroskaInfo(),
        tracks: [MatroskaParsedTrack] = [],
        cues: [MatroskaCuePoint] = [],
        firstClusterOffset: Int? = nil,
        segmentPayloadOffset: Int? = nil,
        segmentEndOffset: Int? = nil,
        parsedUntilOffset: Int = 0,
        clusterRanges: [MatroskaClusterRange] = [],
        packets: [MediaPacket] = []
    ) {
        self.info = info
        self.tracks = tracks
        self.cues = cues
        self.firstClusterOffset = firstClusterOffset
        self.segmentPayloadOffset = segmentPayloadOffset
        self.segmentEndOffset = segmentEndOffset
        self.parsedUntilOffset = parsedUntilOffset
        self.clusterRanges = clusterRanges
        self.packets = packets
    }
}
