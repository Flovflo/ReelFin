import CoreMedia
import NativeMediaCore
import XCTest

final class MPEGTransportStreamDemuxerTests: XCTestCase {
    func testParsesPATPMTTracksAndPackets() async throws {
        let data = tsPacket(pid: 0, payloadUnitStart: true, payload: patSection(pmtPID: 0x100))
            + tsPacket(pid: 0x100, payloadUnitStart: true, payload: pmtSection(videoPID: 0x101, audioPID: 0x102))
            + tsPacket(pid: 0x101, payloadUnitStart: true, payload: pes(streamID: 0xE0, pts90k: 90_000, payload: h264AccessUnit()))
            + tsPacket(pid: 0x102, payloadUnitStart: true, payload: pes(streamID: 0xC0, pts90k: 91_024, payload: adtsFrame(payload: [0x21, 0x10])))
        let demuxer = MPEGTransportStreamDemuxer(source: DataBackedTSByteSource(data: data))

        let stream = try await demuxer.open()
        let video = try XCTUnwrap(stream.tracks.first { $0.kind == .video })
        let audio = try XCTUnwrap(stream.tracks.first { $0.kind == .audio })
        guard let first = try await demuxer.readNextPacket() else {
            return XCTFail("Expected a video packet")
        }
        guard let second = try await demuxer.readNextPacket() else {
            return XCTFail("Expected an audio packet")
        }

        XCTAssertEqual(stream.container, .mpegTS)
        XCTAssertEqual(video.codec, "h264")
        XCTAssertNotNil(video.codecPrivateData)
        XCTAssertEqual(audio.codec, "aac")
        XCTAssertEqual(audio.audioSampleRate, 48_000)
        XCTAssertEqual(audio.audioChannels, 2)
        XCTAssertEqual(audio.codecPrivateData, Data([0x11, 0x90]))
        XCTAssertEqual(first.trackID, video.trackId)
        XCTAssertEqual(first.timestamp.pts.seconds, 1, accuracy: 0.0001)
        XCTAssertEqual(second.trackID, audio.trackId)
        XCTAssertEqual(second.data, Data([0x21, 0x10]))
    }

    func testFactoryCreatesTransportStreamDemuxer() async throws {
        let source = DataBackedTSByteSource(data: Data(repeating: 0xFF, count: 188))
        let demuxer = try DemuxerFactory().makeDemuxer(format: .mpegTS, source: source, sourceURL: source.url)

        XCTAssertTrue(String(describing: type(of: demuxer)).contains("MPEGTransportStreamDemuxer"))
    }

    func testParsesEAC3AudioHeaderMetadata() async throws {
        let data = tsPacket(pid: 0, payloadUnitStart: true, payload: patSection(pmtPID: 0x100))
            + tsPacket(pid: 0x100, payloadUnitStart: true, payload: pmtSection(videoPID: 0x101, audioPID: 0x102, audioStreamType: 0x87))
            + tsPacket(pid: 0x102, payloadUnitStart: true, payload: pes(streamID: 0xBD, pts90k: 0, payload: eac3Frame()))
        let demuxer = MPEGTransportStreamDemuxer(source: DataBackedTSByteSource(data: data))

        let stream = try await demuxer.open()
        let audio = try XCTUnwrap(stream.tracks.first { $0.kind == .audio })

        XCTAssertEqual(audio.codec, "eac3")
        XCTAssertEqual(audio.audioSampleRate, 48_000)
        XCTAssertEqual(audio.audioChannels, 6)
    }

    func testSplitsMultipleADTSFramesInOnePES() async throws {
        let data = tsPacket(pid: 0, payloadUnitStart: true, payload: patSection(pmtPID: 0x100))
            + tsPacket(pid: 0x100, payloadUnitStart: true, payload: pmtSection(videoPID: 0x101, audioPID: 0x102))
            + tsPacket(
                pid: 0x102,
                payloadUnitStart: true,
                payload: pes(
                    streamID: 0xC0,
                    pts90k: 180_000,
                    payload: adtsFrame(payload: [0x21, 0x10]) + adtsFrame(payload: [0x22, 0x11])
                )
            )
        let demuxer = MPEGTransportStreamDemuxer(source: DataBackedTSByteSource(data: data))
        _ = try await demuxer.open()

        guard let first = try await demuxer.readNextPacket() else {
            return XCTFail("Expected first AAC packet")
        }
        guard let second = try await demuxer.readNextPacket() else {
            return XCTFail("Expected second AAC packet")
        }

        XCTAssertEqual(first.data, Data([0x21, 0x10]))
        XCTAssertEqual(second.data, Data([0x22, 0x11]))
        XCTAssertEqual(first.timestamp.pts.seconds, 2, accuracy: 0.0001)
        XCTAssertEqual(second.timestamp.pts.seconds, 2 + (1_024.0 / 48_000.0), accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(first.timestamp.duration).seconds, 1_024.0 / 48_000.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(second.timestamp.duration).seconds, 1_024.0 / 48_000.0, accuracy: 0.0001)
    }

