import CoreMedia
import Foundation

public actor MatroskaDemuxer: MediaDemuxer {
    private static let initialReadBytes = 8 * 1024 * 1024
    private static let maxClusterReadBytes = 32 * 1024 * 1024

    private let source: any MediaByteSource
    private let profile: MatroskaProfile
    private let reader = EBMLReader()
    private let clusterParser = MatroskaClusterParser()
    private var streamInfo: DemuxerStreamInfo?
    private var packets: [MediaPacket] = []
    private var packetIndex = 0
    private var nextTopLevelOffset: Int64?
    private var segmentEndOffset: Int64?
    private var segmentPayloadOffset: Int64 = 0
    private var cuePoints: [MatroskaCuePoint] = []
    private var timecodeScale: Int64 = 1_000_000
    private var defaultDurations: [Int: CMTime] = [:]

    public init(source: any MediaByteSource, profile: MatroskaProfile = .matroska) {
        self.source = source
        self.profile = profile
    }

    public func open() async throws -> DemuxerStreamInfo {
        if let streamInfo { return streamInfo }
        let data = try await source.read(range: ByteRange(offset: 0, length: Self.initialReadBytes))
        let segment = try MatroskaSegmentParser().parse(data: data)
        timecodeScale = segment.info.timecodeScale
        segmentPayloadOffset = Int64(segment.segmentPayloadOffset ?? 0)
        segmentEndOffset = segment.segmentEndOffset.map(Int64.init)
        nextTopLevelOffset = Int64(segment.parsedUntilOffset)
        cuePoints = segment.cues
        defaultDurations = MatroskaTrackTiming.defaultDurations(for: segment.tracks)
        packets = segment.packets
        let duration = segment.info.duration.map {
            CMTime(seconds: $0 * Double(segment.info.timecodeScale) / 1_000_000_000, preferredTimescale: 1000)
        }
        let tracks = segment.tracks.map { track in
            MediaTrack(
                id: "\(track.number)",
                trackId: track.number,
                kind: track.type,
                codec: track.codec,
                codecID: track.codecID,
                language: track.language,
                title: track.name,
                isDefault: track.isDefault,
                isForced: track.isForced,
                codecPrivateData: track.codecPrivate,
                duration: duration,
                timebase: .nanoseconds,
                audioSampleRate: track.audio?.sampleRate,
                audioChannels: track.audio?.channels,
                audioBitDepth: track.audio?.bitDepth
            )
        }
        let info = DemuxerStreamInfo(
            container: profile == .webm ? .webm : .matroska,
            duration: duration,
            tracks: tracks,
            seekMap: SeekMap(duration: duration, isSeekable: !segment.cues.isEmpty)
        )
        streamInfo = info
        return info
    }

    public func readNextPacket() async throws -> MediaPacket? {
        if streamInfo == nil { _ = try await open() }
        if packetIndex >= packets.count {
            try await loadMorePacketsIfNeeded()
        }
        guard packetIndex < packets.count else { return nil }
        defer { packetIndex += 1 }
        return packets[packetIndex]
    }

    public func seek(to time: CMTime) async throws {
        if let cueOffset = cueOffset(for: time) {
            packets.removeAll(keepingCapacity: true)
            packetIndex = 0
            nextTopLevelOffset = cueOffset
            return
        }
        if let index = packets.firstIndex(where: { $0.timestamp.pts >= time }) {
            packetIndex = index
            return
        }
        packetIndex = 0
    }

    private func cueOffset(for time: CMTime) -> Int64? {
        guard !cuePoints.isEmpty else { return nil }
        let targetTimecode = UInt64(max(0, time.seconds) * 1_000_000_000 / Double(timecodeScale))
        return cuePoints
            .filter { $0.timecode <= targetTimecode && $0.clusterPosition != nil }
            .max { $0.timecode < $1.timecode }
            .flatMap { $0.clusterPosition.map { segmentPayloadOffset + Int64($0) } }
    }

    private func loadMorePacketsIfNeeded() async throws {
        guard let startOffset = nextTopLevelOffset else { return }
        var offset = startOffset
        let sourceSize = try await source.size()
        let hardEnd = segmentEndOffset ?? sourceSize

        while packets.count == packetIndex {
            if let hardEnd, offset >= hardEnd {
                nextTopLevelOffset = nil
                return
            }
            let headerData = try await source.read(range: ByteRange(offset: offset, length: 16))
            guard !headerData.isEmpty else {
                nextTopLevelOffset = nil
                return
            }
            let header = try reader.readHeader(data: headerData, offset: 0)
            guard let elementSize = header.size else {
                throw EBMLError.invalidMatroska("Matroska top-level element at byte \(offset) has unknown size; streaming parser cannot skip it yet.")
            }
            let totalSize = Int64(header.totalHeaderSize) + elementSize
            if header.id == EBMLElementID.cluster {
                let clusterData = try await readCluster(offset: offset, totalSize: totalSize)
                let localHeader = try reader.readHeader(data: clusterData, offset: 0)
                let parsed = try clusterParser.parseCluster(
                    data: clusterData,
                    header: localHeader,
                    timecodeScale: timecodeScale,
                    trackDefaultDurations: defaultDurations
                )
                packets.append(contentsOf: applyDefaultDurations(parsed))
            }
            offset += totalSize
            nextTopLevelOffset = offset
        }
    }

    private func readCluster(offset: Int64, totalSize: Int64) async throws -> Data {
        guard totalSize > 0 else {
            throw EBMLError.invalidMatroska("Matroska cluster at byte \(offset) has invalid size \(totalSize).")
        }
        guard totalSize <= Int64(Self.maxClusterReadBytes) else {
            throw EBMLError.invalidMatroska("Matroska cluster at byte \(offset) is \(totalSize) bytes; streaming partial cluster parsing is not implemented yet.")
        }
        return try await source.read(range: ByteRange(offset: offset, length: Int(totalSize)))
    }

    private func applyDefaultDurations(_ newPackets: [MediaPacket]) -> [MediaPacket] {
        guard !defaultDurations.isEmpty else { return newPackets }
        return newPackets.map { packet in
            var adjusted = packet
            if adjusted.timestamp.duration == nil {
                adjusted.timestamp.duration = defaultDurations[packet.trackID]
            }
            return adjusted
        }
    }
}
