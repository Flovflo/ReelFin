@testable import PlaybackEngine
import XCTest

final class BMFFValidatorTests: XCTestCase {
    func testValidatesInitAndFragmentFromRepackager() async throws {
        let plan = NativeBridgePlan(
            itemID: "item",
            sourceID: "source",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: TrackInfo(id: 1, trackType: .video, codecID: "V_MPEGH/ISO/HEVC", codecName: "hevc", isDefault: true),
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "HDR10",
            whyChosen: "test"
        )

        let repackager = FMP4Repackager(plan: plan)
        let streamInfo = StreamInfo(
            durationNanoseconds: 120_000_000_000,
            tracks: [TrackInfo(id: 1, trackType: .video, codecID: "V_MPEGH/ISO/HEVC", codecName: "hevc", isDefault: true)],
            hasChapters: false,
            seekable: true
        )

        let initSegment = try await repackager.generateInitSegment(streamInfo: streamInfo)
        let sample = Sample(
            trackID: 1,
            pts: .init(value: 0, timescale: 1_000_000_000),
            duration: .init(value: 41_708_333, timescale: 1_000_000_000),
            isKeyframe: true,
            data: Data([0x00, 0x00, 0x00, 0x01, 0x65, 0x88])
        )
        let fragment = try await repackager.generateFragment(samples: [sample])

        let validator = BMFFValidator()
        XCTAssertNoThrow(try validator.validateInitSegment(initSegment))
        XCTAssertNoThrow(try validator.validateMediaFragment(fragment))
    }

    func testRejectsInvalidPayload() {
        let validator = BMFFValidator()
        XCTAssertThrowsError(try validator.validateInitSegment(Data([0x00, 0x01])))
    }
}
