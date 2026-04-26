import CoreMedia
import NativeMediaCore
import XCTest

final class VideoCodecPrivateDataParserTests: XCTestCase {
    func testCreatesH264FormatDescriptionFromAVCC() async throws {
        let track = MediaTrack(
            id: "1",
            trackId: 1,
            kind: .video,
            codec: "h264",
            codecID: "V_MPEG4/ISO/AVC",
            codecPrivateData: Self.avcC
        )
        let decoder = VideoToolboxDecoder()

        try await decoder.configure(track: track)
        let diagnostics = await decoder.diagnostics()

        XCTAssertEqual(diagnostics.codec, "h264")
        XCTAssertTrue(diagnostics.hardwareDecodeActive)
    }

    func testVideoToolboxDecoderWrapsMatroskaAVCPacketAsSampleBuffer() async throws {
        let track = MediaTrack(
            id: "1",
            trackId: 1,
            kind: .video,
            codec: "h264",
            codecID: "V_MPEG4/ISO/AVC",
            codecPrivateData: Self.avcC
        )
        let packet = MediaPacket(
            trackID: 1,
            timestamp: PacketTimestamp(
                pts: CMTime(value: 12, timescale: 24),
                dts: CMTime(value: 10, timescale: 24),
                duration: CMTime(value: 1, timescale: 24)
            ),
            isKeyframe: true,
            data: Data([0x00, 0x00, 0x00, 0x02, 0x65, 0x88])
        )
        let decoder = VideoToolboxDecoder()

        try await decoder.configure(track: track)
        let frame = try await decoder.decode(packet: packet)
        let unwrappedFrame = try XCTUnwrap(frame)
        let sampleBuffer = try XCTUnwrap(unwrappedFrame.sampleBuffer)

        XCTAssertEqual(unwrappedFrame.presentationTime.seconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds, 0.5, accuracy: 0.0001)
    }

    func testConvertsAnnexBPacketToAVCCLengthPrefixedNALUnits() throws {
        let annexB = Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x00, 0x00, 0x01, 0x41, 0x9A])

        let converted = try VideoPacketNormalizer.normalizeLengthPrefixedNALUnits(annexB, nalUnitLengthSize: 4)

        XCTAssertEqual(converted, Data([0x00, 0x00, 0x00, 0x02, 0x65, 0x88, 0x00, 0x00, 0x00, 0x02, 0x41, 0x9A]))
    }

    func testSampleBuilderAcceptsAnnexBMatroskaAVCPacket() throws {
        let track = MediaTrack(
            id: "1",
            trackId: 1,
            kind: .video,
            codec: "h264",
            codecID: "V_MPEG4/ISO/AVC",
            codecPrivateData: Self.avcC
        )
        let packet = MediaPacket(
            trackID: 1,
            timestamp: PacketTimestamp(pts: CMTime(value: 1, timescale: 24)),
            isKeyframe: true,
            data: Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88])
        )

        let sample = try CompressedVideoSampleBuilder(track: track).makeSampleBuffer(packet: packet)

        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample).seconds, 1.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(CMSampleBufferGetFormatDescription(sample)!), kCMVideoCodecType_H264)
    }

    func testVideoToolboxDecoderNormalizesAnnexBMatroskaAVCPacket() async throws {
        let track = MediaTrack(
            id: "1",
            trackId: 1,
            kind: .video,
            codec: "h264",
            codecID: "V_MPEG4/ISO/AVC",
            codecPrivateData: Self.avcC
        )
        let packet = MediaPacket(
            trackID: 1,
            timestamp: PacketTimestamp(pts: CMTime(value: 2, timescale: 24)),
            isKeyframe: true,
            data: Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88])
        )
        let decoder = VideoToolboxDecoder()

        try await decoder.configure(track: track)
        let frame = try await decoder.decode(packet: packet)
        let sample = try XCTUnwrap(frame?.sampleBuffer)

        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample).seconds, 2.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(CMSampleBufferGetFormatDescription(sample)!), kCMVideoCodecType_H264)
    }

    func testVideoToolboxDecoderPropagatesTrackHDRMetadata() async throws {
        let metadata = HDRMetadata(
            format: .hdr10,
            colorPrimaries: .bt2020,
            transferFunction: .pq,
            matrixCoefficients: .bt2020NonConstant,
            bitDepth: 10
        )
        let track = MediaTrack(
            id: "1",
            trackId: 1,
            kind: .video,
            codec: "h264",
            codecID: "V_MPEG4/ISO/AVC",
            codecPrivateData: Self.avcC,
            hdrMetadata: metadata
        )
        let packet = MediaPacket(
            trackID: 1,
            timestamp: PacketTimestamp(pts: CMTime(value: 2, timescale: 24)),
            isKeyframe: true,
            data: Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88])
        )
        let decoder = VideoToolboxDecoder()

        try await decoder.configure(track: track)
        let frame = try await decoder.decode(packet: packet)

        XCTAssertEqual(frame?.hdrMetadata, metadata)
    }

    func testParsesHEVCHVCCParameterSets() throws {
        let config = try VideoCodecPrivateDataParser.parseHEVCDecoderConfigurationRecord(Self.hvcC)

        XCTAssertEqual(config.nalUnitLengthSize, 4)
        XCTAssertEqual(config.vps.count, 1)
        XCTAssertEqual(config.sps.count, 1)
        XCTAssertEqual(config.pps.count, 1)
    }

    func testParsesMatroskaAVCCodecPrivateAsAVCC() throws {
        let config = try VideoCodecPrivateDataParser.parseAVCDecoderConfigurationRecord(Self.avcC)

        XCTAssertEqual(config.nalUnitLengthSize, 4)
        XCTAssertEqual(config.sps.count, 1)
        XCTAssertEqual(config.pps.count, 1)
    }

    private static let avcC = Data([
        0x01, 0x42, 0xE0, 0x1E, 0xFF, 0xE1,
        0x00, 0x1D,
        0x67, 0x42, 0xE0, 0x1E, 0xDA, 0x02, 0x80, 0xB7,
        0xFE, 0x5C, 0x05, 0xA8, 0x30, 0x30, 0x32, 0x00,
        0x00, 0x03, 0x00, 0x02, 0x00, 0x00, 0x03, 0x00,
        0x79, 0x1E, 0x2C, 0x5C, 0x90,
        0x01, 0x00, 0x04,
        0x68, 0xCE, 0x06, 0xE2
    ])

    private static let hvcC = Data([
        0x01, 0x01, 0x60, 0x00, 0x00, 0x00, 0x90, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x5D, 0xF0, 0x00, 0xFC,
        0xFD, 0xF8, 0xF8, 0x00, 0x00, 0x0F, 0x03,
        0xA0, 0x00, 0x01, 0x00, 0x02, 0x40, 0x01,
        0xA1, 0x00, 0x01, 0x00, 0x02, 0x42, 0x01,
        0xA2, 0x00, 0x01, 0x00, 0x02, 0x44, 0x01
    ])
}