    func testBuildsHEVCHVCCFromTransportStreamAnnexBParameterSets() async throws {
        let data = tsPacket(pid: 0, payloadUnitStart: true, payload: patSection(pmtPID: 0x100))
            + tsPacket(pid: 0x100, payloadUnitStart: true, payload: pmtSection(videoPID: 0x101, audioPID: 0x102, videoStreamType: 0x24))
            + tsPacket(pid: 0x101, payloadUnitStart: true, payload: pes(streamID: 0xE0, pts90k: 0, payload: hevcAccessUnit()))
        let demuxer = MPEGTransportStreamDemuxer(source: DataBackedTSByteSource(data: data))

        let stream = try await demuxer.open()
        let video = try XCTUnwrap(stream.tracks.first { $0.kind == .video })
        let privateData = try XCTUnwrap(video.codecPrivateData)
        let config = try VideoCodecPrivateDataParser.parseHEVCDecoderConfigurationRecord(privateData)

        XCTAssertEqual(video.codec, "hevc")
        XCTAssertEqual(config.nalUnitLengthSize, 4)
        XCTAssertEqual(config.vps.count, 1)
        XCTAssertEqual(config.sps.count, 1)
        XCTAssertEqual(config.pps.count, 1)
    }

    func testParsesM2TSPacketsWithBluRayTimestampPrefix() async throws {
        let data = m2tsPacket(pid: 0, payloadUnitStart: true, payload: patSection(pmtPID: 0x100))
            + m2tsPacket(pid: 0x100, payloadUnitStart: true, payload: pmtSection(videoPID: 0x101, audioPID: 0x102))
            + m2tsPacket(pid: 0x101, payloadUnitStart: true, payload: pes(streamID: 0xE0, pts90k: 90_000, payload: h264AccessUnit()))
            + m2tsPacket(pid: 0x102, payloadUnitStart: true, payload: pes(streamID: 0xC0, pts90k: 91_024, payload: adtsFrame(payload: [0x21, 0x10])))
        let demuxer = MPEGTransportStreamDemuxer(source: DataBackedTSByteSource(data: data), format: .m2ts)

        let stream = try await demuxer.open()
        let video = try XCTUnwrap(stream.tracks.first { $0.kind == .video })
        let audio = try XCTUnwrap(stream.tracks.first { $0.kind == .audio })

        XCTAssertEqual(stream.container, .m2ts)
        XCTAssertEqual(video.codec, "h264")
        XCTAssertEqual(audio.codec, "aac")
        XCTAssertNotNil(video.codecPrivateData)
        XCTAssertNotNil(audio.codecPrivateData)
    }

    func testPlannerRoutesTransportStreamH264AACToLocalBackends() {
        let tracks = [
            MediaTrack(id: "1", trackId: 1, kind: .video, codec: "h264", codecID: "streamType_0x1B"),
            MediaTrack(id: "2", trackId: 2, kind: .audio, codec: "aac", codecID: "streamType_0x0F")
        ]
        let stream = DemuxerStreamInfo(container: .mpegTS, tracks: tracks)
        let probe = ProbeResult(format: .mpegTS, confidence: .strong, byteSignature: "47", reason: "sync")

        let plan = NativePlaybackPlanner().makePlan(probe: probe, stream: stream, access: MediaAccessMetrics())

        XCTAssertTrue(plan.canStartLocalPlayback)
        XCTAssertEqual(plan.demux.backend, "MPEGTransportStreamDemuxer(PAT/PMT/PES)")
        XCTAssertEqual(plan.video?.backend, "VideoToolbox")
        XCTAssertEqual(plan.audio?.backend, "AppleAudioToolbox")
        XCTAssertEqual(plan.diagnostics.rendererBackend, "AVSampleBufferDisplayLayer(compressed-ts)")
    }

    func testPlannerRoutesM2TSHEVCEAC3ToLocalBackends() {
        let tracks = [
            MediaTrack(id: "1", trackId: 1, kind: .video, codec: "hevc", codecID: "streamType_0x24", codecPrivateData: Data([1])),
            MediaTrack(id: "2", trackId: 2, kind: .audio, codec: "eac3", codecID: "streamType_0x87", audioSampleRate: 48_000, audioChannels: 6)
        ]
        let stream = DemuxerStreamInfo(container: .m2ts, tracks: tracks)
        let probe = ProbeResult(format: .m2ts, confidence: .strong, byteSignature: "0000000047", reason: "m2ts sync")

        let plan = NativePlaybackPlanner().makePlan(probe: probe, stream: stream, access: MediaAccessMetrics())

        XCTAssertTrue(plan.canStartLocalPlayback)
        XCTAssertEqual(plan.demux.backend, "MPEGTransportStreamDemuxer(PAT/PMT/PES)")
        XCTAssertEqual(plan.video?.backend, "VideoToolbox")
        XCTAssertEqual(plan.audio?.backend, "AppleAudioToolbox")
        XCTAssertEqual(plan.diagnostics.rendererBackend, "AVSampleBufferDisplayLayer(compressed-ts)")
    }

