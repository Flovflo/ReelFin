import CoreMedia
import Foundation

public actor MatroskaDemuxer: MediaDemuxer {
    private static let initialReadBytes = 8 * 1024 * 1024
    private static let maxCuesReadBytes = 16 * 1024 * 1024
    private static let maxClusterReadBytes = 32 * 1024 * 1024
    private static let approximateSeekPrerollSeconds = 12.0
    private static let approximateSeekSearchBytesBefore = 8 * 1024 * 1024
    private static let approximateSeekSearchBytesAfter = 16 * 1024 * 1024

    private let source: any MediaByteSource
    private let profile: MatroskaProfile
    private let reader = EBMLReader()
    private let clusterParser = MatroskaClusterParser()
    private var streamInfo: DemuxerStreamInfo?
    private var packets: [MediaPacket] = []
    private var packetIndex = 0
    private var nextTopLevelOffset: Int64?
    private var firstClusterOffset: Int64?
    private var segmentEndOffset: Int64?
    private var segmentPayloadOffset: Int64 = 0
    private var cuePoints: [MatroskaCuePoint] = []
    private var clusterSeekIndex: [ClusterSeekCandidate] = []
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
        firstClusterOffset = segment.firstClusterOffset.map(Int64.init)
        nextTopLevelOffset = Int64(segment.parsedUntilOffset)
        cuePoints = segment.cues
        if cuePoints.isEmpty {
            cuePoints = try await loadCuesFromSeekHead(segment.seekHead)
        }
        clusterSeekIndex = segment.clusterRanges.compactMap {
            clusterSeekCandidate(in: data, offset: $0.offset, baseOffset: 0)
        }
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
                audioBitDepth: track.audio?.bitDepth,
                hdrMetadata: track.video?.hdr
            )
        }
        let info = DemuxerStreamInfo(
            container: profile == .webm ? .webm : .matroska,
            duration: duration,
            tracks: tracks,
            seekMap: SeekMap(duration: duration, isSeekable: !cuePoints.isEmpty)
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
        if loadedPacketsCover(time), let index = nearestLoadedVideoKeyframeIndex(for: time) {
            packetIndex = index
            return
        }
        if let indexedOffset = indexedClusterOffset(for: time.seconds) {
            packets.removeAll(keepingCapacity: true)
            packetIndex = 0
            nextTopLevelOffset = indexedOffset
            return
        }
        if let approximateOffset = try await approximateClusterOffset(for: time) {
            packets.removeAll(keepingCapacity: true)
            packetIndex = 0
            nextTopLevelOffset = approximateOffset
            return
        }
        if let index = nearestLoadedVideoKeyframeIndex(for: time) {
            packetIndex = index
            return
        }
        packetIndex = 0
    }

    private func loadCuesFromSeekHead(_ seekHead: [UInt32: UInt64]) async throws -> [MatroskaCuePoint] {
        guard let relativeOffset = seekHead[EBMLElementID.cues] else { return [] }
        let absoluteOffset = segmentPayloadOffset + Int64(relativeOffset)
        let headerData = try await source.read(range: ByteRange(offset: absoluteOffset, length: 16))
        guard !headerData.isEmpty else { return [] }
        let header = try reader.readHeader(data: headerData, offset: 0)
        guard header.id == EBMLElementID.cues,
              let elementSize = header.size,
              elementSize >= 0 else {
            return []
        }
        let totalSize = Int64(header.totalHeaderSize) + elementSize
        guard totalSize > 0, totalSize <= Int64(Self.maxCuesReadBytes) else { return [] }
        let cuesData = try await source.read(range: ByteRange(offset: absoluteOffset, length: Int(totalSize)))
        let localHeader = try reader.readHeader(data: cuesData, offset: 0)
        let payloadEnd = localHeader.payloadOffset + Int(localHeader.size ?? 0)
        guard payloadEnd <= cuesData.count else { return [] }
        return try MatroskaCueParser().parseCues(data: Data(cuesData[localHeader.payloadOffset..<payloadEnd]))
    }

    private func loadedPacketsCover(_ time: CMTime) -> Bool {
        let targetSeconds = time.seconds
        return packets.contains { $0.timestamp.pts.seconds >= targetSeconds }
    }

    private func nearestLoadedVideoKeyframeIndex(for time: CMTime) -> Int? {
        guard let streamInfo else { return nil }
        let videoTrackIDs = Set(streamInfo.tracks.filter { $0.kind == .video }.map(\.trackId))
        guard !videoTrackIDs.isEmpty else { return nil }
        let targetSeconds = time.seconds
        if let prerollIndex = packets.indices.last(where: { index in
            let packet = packets[index]
            return videoTrackIDs.contains(packet.trackID)
                && packet.isKeyframe
                && packet.timestamp.pts.seconds <= targetSeconds
        }) {
            return prerollIndex
        }
        return packets.indices.first { index in
            let packet = packets[index]
            return videoTrackIDs.contains(packet.trackID)
                && packet.isKeyframe
                && packet.timestamp.pts.seconds >= targetSeconds
        }
    }

    private func approximateClusterOffset(for time: CMTime) async throws -> Int64? {
        guard cuePoints.isEmpty else { return nil }
        guard let durationSeconds = streamInfo?.duration?.seconds,
              durationSeconds.isFinite,
              durationSeconds > 0,
              time.seconds.isFinite,
              time.seconds > 0.05,
              let lowerBound = firstClusterOffset else {
            return nil
        }
        let sourceSize = try await source.size()
        guard let upperBound = segmentEndOffset ?? sourceSize,
              upperBound > lowerBound else {
            return nil
        }
        let mediaBytes = upperBound - lowerBound
        let estimateSeconds = max(0, time.seconds - Self.approximateSeekPrerollSeconds)
        let ratio = min(max(estimateSeconds / durationSeconds, 0), 1)
        let estimatedOffset = lowerBound + Int64(Double(mediaBytes) * ratio)
        let windowStart = max(lowerBound, estimatedOffset - Int64(Self.approximateSeekSearchBytesBefore))
        let windowEnd = min(upperBound, estimatedOffset + Int64(Self.approximateSeekSearchBytesAfter))
        guard windowEnd > windowStart else { return nil }
        let data = try await source.read(range: ByteRange(offset: windowStart, length: Int(windowEnd - windowStart)))
        let candidates = clusterSeekCandidates(in: data, baseOffset: windowStart)
        rememberClusterSeekCandidates(candidates)
        return bestClusterSeekOffset(from: candidates, targetSeconds: time.seconds)
    }

    private struct ClusterSeekCandidate {
        var offset: Int64
        var timeSeconds: Double
    }

    private func indexedClusterOffset(for targetSeconds: Double) -> Int64? {
        guard clusterSeekIndex.contains(where: { $0.timeSeconds >= targetSeconds }) else {
            return nil
        }
        return bestClusterSeekOffset(from: clusterSeekIndex, targetSeconds: targetSeconds)
    }

    private func rememberClusterSeekCandidates(_ candidates: [ClusterSeekCandidate]) {
        guard !candidates.isEmpty else { return }
        var byOffset = Dictionary(uniqueKeysWithValues: clusterSeekIndex.map { ($0.offset, $0) })
        for candidate in candidates {
            byOffset[candidate.offset] = candidate
        }
        clusterSeekIndex = byOffset.values.sorted {
            if $0.timeSeconds == $1.timeSeconds { return $0.offset < $1.offset }
            return $0.timeSeconds < $1.timeSeconds
        }
    }

    private func clusterSeekCandidates(in data: Data, baseOffset: Int64) -> [ClusterSeekCandidate] {
        guard data.count >= 4 else { return [] }
        var candidates: [ClusterSeekCandidate] = []
        var offset = 0
        while offset <= data.count - 4 {
            if data[offset] == 0x1F,
               data[offset + 1] == 0x43,
               data[offset + 2] == 0xB6,
               data[offset + 3] == 0x75,
               let candidate = clusterSeekCandidate(in: data, offset: offset, baseOffset: baseOffset) {
                candidates.append(candidate)
                offset += 4
            } else {
                offset += 1
            }
        }
        return candidates
    }

    private func clusterSeekCandidate(in data: Data, offset: Int, baseOffset: Int64) -> ClusterSeekCandidate? {
        guard let header = try? reader.readHeader(data: data, offset: offset),
              header.id == EBMLElementID.cluster,
              let timeSeconds = clusterTimeSeconds(in: data, header: header) else {
            return nil
        }
        return ClusterSeekCandidate(offset: baseOffset + Int64(offset), timeSeconds: timeSeconds)
    }

    private func clusterTimeSeconds(in data: Data, header: EBMLElementHeader) -> Double? {
        let payloadLimit = header.size.flatMap { size -> Int? in
            guard size >= 0, let sizeInt = Int(exactly: size) else { return nil }
            return header.payloadOffset + sizeInt
        } ?? data.count
        let scanLimit = min(data.count, payloadLimit, header.payloadOffset + 64 * 1024)
        var offset = header.payloadOffset
        while offset < scanLimit {
            guard let child = try? reader.readHeader(data: data, offset: offset),
                  let size = child.size,
                  size >= 0,
                  let sizeInt = Int(exactly: size) else {
                return nil
            }
            let childEnd = child.payloadOffset + sizeInt
            guard childEnd <= data.count, childEnd <= scanLimit else { return nil }
            if child.id == EBMLElementID.timecode,
               let rawTimecode = try? reader.readUInt(data: data, offset: child.payloadOffset, size: sizeInt) {
                return Double(rawTimecode) * Double(timecodeScale) / 1_000_000_000
            }
            guard childEnd > offset else { return nil }
            offset = childEnd
        }
        return nil
    }

    private func bestClusterSeekOffset(from candidates: [ClusterSeekCandidate], targetSeconds: Double) -> Int64? {
        if let beforeTarget = candidates
            .filter({ $0.timeSeconds <= targetSeconds })
            .max(by: { $0.timeSeconds < $1.timeSeconds }) {
            return beforeTarget.offset
        }
        return candidates.min(by: {
            abs($0.timeSeconds - targetSeconds) < abs($1.timeSeconds - targetSeconds)
        })?.offset
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
                if let candidate = clusterSeekCandidate(in: clusterData, offset: 0, baseOffset: offset) {
                    rememberClusterSeekCandidates([candidate])
                }
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
