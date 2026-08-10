@testable import PlaybackEngine
import CoreMedia
import XCTest

final class FMP4RepackagerFilteringTests: XCTestCase {
    func testAVCFallbackWritesAvcCWithoutHEVCOrDolbyVisionConfiguration() async throws {
        let videoTrack = makeAVCTrack()
        let plan = makeAVCPlan(videoTrack: videoTrack)
        let streamInfo = StreamInfo(
            durationNanoseconds: 20_000_000_000,
            tracks: [videoTrack],
            hasChapters: false,
            seekable: true
        )
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .dvProfile81Compatible
        )
        let repackager: any Repackager = FMP4Repackager(plan: plan)
        await repackager.setPackagingDecision(decision)

        let initSegment = try await repackager.generateInitSegment(streamInfo: streamInfo)
        let inspection = InitSegmentInspector.inspect(initSegment)

        XCTAssertEqual(inspection.videoSampleEntry, "avc1")
        XCTAssertNotNil(initSegment.range(of: Data("avcC".utf8)))
        XCTAssertNil(initSegment.range(of: Data("hvcC".utf8)))
        XCTAssertNil(initSegment.range(of: Data("dvcC".utf8)))
    }

    func testAVCFallbackPreservesLengthPrefixedNALBytesExactly() async throws {
        let videoTrack = makeAVCTrack()
        let plan = makeAVCPlan(videoTrack: videoTrack)
        let streamInfo = StreamInfo(
            durationNanoseconds: 20_000_000_000,
            tracks: [videoTrack],
            hasChapters: false,
            seekable: true
        )
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .dvProfile81Compatible
        )
        let repackager: any Repackager = FMP4Repackager(plan: plan)
        await repackager.setPackagingDecision(decision)
        _ = try await repackager.generateInitSegment(streamInfo: streamInfo)
        let avcBytes = Data([
            0x00, 0x00, 0x00, 0x02, 0x7C, 0xAA,
            0x00, 0x00, 0x00, 0x02, 0x65, 0xBB
        ])

        let fragment = try await repackager.generateFragment(samples: [
            Sample(
                trackID: videoTrack.id,
                pts: .zero,
                duration: CMTime(value: 1, timescale: 30),
                isKeyframe: true,
                data: avcBytes
            )
        ])
        let boxes = try BMFFSanityParser.parseTopLevel(fragment)
        let mdat = try XCTUnwrap(boxes.first(where: { $0.type == "mdat" }))
        let payload = Data(fragment[(mdat.startOffset + 8)..<(mdat.startOffset + mdat.size)])

        XCTAssertEqual(payload, avcBytes)
    }

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

    private func makeAVCTrack() -> TrackInfo {
        TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEG4/ISO/AVC",
            codecName: "h264",
            isDefault: true,
            width: 64,
            height: 64,
            bitDepth: 8,
            codecPrivate: Data([
                0x01, 0x42, 0x00, 0x1F, 0xFF, 0xE1, 0x00, 0x04,
                0x67, 0x42, 0x00, 0x1F, 0x01, 0x00, 0x02, 0x68, 0xCE
            ])
        )
    }

    private func makeAVCPlan(videoTrack: TrackInfo) -> NativeBridgePlan {
        NativeBridgePlan(
            itemID: "item-avc",
            sourceID: "source-avc",
            sourceURL: URL(string: "https://example.com/video.mp4")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "SDR",
            whyChosen: "avc-fallback-test"
        )
    }
}