    private func tsPacket(pid: Int, payloadUnitStart: Bool, payload: Data) -> Data {
        precondition(payload.count <= 184)
        if payload.count == 184 {
            return Data([
                0x47,
                UInt8((payloadUnitStart ? 0x40 : 0x00) | ((pid >> 8) & 0x1F)),
                UInt8(pid & 0xFF),
                0x10
            ]) + payload
        }
        let adaptationLength = 183 - payload.count
        var packet = Data([
            0x47,
            UInt8((payloadUnitStart ? 0x40 : 0x00) | ((pid >> 8) & 0x1F)),
            UInt8(pid & 0xFF),
            0x30
        ])
        packet.append(UInt8(adaptationLength))
        if adaptationLength > 0 {
            packet.append(0x00)
            packet.append(Data(repeating: 0xFF, count: adaptationLength - 1))
        }
        packet.append(payload)
        XCTAssertEqual(packet.count, 188)
        return packet
    }

    private func m2tsPacket(pid: Int, payloadUnitStart: Bool, payload: Data) -> Data {
        Data([0, 0, 0, 0]) + tsPacket(pid: pid, payloadUnitStart: payloadUnitStart, payload: payload)
    }

    private func patSection(pmtPID: Int) -> Data {
        Data([0x00, 0x00, 0xB0, 0x0D, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01])
            + Data([UInt8(0xE0 | ((pmtPID >> 8) & 0x1F)), UInt8(pmtPID & 0xFF)])
            + Data([0, 0, 0, 0])
    }

    private func pmtSection(videoPID: Int, audioPID: Int, videoStreamType: UInt8 = 0x1B, audioStreamType: UInt8 = 0x0F) -> Data {
        var data = Data([0x00, 0x02, 0xB0, 0x17, 0x00, 0x01, 0xC1, 0x00, 0x00, 0xE1, 0x01, 0xF0, 0x00])
        data.append(contentsOf: [videoStreamType, UInt8(0xE0 | ((videoPID >> 8) & 0x1F)), UInt8(videoPID & 0xFF), 0xF0, 0x00])
        data.append(contentsOf: [audioStreamType, UInt8(0xE0 | ((audioPID >> 8) & 0x1F)), UInt8(audioPID & 0xFF), 0xF0, 0x00])
        data.append(contentsOf: [0, 0, 0, 0])
        return data
    }

    private func pes(streamID: UInt8, pts90k: Int64, payload: Data) -> Data {
        Data([0x00, 0x00, 0x01, streamID, 0x00, 0x00, 0x80, 0x80, 0x05] + ptsBytes(pts90k)) + payload
    }

    private func ptsBytes(_ pts: Int64) -> [UInt8] {
        [
            UInt8(0x20 | (((pts >> 30) & 0x07) << 1) | 1),
            UInt8((pts >> 22) & 0xFF),
            UInt8((((pts >> 15) & 0x7F) << 1) | 1),
            UInt8((pts >> 7) & 0xFF),
            UInt8(((pts & 0x7F) << 1) | 1)
        ]
    }

    private func h264AccessUnit() -> Data {
        Data([0, 0, 0, 1, 0x67, 0x42, 0x00, 0x1E, 0x95, 0xA8, 0x28])
            + Data([0, 0, 0, 1, 0x68, 0xCE, 0x06, 0xE2])
            + Data([0, 0, 0, 1, 0x65, 0x88])
    }

    private func hevcAccessUnit() -> Data {
        Data([0, 0, 0, 1, 0x40, 0x01, 0x0C, 0x01])
            + Data([0, 0, 0, 1, 0x42, 0x01, 0x01, 0x60])
            + Data([0, 0, 0, 1, 0x44, 0x01, 0xC0])
            + Data([0, 0, 0, 1, 0x26, 0x01, 0x99])
    }

    private func adtsFrame(payload: [UInt8]) -> Data {
        let length = 7 + payload.count
        let profile = 1
        let sampleRateIndex = 3
        let channels = 2
        return Data([
            0xFF, 0xF1,
            UInt8((profile << 6) | (sampleRateIndex << 2) | (channels >> 2)),
            UInt8(((channels & 0x03) << 6) | ((length >> 11) & 0x03)),
            UInt8((length >> 3) & 0xFF),
            UInt8(((length & 0x07) << 5) | 0x1F),
            0xFC
        ] + payload)
    }

    private func eac3Frame() -> Data {
        Data([0x0B, 0x77, 0x00, 0x10, 0x0F, 0x00, 0x00, 0x00])
    }
}

private actor DataBackedTSByteSource: MediaByteSource {
    nonisolated let url = URL(fileURLWithPath: "/tmp/reelfin-test.ts")
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func read(range: ByteRange) async throws -> Data {
        let start = Int(range.offset)
        guard start < data.count else { return Data() }
        let end = min(data.count, start + range.length)
        return Data(data[start..<end])
    }

    func size() async throws -> Int64? { Int64(data.count) }
    func cancel() async {}
    func metrics() async -> MediaAccessMetrics { MediaAccessMetrics() }
}
