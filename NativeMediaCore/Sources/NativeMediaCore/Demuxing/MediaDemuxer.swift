import CoreMedia
import Foundation

public struct MediaPacket: Sendable, Hashable {
    public var trackID: Int
    public var timestamp: PacketTimestamp
    public var isKeyframe: Bool
    public var data: Data

    public init(trackID: Int, timestamp: PacketTimestamp, isKeyframe: Bool, data: Data) {
        self.trackID = trackID
        self.timestamp = timestamp
        self.isKeyframe = isKeyframe
        self.data = data
    }
}

public struct SeekMap: Sendable, Hashable {
    public var duration: CMTime?
    public var isSeekable: Bool
    public var keyframes: [CMTime]

    public init(duration: CMTime? = nil, isSeekable: Bool = false, keyframes: [CMTime] = []) {
        self.duration = duration
        self.isSeekable = isSeekable
        self.keyframes = keyframes
    }
}

public protocol PacketReader: Sendable {
    func readNextPacket() async throws -> MediaPacket?
}

public protocol SeekIndex: Sendable {
    func nearestPacketOffset(for time: CMTime) async -> Int64?
}

public protocol TimestampMapper: Sendable {
    func presentationTime(clusterTimecode: Int64, blockTimecode: Int16, scale: Int64) -> CMTime
}

public protocol MediaDemuxer: Sendable {
    func open() async throws -> DemuxerStreamInfo
    func readNextPacket() async throws -> MediaPacket?
    func seek(to time: CMTime) async throws
}

public struct DemuxerStreamInfo: Sendable, Hashable {
    public var container: ContainerFormat
    public var duration: CMTime?
    public var bitrate: Int?
    public var tracks: [MediaTrack]
    public var chapters: [ChapterTrack]
    public var attachments: [AttachmentTrack]
    public var seekMap: SeekMap

    public init(
        container: ContainerFormat,
        duration: CMTime? = nil,
        bitrate: Int? = nil,
        tracks: [MediaTrack] = [],
        chapters: [ChapterTrack] = [],
        attachments: [AttachmentTrack] = [],
        seekMap: SeekMap = SeekMap()
    ) {
        self.container = container
        self.duration = duration
        self.bitrate = bitrate
        self.tracks = tracks
        self.chapters = chapters
        self.attachments = attachments
        self.seekMap = seekMap
    }
}

public struct AttachmentTrack: Hashable, Sendable {
    public var id: String
    public var name: String
    public var mimeType: String?
    public var data: Data?

    public init(id: String, name: String, mimeType: String? = nil, data: Data? = nil) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.data = data
    }
}

public struct ChapterTrack: Hashable, Sendable {
    public var id: String
    public var title: String?
    public var start: CMTime
    public var end: CMTime?

    public init(id: String, title: String? = nil, start: CMTime, end: CMTime? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
    }
}
