import CoreMedia
import NativeMediaCore
import XCTest

final class MatroskaParserTests: XCTestCase {
    func testParsesBasicTrackMetadata() throws {
        let data = mkv([
            element([0x15, 0x49, 0xA9, 0x66], payload: element([0x2A, 0xD7, 0xB1], payload: [0x0F, 0x42, 0x40])),
            element([0x16, 0x54, 0xAE, 0x6B], payload: element([0xAE], payload:
                element([0xD7], payload: [0x01]) +
                element([0x83], payload: [0x01]) +
                element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8)) +
                element([0x22, 0xB5, 0x9C], payload: Array("eng".utf8)) +
                element([0x53, 0x6E], payload: Array("Main".utf8)) +
                element([0xE0], payload:
                    element([0xB0], payload: [0x07, 0x80]) +
                    element([0xBA], payload: [0x04, 0x38])
                )
            ))
        ])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.tracks.count, 1)
        XCTAssertEqual(segment.tracks[0].codec, "h264")
        XCTAssertEqual(segment.tracks[0].language, "eng")
        XCTAssertEqual(segment.tracks[0].video?.width, 1920)
        XCTAssertEqual(segment.tracks[0].video?.height, 1080)
    }

    func testParsesSimpleBlockPacket() throws {
        let simpleBlock = element([0xA3], payload: [0x81, 0x00, 0x00, 0x80, 0x01, 0x02])
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 1)
        XCTAssertEqual(segment.packets[0].trackID, 1)
        XCTAssertTrue(segment.packets[0].isKeyframe)
        XCTAssertEqual(segment.packets[0].data, Data([0x01, 0x02]))
    }

    func testMapsSimpleBlockTimestampWithClusterTimecode() throws {
        let simpleBlock = element([0xA3], payload: [0x81, 0x00, 0x0A, 0x80, 0xAA])
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x05]) + simpleBlock)
        let data = mkv([cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 1)
        XCTAssertEqual(segment.packets[0].timestamp.pts.seconds, 0.015, accuracy: 0.0001)
    }

    func testExtractsXiphLacedSimpleBlockPackets() throws {
        let simpleBlock = element(
            [0xA3],
            payload: [0x81, 0x00, 0x00, 0x82, 0x01, 0x02, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
        )
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 2)
        XCTAssertEqual(segment.packets[0].data, Data([0xAA, 0xBB]))
        XCTAssertEqual(segment.packets[1].data, Data([0xCC, 0xDD, 0xEE]))
    }

    func testExtractsFixedSizeLacedSimpleBlockPackets() throws {
        let simpleBlock = element(
            [0xA3],
            payload: [0x81, 0x00, 0x00, 0x84, 0x01, 0x01, 0x02, 0x03, 0x04]
        )
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 2)
        XCTAssertEqual(segment.packets[0].data, Data([0x01, 0x02]))
        XCTAssertEqual(segment.packets[1].data, Data([0x03, 0x04]))
    }

    func testLacedPacketsAdvancePTSUsingTrackDefaultDuration() throws {
        let track = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x02]) +
            element([0x86], payload: Array("A_AAC".utf8)) +
            element([0x23, 0xE3, 0x83], payload: [0x01, 0x45, 0x85, 0x55])
        )
        let simpleBlock = element(
            [0xA3],
            payload: [0x81, 0x00, 0x00, 0x84, 0x01, 0x11, 0x22, 0x33, 0x44]
        )
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([element([0x16, 0x54, 0xAE, 0x6B], payload: track), cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 2)
        XCTAssertEqual(segment.packets[0].timestamp.pts.seconds, 0, accuracy: 0.000001)
        XCTAssertEqual(segment.packets[1].timestamp.pts.seconds, 0.021333333, accuracy: 0.000001)
        XCTAssertEqual(segment.packets[0].timestamp.duration?.seconds ?? 0, 0.021333333, accuracy: 0.000001)
        XCTAssertEqual(segment.packets[1].timestamp.duration?.seconds ?? 0, 0.021333333, accuracy: 0.000001)
    }

    func testLacedEAC3PacketsAdvancePTSUsingSynthesizedAudioDuration() throws {
        let track = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x02]) +
            element([0x86], payload: Array("A_EAC3".utf8)) +
            element([0xE1], payload:
                element([0xB5], payload: doublePayload(48_000)) +
                element([0x9F], payload: [0x06])
            )
        )
        let simpleBlock = element(
            [0xA3],
            payload: [0x81, 0x00, 0x00, 0x84, 0x01, 0x11, 0x22, 0x33, 0x44]
        )
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([element([0x16, 0x54, 0xAE, 0x6B], payload: track), cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 2)
        XCTAssertEqual(segment.packets[0].timestamp.pts.seconds, 0, accuracy: 0.000001)
        XCTAssertEqual(segment.packets[1].timestamp.pts.seconds, 0.032, accuracy: 0.000001)
        XCTAssertEqual(segment.packets[0].timestamp.duration?.seconds ?? 0, 0.032, accuracy: 0.000001)
        XCTAssertEqual(segment.packets[1].timestamp.duration?.seconds ?? 0, 0.032, accuracy: 0.000001)
    }

    func testExtractsEBMLLacedSimpleBlockPackets() throws {
        let simpleBlock = element(
            [0xA3],
            payload: [
                0x81, 0x00, 0x00, 0x86,
                0x02,
                0x82,
                0xC0,
                0xAA, 0xBB,
                0xCC, 0xDD, 0xEE,
                0xF0, 0xF1, 0xF2, 0xF3
            ]
        )
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 3)
        XCTAssertEqual(segment.packets[0].data, Data([0xAA, 0xBB]))
        XCTAssertEqual(segment.packets[1].data, Data([0xCC, 0xDD, 0xEE]))
        XCTAssertEqual(segment.packets[2].data, Data([0xF0, 0xF1, 0xF2, 0xF3]))
    }

    func testParsesAudioMetadataAndAppliesDefaultPacketDuration() throws {
        let track = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x02]) +
            element([0x86], payload: Array("A_AAC".utf8)) +
            element([0x23, 0xE3, 0x83], payload: [0x01, 0x45, 0x85, 0x55]) +
            element([0xE1], payload:
                element([0xB5], payload: doublePayload(48_000)) +
                element([0x9F], payload: [0x02]) +
                element([0x62, 0x64], payload: [0x10])
            )
        )
        let simpleBlock = element([0xA3], payload: [0x81, 0x00, 0x00, 0x80, 0x21, 0x10])
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([element([0x16, 0x54, 0xAE, 0x6B], payload: track), cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.tracks[0].codec, "aac")
        XCTAssertEqual(segment.tracks[0].audio?.sampleRate, 48_000)
        XCTAssertEqual(segment.tracks[0].audio?.channels, 2)
        XCTAssertEqual(segment.tracks[0].audio?.bitDepth, 16)
        XCTAssertEqual(segment.packets[0].timestamp.duration?.seconds ?? 0, 0.021333333, accuracy: 0.000001)
    }

    func testParsesBlockGroupDurationForSubtitleTiming() throws {
        let block = element([0xA1], payload: [0x81, 0x00, 0x05, 0x00] + Array("Bonjour".utf8))
        let duration = element([0x9B], payload: [0x28])
        let group = element([0xA0], payload: block + duration)
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + group)
        let data = mkv([cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 1)
        XCTAssertEqual(segment.packets[0].data, Data("Bonjour".utf8))
        XCTAssertEqual(segment.packets[0].timestamp.pts.seconds, 0.005, accuracy: 0.0001)
        XCTAssertEqual(segment.packets[0].timestamp.duration?.seconds ?? 0, 0.04, accuracy: 0.0001)
    }

    func testDemuxerReadsClustersBeyondInitialProbeWindow() async throws {
        let track = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x01]) +
            element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8))
        )
        let firstCluster = cluster(track: 1, payload: [0x01])
        let filler = element([0xEC], payload: Array(repeating: 0, count: 8 * 1024 * 1024))
        let secondCluster = cluster(track: 1, payload: [0x02, 0x03])
        let data = mkv([element([0x16, 0x54, 0xAE, 0x6B], payload: track), firstCluster, filler, secondCluster])
        let source = DataBackedByteSource(data: data)
        let demuxer = MatroskaDemuxer(source: source)

        _ = try await demuxer.open()
        let first = try await demuxer.readNextPacket()
        let second = try await demuxer.readNextPacket()

        XCTAssertEqual(first?.data, Data([0x01]))
        XCTAssertEqual(second?.data, Data([0x02, 0x03]))
        let metrics = await source.metrics()
        XCTAssertGreaterThan(metrics.rangeRequestCount, 1)
    }

    func testDemuxerAppliesSynthesizedAudioDurationToStreamingClusters() async throws {
        let track = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x02]) +
            element([0x86], payload: Array("A_EAC3".utf8)) +
            element([0xE1], payload:
                element([0xB5], payload: doublePayload(48_000)) +
                element([0x9F], payload: [0x06])
            )
        )
        let firstCluster = cluster(track: 1, payload: [0x0B, 0x77])
        let filler = element([0xEC], payload: Array(repeating: 0, count: 8 * 1024 * 1024))
        let lacedBlock = element(
            [0xA3],
            payload: [0x81, 0x00, 0x00, 0x84, 0x01, 0x11, 0x22, 0x33, 0x44]
        )
        let secondCluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x64]) + lacedBlock)
        let data = mkv([element([0x16, 0x54, 0xAE, 0x6B], payload: track), firstCluster, filler, secondCluster])
        let source = DataBackedByteSource(data: data)
        let demuxer = MatroskaDemuxer(source: source)

        _ = try await demuxer.open()
        _ = try await demuxer.readNextPacket()
        let firstLacedPacket = try await demuxer.readNextPacket()
        let secondLacedPacket = try await demuxer.readNextPacket()
        let firstLaced = try XCTUnwrap(firstLacedPacket)
        let secondLaced = try XCTUnwrap(secondLacedPacket)

        XCTAssertEqual(firstLaced.timestamp.pts.seconds, 0.1, accuracy: 0.000001)
        XCTAssertEqual(secondLaced.timestamp.pts.seconds, 0.132, accuracy: 0.000001)
        XCTAssertEqual(secondLaced.timestamp.duration?.seconds ?? 0, 0.032, accuracy: 0.000001)
        let metrics = await source.metrics()
        XCTAssertGreaterThan(metrics.rangeRequestCount, 1)
    }

    func testDemuxerSeekUsesCueClusterPosition() async throws {
        let track = element([0x16, 0x54, 0xAE, 0x6B], payload: element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x01]) +
            element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8))
        ))
        let firstCluster = cluster(track: 1, payload: [0x01])
        let secondCluster = cluster(track: 1, payload: [0x02])
        let placeholderCue = cues(timecode: 10, track: 1, clusterPosition: 0)
        let secondClusterPosition = track.count + placeholderCue.count + firstCluster.count
        let data = mkv([
            track,
            cues(timecode: 10, track: 1, clusterPosition: UInt8(secondClusterPosition)),
            firstCluster,
            secondCluster
        ])
        let demuxer = MatroskaDemuxer(source: DataBackedByteSource(data: data))

        _ = try await demuxer.open()
        try await demuxer.seek(to: CMTime(seconds: 0.010, preferredTimescale: 1000))
        let packet = try await demuxer.readNextPacket()

        XCTAssertEqual(packet?.data, Data([0x02]))
    }

    private func mkv(_ children: [[UInt8]]) -> Data {
        Data(element([0x1A, 0x45, 0xDF, 0xA3], payload: []))
            + Data(element([0x18, 0x53, 0x80, 0x67], payload: children.flatMap { $0 }))
    }

    private func cluster(track: UInt8, payload: [UInt8]) -> [UInt8] {
        let simpleBlock = element([0xA3], payload: [0x80 | track, 0x00, 0x00, 0x80] + payload)
        return element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
    }

    private func cues(timecode: UInt8, track: UInt8, clusterPosition: UInt8) -> [UInt8] {
        let positions = element([0xB7], payload:
            element([0xF7], payload: [track]) +
            element([0xF1], payload: [clusterPosition])
        )
        let point = element([0xBB], payload:
            element([0xB3], payload: [timecode]) +
            positions
        )
        return element([0x1C, 0x53, 0xBB, 0x6B], payload: point)
    }

    private func element(_ id: [UInt8], payload: [UInt8]) -> [UInt8] {
        id + vintSize(payload.count) + payload
    }

    private func vintSize(_ size: Int) -> [UInt8] {
        precondition(size >= 0)
        let value = UInt64(size)
        for length in 1...8 {
            let maxValue = (UInt64(1) << UInt64(7 * length)) - 2
            guard value <= maxValue else { continue }
            var bytes = Array(repeating: UInt8(0), count: length)
            var remaining = value
            for index in stride(from: length - 1, through: 0, by: -1) {
                bytes[index] = UInt8(remaining & 0xFF)
                remaining >>= 8
            }
            bytes[0] |= UInt8(1 << (8 - length))
            return bytes
        }
        preconditionFailure("EBML test size too large")
    }

    private func doublePayload(_ value: Double) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.bigEndian, Array.init)
    }
}

private actor DataBackedByteSource: MediaByteSource {
    nonisolated let url = URL(fileURLWithPath: "/tmp/reelfin-test.mkv")
    private let data: Data
    private var snapshot = MediaAccessMetrics()

    init(data: Data) {
        self.data = data
    }

    func read(range: ByteRange) async throws -> Data {
        guard range.offset >= 0, range.length > 0 else { throw MediaAccessError.invalidRange(range) }
        let start = Int(range.offset)
        guard start < data.count else { return Data() }
        let end = min(data.count, start + range.length)
        snapshot.rangeRequestCount += 1
        snapshot.currentOffset = Int64(end)
        snapshot.bufferedRanges.append(ByteRange(offset: range.offset, length: end - start))
        return Data(data[start..<end])
    }

    func size() async throws -> Int64? {
        Int64(data.count)
    }

    func cancel() async {}

    func metrics() async -> MediaAccessMetrics {
        snapshot
    }
}
