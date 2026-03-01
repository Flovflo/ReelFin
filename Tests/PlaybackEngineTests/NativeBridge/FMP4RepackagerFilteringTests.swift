@testable import PlaybackEngine
import XCTest

final class FMP4RepackagerFilteringTests: XCTestCase {
    func testInitSegmentFiltersNonAVTracks() async throws {
        let plan = NativeBridgePlan(
            itemID: "item",
            sourceID: "source",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: TrackInfo(id: 1, trackType: .video, codecID: "V_MPEGH/ISO/HEVC", codecName: "hevc", isDefault: true),
            audioTrack: TrackInfo(id: 2, trackType: .audio, codecID: "A_AAC", codecName: "aac", isDefault: true),
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "HDR10",
            whyChosen: "test"
        )

        let repackager = FMP4Repackager(plan: plan)
        let streamInfo = StreamInfo(
            durationNanoseconds: 12_000_000_000,
            tracks: [
                TrackInfo(id: 1, trackType: .video, codecID: "V_MPEGH/ISO/HEVC", codecName: "hevc", isDefault: true),
                TrackInfo(id: 2, trackType: .audio, codecID: "A_AAC", codecName: "aac", isDefault: true),
                TrackInfo(id: 4, trackType: .subtitle, codecID: "S_TEXT/UTF8", codecName: "s_text", isDefault: false)
            ],
            hasChapters: false,
            seekable: true
        )

        let initSegment = try await repackager.generateInitSegment(streamInfo: streamInfo)
        let boxes = try BMFFSanityParser.parseTopLevel(initSegment)
        guard let moov = boxes.first(where: { $0.type == "moov" }) else {
            XCTFail("Missing moov box")
            return
        }
        let trakCount = moov.children.filter { $0.type == "trak" }.count
        XCTAssertEqual(trakCount, 2)
    }
}
