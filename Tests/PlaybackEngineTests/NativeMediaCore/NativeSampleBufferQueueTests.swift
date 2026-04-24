@testable import ReelFinUI
import CoreMedia
import NativeMediaCore
import XCTest

final class NativeSampleBufferQueueTests: XCTestCase {
    func testQueuePreservesFIFOOrderAndTracksBufferedDuration() throws {
        let queue = NativeSampleBufferQueue(capacity: 2)
        let first = try makeAudioSample(pts: 0)
        let second = try makeAudioSample(pts: 32)

        XCTAssertTrue(queue.push(first))
        XCTAssertTrue(queue.push(second))
        XCTAssertFalse(queue.push(try makeAudioSample(pts: 64)))

        var snapshot = queue.snapshot()
        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot.durationSeconds, 0.064, accuracy: 0.001)

        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(queue.pop()!), CMTime(value: 0, timescale: 1000))
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(queue.pop()!), CMTime(value: 32, timescale: 1000))
        XCTAssertNil(queue.pop())

        snapshot = queue.snapshot()
        XCTAssertEqual(snapshot.count, 0)
        XCTAssertEqual(snapshot.durationSeconds, 0, accuracy: 0.001)
    }

    private func makeAudioSample(pts milliseconds: Int64) throws -> CMSampleBuffer {
        let track = MediaTrack(
            id: "2",
            trackId: 2,
            kind: .audio,
            codec: "ac3",
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
