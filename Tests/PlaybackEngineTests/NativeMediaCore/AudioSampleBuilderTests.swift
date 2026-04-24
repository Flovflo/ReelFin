import AudioToolbox
import CoreMedia
import NativeMediaCore
import XCTest

final class AudioSampleBuilderTests: XCTestCase {
    func testBuildsAACSampleBufferFromMatroskaPacket() throws {
        let track = MediaTrack(
            id: "2",
            trackId: 2,
            kind: .audio,
            codec: "aac",
            codecPrivateData: Data([0x12, 0x10]),
            audioSampleRate: 44_100,
            audioChannels: 2
        )
        let packet = MediaPacket(
            trackID: 2,
            timestamp: PacketTimestamp(
                pts: CMTime(value: 42, timescale: 1000),
                duration: CMTime(value: 1024, timescale: 44_100)
            ),
            isKeyframe: true,
            data: Data([0x21, 0x10, 0x04, 0x60])
        )

        let sample = try CompressedAudioSampleBuilder(track: track).makeSampleBuffer(packet: packet)

        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample), packet.timestamp.pts)
        XCTAssertEqual(CMSampleBufferGetDuration(sample), packet.timestamp.duration)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(CMSampleBufferGetFormatDescription(sample)!), kAudioFormatMPEG4AAC)
    }

    func testAppleAudioDecoderReturnsCompressedSampleBuffer() async throws {
        let track = MediaTrack(
            id: "3",
            trackId: 3,
            kind: .audio,
            codec: "ac3",
            audioSampleRate: 48_000,
            audioChannels: 6
        )
        let packet = MediaPacket(
            trackID: 3,
            timestamp: PacketTimestamp(
                pts: .zero,
                duration: CMTime(value: 1536, timescale: 48_000)
            ),
            isKeyframe: true,
            data: Data([0x0B, 0x77, 0x00, 0x00])
        )
        let decoder = AppleAudioDecoder()

        try await decoder.configure(track: track)
        let frame = try await decoder.decode(packet: packet)

        XCTAssertNotNil(frame?.sampleBuffer)
        let diagnostics = await decoder.diagnostics()
        XCTAssertEqual(diagnostics.decoderBackend, "AppleAudioToolbox")
        XCTAssertEqual(diagnostics.sampleRate, 48_000)
        XCTAssertEqual(diagnostics.channels, 6)
    }

    func testBuildsAC3SampleBufferDurationWhenPacketDurationIsMissing() throws {
        let track = MediaTrack(
            id: "3",
            trackId: 3,
            kind: .audio,
            codec: "ac3",
            audioSampleRate: 48_000,
            audioChannels: 6
        )
        let packet = MediaPacket(
            trackID: 3,
            timestamp: PacketTimestamp(pts: .zero),
            isKeyframe: true,
            data: Data([0x0B, 0x77, 0x00, 0x00])
        )

        let sample = try CompressedAudioSampleBuilder(track: track).makeSampleBuffer(packet: packet)

        XCTAssertEqual(CMSampleBufferGetDuration(sample), CMTime(value: 1536, timescale: 48_000))
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(CMSampleBufferGetFormatDescription(sample)!), kAudioFormatAC3)
    }

    func testBuildsMultiFrameEAC3SampleBufferWithContinuousTiming() throws {
        let track = MediaTrack(
            id: "3",
            trackId: 3,
            kind: .audio,
            codec: "eac3",
            audioSampleRate: 48_000,
            audioChannels: 6
        )
        let frame = eac3Frame(frameSize: 8)
        let packet = MediaPacket(
            trackID: 3,
            timestamp: PacketTimestamp(pts: CMTime(value: 10, timescale: 1)),
            isKeyframe: true,
            data: frame + frame
        )

        let sample = try CompressedAudioSampleBuilder(track: track).makeSampleBuffer(packet: packet)

        XCTAssertEqual(CMSampleBufferGetNumSamples(sample), 2)
        XCTAssertEqual(CMSampleBufferGetDuration(sample).seconds, 0.064, accuracy: 0.0001)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(CMSampleBufferGetFormatDescription(sample)!), kAudioFormatEnhancedAC3)
    }

    func testBuildsOpusSampleBufferFromMatroskaPacket() throws {
        let track = MediaTrack(
            id: "4",
            trackId: 4,
            kind: .audio,
            codec: "opus",
            codecPrivateData: opusHead(channels: 2, sampleRate: 48_000)
        )
        let packet = MediaPacket(
            trackID: 4,
            timestamp: PacketTimestamp(
                pts: CMTime(value: 0, timescale: 48_000),
                duration: CMTime(value: 960, timescale: 48_000)
            ),
            isKeyframe: true,
            data: Data([0xF8, 0xFF, 0xFE])
        )

        let sample = try CompressedAudioSampleBuilder(track: track).makeSampleBuffer(packet: packet)

        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(CMSampleBufferGetFormatDescription(sample)!), kAudioFormatOpus)
        XCTAssertEqual(CMSampleBufferGetDuration(sample), packet.timestamp.duration)
    }

    private func opusHead(channels: UInt8, sampleRate: UInt32) -> Data {
        var data = Data("OpusHead".utf8)
        data.append(1)
        data.append(channels)
        data.append(contentsOf: [0x00, 0x00])
        data.append(UInt8(sampleRate & 0xFF))
        data.append(UInt8((sampleRate >> 8) & 0xFF))
        data.append(UInt8((sampleRate >> 16) & 0xFF))
        data.append(UInt8((sampleRate >> 24) & 0xFF))
        data.append(contentsOf: [0x00, 0x00, 0x00])
        return data
    }

    private func eac3Frame(frameSize: Int) -> Data {
        let frameSizeCode = max(0, (frameSize / 2) - 1)
        return Data([
            0x0B, 0x77,
            UInt8((frameSizeCode >> 8) & 0x07),
            UInt8(frameSizeCode & 0xFF),
            0x3F,
            0x00,
            0x00,
            0x00
        ])
    }
}
