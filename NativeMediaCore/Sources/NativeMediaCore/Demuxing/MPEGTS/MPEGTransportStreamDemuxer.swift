import CoreMedia
import Foundation

public actor MPEGTransportStreamDemuxer: MediaDemuxer {
    private let source: any MediaByteSource
    private let format: ContainerFormat
    private let packetParser: MPEGTSPacketParser
    private let sectionParser = MPEGTSSectionParser()
    private let pesParser = PESPacketParser()

    private var streamInfo: DemuxerStreamInfo?
    private var readOffset: Int64 = 0
    private var pmtPID: Int?
    private var streamsByPID: [Int: MPEGTSStream] = [:]
    private var assemblies: [Int: Data] = [:]
    private var assemblyOrder: [Int] = []
    private var packets: [MediaPacket] = []
    private var reachedEOF = false

    public init(source: any MediaByteSource, format: ContainerFormat = .mpegTS) {
        self.source = source
        self.format = format
        self.packetParser = MPEGTSPacketParser(format: format)
    }

    public func open() async throws -> DemuxerStreamInfo {
        if let streamInfo { return streamInfo }
        var scannedBytes = 0
        while shouldContinueInitialScan(scannedBytes: scannedBytes) {
            let read = try await readMoreTransportPackets(maxPackets: 256)
            scannedBytes += read
            if read == 0 { break }
        }
        guard pmtPID != nil else { throw MPEGTransportStreamError.noProgramMap }
        guard !streamsByPID.isEmpty else { throw MPEGTransportStreamError.noElementaryStreams }
        let info = DemuxerStreamInfo(
            container: format == .m2ts ? .m2ts : .mpegTS,
            tracks: tracks(),
            seekMap: SeekMap(isSeekable: false)
        )
        streamInfo = info
        return info
    }

    public func readNextPacket() async throws -> MediaPacket? {
        _ = try await open()
        while packets.isEmpty, !reachedEOF {
            if try await readMoreTransportPackets(maxPackets: 256) == 0 {
                flushOpenAssemblies()
            }
        }
        guard !packets.isEmpty else { return nil }
        return packets.removeFirst()
    }

    public func seek(to time: CMTime) async throws {
        guard time <= .zero else { return }
        readOffset = 0
        pmtPID = nil
        streamsByPID.removeAll()
        assemblies.removeAll()
        assemblyOrder.removeAll()
        packets.removeAll()
        streamInfo = nil
        reachedEOF = false
    }

    private func shouldContinueInitialScan(scannedBytes: Int) -> Bool {
        guard scannedBytes < 4 * 1024 * 1024 else { return false }
        guard !streamsByPID.isEmpty else { return true }
        if packets.isEmpty { return true }
        return streamsByPID.values.contains { stream in
            (stream.codec == "h264" || stream.codec == "aac") && stream.codecPrivateData == nil
        }
    }

    private func readMoreTransportPackets(maxPackets: Int) async throws -> Int {
        let length = packetParser.packetSize * maxPackets
        let data = try await source.read(range: ByteRange(offset: readOffset, length: length))
        guard !data.isEmpty else {
            reachedEOF = true
            flushOpenAssemblies()
            return 0
        }
        let fullPackets = data.count / packetParser.packetSize
        for index in 0..<fullPackets {
            let start = index * packetParser.packetSize
            let end = start + packetParser.packetSize
            let packet = try packetParser.parse(
                data: Data(data[start..<end]),
                absoluteOffset: readOffset + Int64(start)
            )
            try handle(packet)
        }
        readOffset += Int64(fullPackets * packetParser.packetSize)
        if fullPackets == 0 { reachedEOF = true }
        return fullPackets * packetParser.packetSize
    }

    private func handle(_ packet: MPEGTSPacket) throws {
        guard !packet.payload.isEmpty else { return }
        if packet.pid == 0, packet.payloadUnitStart {
            pmtPID = sectionParser.parsePAT(packet.payload) ?? pmtPID
            return
        }
        if packet.pid == pmtPID, packet.payloadUnitStart {
            mergePMT(sectionParser.parsePMT(packet.payload))
            return
        }
        guard let stream = streamsByPID[packet.pid] else { return }
        if packet.payloadUnitStart {
            try flush(pid: packet.pid, stream: stream)
            assemblies[packet.pid] = packet.payload
            if !assemblyOrder.contains(packet.pid) {
                assemblyOrder.append(packet.pid)
            }
        } else {
            if assemblies[packet.pid] == nil {
                assemblyOrder.append(packet.pid)
            }
            assemblies[packet.pid, default: Data()].append(packet.payload)
        }
    }

    private func mergePMT(_ streams: [MPEGTSStream]) {
        guard !streams.isEmpty else { return }
        for stream in streams {
            var merged = stream
            if let existing = streamsByPID[stream.pid] {
                merged.trackID = existing.trackID
                merged.codecPrivateData = existing.codecPrivateData
                merged.audioSampleRate = existing.audioSampleRate
                merged.audioChannels = existing.audioChannels
            }
            streamsByPID[stream.pid] = merged
        }
    }

    private func flush(pid: Int, stream: MPEGTSStream) throws {
        guard let data = assemblies.removeValue(forKey: pid), !data.isEmpty else { return }
        updateMetadata(from: data, pid: pid, stream: stream)
        if let updated = streamsByPID[pid] {
            packets.append(contentsOf: try pesParser.parsePackets(data, stream: updated))
        }
    }

    private func flushOpenAssemblies() {
        for pid in assemblyOrder {
            guard let data = assemblies[pid], !data.isEmpty else { continue }
            guard let stream = streamsByPID[pid] else { continue }
            updateMetadata(from: data, pid: pid, stream: stream)
            if let parsed = try? pesParser.parsePackets(data, stream: streamsByPID[pid] ?? stream) {
                packets.append(contentsOf: parsed)
            }
        }
        assemblies.removeAll()
        assemblyOrder.removeAll()
    }

    private func updateMetadata(from pesData: Data, pid: Int, stream: MPEGTSStream) {
        guard var updated = streamsByPID[pid], let payload = pesPayload(from: pesData) else { return }
        if stream.codec == "h264", updated.codecPrivateData == nil {
            updated.codecPrivateData = AnnexBNALUnitParser.makeAVCC(fromAnnexB: payload)
        } else if stream.codec == "hevc", updated.codecPrivateData == nil {
            updated.codecPrivateData = AnnexBNALUnitParser.makeHVCC(fromAnnexB: payload)
        } else if stream.codec == "aac", let header = AACADTSHeader.parse(payload) {
            updated.codecPrivateData = header.audioSpecificConfig
            updated.audioSampleRate = header.sampleRate
            updated.audioChannels = header.channels
        } else if (stream.codec == "ac3" || stream.codec == "eac3"),
                  let frame = DolbyAudioHeaderParser.parse(payload, codec: stream.codec) {
            updated.audioSampleRate = frame.sampleRate
            updated.audioChannels = frame.channels
        }
        streamsByPID[pid] = updated
    }

    private func pesPayload(from data: Data) -> Data? {
        guard data.count >= 9, data[0] == 0, data[1] == 0, data[2] == 1 else { return nil }
        let start = 9 + Int(data[8])
        guard start < data.count else { return nil }
        return Data(data[start..<data.endIndex])
    }

    private func tracks() -> [MediaTrack] {
        streamsByPID.values.sorted { $0.trackID < $1.trackID }.map { stream in
            MediaTrack(
                id: "\(stream.trackID)",
                trackId: stream.trackID,
                kind: stream.kind == .video ? .video : .audio,
                codec: stream.codec,
                codecID: "streamType_0x\(String(format: "%02X", stream.streamType))",
                codecPrivateData: stream.codecPrivateData,
                timebase: TimeBase(numerator: 1, denominator: 90_000),
                audioSampleRate: stream.audioSampleRate,
                audioChannels: stream.audioChannels
            )
        }
    }
}
