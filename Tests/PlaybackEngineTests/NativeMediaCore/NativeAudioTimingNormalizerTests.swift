import CoreMedia
import NativeMediaCore
@testable import ReelFinUI
import XCTest

final class NativeAudioTimingNormalizerTests: XCTestCase {
    func testRewritesDuplicateAudioPTSUsingPacketDuration() throws {
        let first = try makeSample(pts: 21_248)
        let duplicate = try makeSample(pts: 21_248)
        var normalizer = NativeAudioTimingNormalizer()

        let firstResult = try normalizer.normalized(first)
        let secondResult = try normalizer.normalized(duplicate)

        XCTAssertFalse(firstResult.rewrotePresentationTimestamp)
        XCTAssertTrue(secondResult.rewrotePresentationTimestamp)
        XCTAssertEqual(
            CMSampleBufferGetPresentationTimeStamp(secondResult.sampleBuffer).seconds,
            21.280,
            accuracy: 0.000001
        )
    }

    func testKeepsForwardAudioPTSUnchanged() throws {
        let first = try makeSample(pts: 21_248)
        let next = try makeSample(pts: 21_280)
        var normalizer = NativeAudioTimingNormalizer()

        _ = try normalizer.normalized(first)
        let result = try normalizer.normalized(next)

        XCTAssertFalse(result.rewrotePresentationTimestamp)
        XCTAssertEqual(
            CMSampleBufferGetPresentationTimeStamp(result.sampleBuffer).seconds,
            21.280,
            accuracy: 0.000001
        )
    }

    func testRewritesForwardAudioPTSGapsUsingPacketDuration() throws {
        let first = try makeSample(pts: 21_248)
        let gapped = try makeSample(pts: 21_600)
        var normalizer = NativeAudioTimingNormalizer()

        _ = try normalizer.normalized(first)
        let result = try normalizer.normalized(gapped)

        XCTAssertTrue(result.rewrotePresentationTimestamp)
        XCTAssertEqual(result.ptsCorrectionSeconds, 0.320, accuracy: 0.000001)
        XCTAssertEqual(
            CMSampleBufferGetPresentationTimeStamp(result.sampleBuffer).seconds,
            21.280,
            accuracy: 0.000001
        )
    }

    private func makeSample(pts milliseconds: Int64) throws -> CMSampleBuffer {
        let track = MediaTrack(
            id: "2",
            trackId: 2,
            kind: .audio,
            codec: "eac3",
            audioSampleRate: 48_000,
            audioChannels: 6
        )
        let packet = MediaPacket(
            trackID: 2,
            timestamp: PacketTimestamp(
                pts: CMTime(value: milliseconds, timescale: 1000),
                duration: CMTime(value: 1536, timescale: 48_000)
            ),
            isKeyframe: true,
            data: Data([0x0B, 0x77, 0x00, 0x00])
        )
        return try CompressedAudioSampleBuilder(track: track).makeSampleBuffer(packet: packet)
    }
}
