import NativeMediaCore
import XCTest

final class MP4DemuxerTests: XCTestCase {
    func testFactoryCreatesMP4DemuxerBackend() throws {
        let source = StaticByteSource(data: Data())
        let demuxer = try DemuxerFactory().makeDemuxer(
            format: .mp4,
            source: source,
            sourceURL: URL(string: "https://example.com/video.mp4")!
        )

        XCTAssertTrue(String(describing: type(of: demuxer)).contains("MP4Demuxer"))
    }

    func testMP4DemuxerOpensExtensionlessOriginalStreamURL() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try await MP4PlaybackFixture.makeTinyH264AACMP4(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let demuxer = try MP4Demuxer(url: url, format: .mp4)
        let info = try await demuxer.open()

        XCTAssertTrue(info.tracks.contains { $0.kind == .video && $0.codec == "h264" })
        XCTAssertTrue(info.tracks.contains { $0.kind == .audio && $0.codec == "aac" })
    }

    func testMP4DemuxerExposesVideoCodecPrivateDataForVideoToolbox() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try await MP4PlaybackFixture.makeTinyH264AACMP4(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let demuxer = try MP4Demuxer(url: url, format: .mp4)
        let info = try await demuxer.open()
        let video = try XCTUnwrap(info.tracks.first { $0.kind == .video })
        let privateData = try XCTUnwrap(video.codecPrivateData)
        let avc = try VideoCodecPrivateDataParser.parseAVCDecoderConfigurationRecord(privateData)

        XCTAssertEqual(video.codec, "h264")
        XCTAssertFalse(avc.sps.isEmpty)
        XCTAssertFalse(avc.pps.isEmpty)
    }

    func testMP4DemuxerExtractsSamplesWithTimestamps() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try await MP4PlaybackFixture.makeTinyH264AACMP4(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let demuxer = try MP4Demuxer(url: url, format: .mp4)
        let info = try await demuxer.open()
        let videoTrackID = try XCTUnwrap(info.tracks.first(where: { $0.kind == .video })?.trackId)
        let audioTrackID = try XCTUnwrap(info.tracks.first(where: { $0.kind == .audio })?.trackId)

        var packets: [MediaPacket] = []
        while packets.count < 16, let packet = try await demuxer.readNextPacket() {
            packets.append(packet)
            if packets.contains(where: { $0.trackID == videoTrackID })
                && packets.contains(where: { $0.trackID == audioTrackID }) {
                break
            }
        }

        let videoPacket = try XCTUnwrap(packets.first { $0.trackID == videoTrackID })
        let audioPacket = try XCTUnwrap(packets.first { $0.trackID == audioTrackID })
        XCTAssertFalse(videoPacket.data.isEmpty)
        XCTAssertFalse(audioPacket.data.isEmpty)
        XCTAssertTrue(videoPacket.timestamp.pts.isValid)
        XCTAssertTrue(audioPacket.timestamp.pts.isValid)
    }
}

private actor StaticByteSource: MediaByteSource {
    nonisolated let url = URL(string: "memory://test")!
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func read(range: ByteRange) async throws -> Data {
        let start = Int(range.offset)
        let end = min(data.count, start + range.length)
        guard start < end else { return Data() }
        return Data(data[start..<end])
    }

    func size() async throws -> Int64? { Int64(data.count) }
    func cancel() async {}
    func metrics() async -> MediaAccessMetrics { MediaAccessMetrics() }
}
