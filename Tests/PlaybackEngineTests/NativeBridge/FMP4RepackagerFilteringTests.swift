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
        let initSegment = try await repackager.generateInitSegment(streamInfo: streamInfo)

        let sourceAVCC = try XCTUnwrap(videoTrack.codecPrivate)
        let avcCTypeOffset = try XCTUnwrap(initSegment.range(of: Data("avcC".utf8)))
            .lowerBound
        let avcCPayloadOffset = avcCTypeOffset + 4
        var expectedAVCC = sourceAVCC
        expectedAVCC[4] = (expectedAVCC[4] & 0xFC) | 0x03
        XCTAssertEqual(
            Data(initSegment[avcCPayloadOffset..<(avcCPayloadOffset + sourceAVCC.count)]),
            expectedAVCC,
            "Init avcC must advertise the four-byte NAL lengths written into fragments without changing SPS/PPS."
        )
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

    func testValidAVCCProvidesExplicitTwoByteNALLengthFormat() async throws {
        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEG4/ISO/AVC",
            codecName: "h264",
            isDefault: true,
            width: 64,
            height: 64,
            bitDepth: 8,
            codecPrivate: Data([
                0x01, 0x42, 0x00, 0x1F, 0xFD, 0xE1, 0x00, 0x04,
                0x67, 0x42, 0x00, 0x1F, 0x01, 0x00, 0x02, 0x68, 0xCE
            ])
        )
        let plan = makeAVCPlan(videoTrack: videoTrack)
        let streamInfo = StreamInfo(
            durationNanoseconds: 1_000_000_000,
            tracks: [videoTrack],
            hasChapters: false,
            seekable: true
        )
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .hdr10OnlyFallback
        )
        let repackager: any Repackager = FMP4Repackager(plan: plan)
        await repackager.setPackagingDecision(decision)
        let initSegment = try await repackager.generateInitSegment(streamInfo: streamInfo)

        let sourceAVCC = try XCTUnwrap(videoTrack.codecPrivate)
        let avcCTypeOffset = try XCTUnwrap(initSegment.range(of: Data("avcC".utf8)))
            .lowerBound
        let avcCPayloadOffset = avcCTypeOffset + 4
        var expectedAVCC = sourceAVCC
        expectedAVCC[4] = (expectedAVCC[4] & 0xFC) | 0x03
        XCTAssertEqual(
            Data(initSegment[avcCPayloadOffset..<(avcCPayloadOffset + sourceAVCC.count)]),
            expectedAVCC,
            "Init avcC must match the four-byte NAL prefixes emitted in mdat."
        )

        let twoByteLengthPrefixed = Data([0x00, 0x03, 0x65, 0xAA, 0xBB])
        let fragment = try await repackager.generateFragment(samples: [
            Sample(
                trackID: videoTrack.id,
                pts: .zero,
                duration: CMTime(value: 1, timescale: 30),
                isKeyframe: true,
                data: twoByteLengthPrefixed
            )
        ])
        let boxes = try BMFFSanityParser.parseTopLevel(fragment)
        let mdat = try XCTUnwrap(boxes.first(where: { $0.type == "mdat" }))
        let payload = Data(fragment[(mdat.startOffset + 8)..<(mdat.startOffset + mdat.size)])

        XCTAssertEqual(payload, Data([0x00, 0x00, 0x00, 0x03, 0x65, 0xAA, 0xBB]))
    }

    func testSelectedSecondVideoTrackDrivesDecisionInitAndFragmentFormat() async throws {
        let unselectedHEVC = TrackInfo(
            id: 10,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 1920,
            height: 1080,
            bitDepth: 10,
            codecPrivate: makeCompleteHVCC(lengthSizeMinusOne: 3)
        )
        let selectedAVCC = Data([
            0x01, 0x42, 0x00, 0x1F, 0xFD, 0xE1, 0x00, 0x04,
            0x67, 0x42, 0x00, 0x1F, 0x01, 0x00, 0x02, 0x68, 0xCE
        ])
        let selectedAVC = TrackInfo(
            id: 20,
            trackType: .video,
            codecID: "V_MPEG4/ISO/AVC",
            codecName: "h264",
            isDefault: false,
            width: 640,
            height: 360,
            bitDepth: 8,
            codecPrivate: selectedAVCC
        )
        let plan = makeAVCPlan(videoTrack: selectedAVC)
        let streamInfo = StreamInfo(
            durationNanoseconds: 1_000_000_000,
            tracks: [unselectedHEVC, selectedAVC],
            hasChapters: false,
            seekable: true
        )
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .dvProfile81Compatible
        )
        XCTAssertEqual(decision.videoEntry.sampleEntryType, "avc1")
        XCTAssertEqual(decision.hlsSignaling.codecs, "avc1.640028")

        let repackager: any Repackager = FMP4Repackager(plan: plan)
        await repackager.setPackagingDecision(decision)
        let initSegment = try await repackager.generateInitSegment(streamInfo: streamInfo)
        XCTAssertEqual(InitSegmentInspector.inspect(initSegment).videoSampleEntry, "avc1")
        XCTAssertNotNil(initSegment.range(of: Data("avcC".utf8)))
        XCTAssertNil(initSegment.range(of: Data("hvcC".utf8)))

        let twoByteLengthPrefixed = Data([0x00, 0x03, 0x65, 0xAA, 0xBB])
        let fragment = try await repackager.generateFragment(samples: [
            Sample(
                trackID: selectedAVC.id,
                pts: .zero,
                duration: CMTime(value: 1, timescale: 30),
                isKeyframe: true,
                data: twoByteLengthPrefixed
            )
        ])
        let boxes = try BMFFSanityParser.parseTopLevel(fragment)
        let mdat = try XCTUnwrap(boxes.first(where: { $0.type == "mdat" }))
        let payload = Data(fragment[(mdat.startOffset + 8)..<(mdat.startOffset + mdat.size)])
        XCTAssertEqual(payload, Data([0x00, 0x00, 0x00, 0x03, 0x65, 0xAA, 0xBB]))
    }

    func testPlannedVideoTrackFallbackDrivesInitAndFragmentWhenMissingFromStreamInfo() async throws {
        let selectedAVCC = Data([
            0x01, 0x42, 0x00, 0x1F, 0xFD, 0xE1, 0x00, 0x04,
            0x67, 0x42, 0x00, 0x1F, 0x01, 0x00, 0x02, 0x68, 0xCE
        ])
        let selectedAVC = TrackInfo(
            id: 20,
            trackType: .video,
            codecID: "V_MPEG4/ISO/AVC",
            codecName: "h264",
            isDefault: false,
            width: 640,
            height: 360,
            bitDepth: 8,
            codecPrivate: selectedAVCC
        )
        let unselectedHEVC = TrackInfo(
            id: 10,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 1920,
            height: 1080,
            bitDepth: 10,
            codecPrivate: makeCompleteHVCC(lengthSizeMinusOne: 3)
        )
        let plan = makeAVCPlan(videoTrack: selectedAVC)
        let streamInfo = StreamInfo(
            durationNanoseconds: 1_000_000_000,
            tracks: [unselectedHEVC],
            hasChapters: false,
            seekable: true
        )
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .dvProfile81Compatible
        )
        XCTAssertEqual(decision.videoEntry.sampleEntryType, "avc1")

        let repackager: any Repackager = FMP4Repackager(plan: plan)
        await repackager.setPackagingDecision(decision)
        let initSegment = try await repackager.generateInitSegment(streamInfo: streamInfo)
        XCTAssertEqual(InitSegmentInspector.inspect(initSegment).videoSampleEntry, "avc1")
        XCTAssertNotNil(initSegment.range(of: Data("avcC".utf8)))
        XCTAssertNil(initSegment.range(of: Data("hvcC".utf8)))

        let fragment = try await repackager.generateFragment(samples: [
            Sample(
                trackID: selectedAVC.id,
                pts: .zero,
                duration: CMTime(value: 1, timescale: 30),
                isKeyframe: true,
                data: Data([0x00, 0x03, 0x65, 0xAA, 0xBB])
            )
        ])
        let boxes = try BMFFSanityParser.parseTopLevel(fragment)
        let mdat = try XCTUnwrap(boxes.first(where: { $0.type == "mdat" }))
        let payload = Data(fragment[(mdat.startOffset + 8)..<(mdat.startOffset + mdat.size)])
        XCTAssertEqual(payload, Data([0x00, 0x00, 0x00, 0x03, 0x65, 0xAA, 0xBB]))
    }

    func testAVCCWithForbiddenParameterSetHeaderDoesNotSuppressAnnexBDetection() async throws {
        let videoTrack = TrackInfo(
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
                0xE7, 0x42, 0x00, 0x1F, 0x01, 0x00, 0x02, 0x68, 0xCE
            ])
        )
        let plan = makeAVCPlan(videoTrack: videoTrack)
        let streamInfo = StreamInfo(
            durationNanoseconds: 1_000_000_000,
            tracks: [videoTrack],
            hasChapters: false,
            seekable: true
        )
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .hdr10OnlyFallback
        )
        let repackager: any Repackager = FMP4Repackager(plan: plan)
        await repackager.setPackagingDecision(decision)
        _ = try await repackager.generateInitSegment(streamInfo: streamInfo)

        let annexB = Data([0x00, 0x00, 0x00, 0x01, 0x65, 0xAA, 0xBB])
        let fragment = try await repackager.generateFragment(samples: [
            Sample(
                trackID: videoTrack.id,
                pts: .zero,
                duration: CMTime(value: 1, timescale: 30),
                isKeyframe: true,
                data: annexB
            )
        ])
        let boxes = try BMFFSanityParser.parseTopLevel(fragment)
        let mdat = try XCTUnwrap(boxes.first(where: { $0.type == "mdat" }))
        let payload = Data(fragment[(mdat.startOffset + 8)..<(mdat.startOffset + mdat.size)])

        XCTAssertEqual(payload, Data([0x00, 0x00, 0x00, 0x03, 0x65, 0xAA, 0xBB]))
    }

    func testDefaultModePreservesHEV1AndReprefixesSourceNALUnitsByteExactly() async throws {
        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "hev1",
            codecName: "hev1",
            isDefault: true,
            width: 64,
            height: 64,
            bitDepth: 10,
            codecPrivate: Data([
                0x01, 0x22, 0x20, 0x00, 0x00, 0x00, 0x90, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x99, 0xF0, 0x00, 0xFC,
                0xFD, 0xFA, 0xFA, 0x00, 0x00, 0x0D, 0x01,
                0xA0, 0x00, 0x01, 0x00, 0x02, 0x40, 0x01
            ])
        )
        let plan = makeHEVCPlan(videoTrack: videoTrack)
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
        XCTAssertEqual(decision.videoEntry.sampleEntryType, "hev1")
        XCTAssertEqual(InitSegmentInspector.inspect(initSegment).videoSampleEntry, "hev1")
        XCTAssertNotNil(initSegment.range(of: Data("hvcC".utf8)))
        XCTAssertNil(initSegment.range(of: Data("avcC".utf8)))

        let twoByteLengthPrefixedNALs = Data([
            0x00, 0x02, 0x26, 0x01,
            0x00, 0x03, 0x02, 0x01, 0xAA
        ])
        let fragment = try await repackager.generateFragment(samples: [
            Sample(
                trackID: videoTrack.id,
                pts: .zero,
                duration: CMTime(value: 1, timescale: 30),
                isKeyframe: true,
                data: twoByteLengthPrefixedNALs
            )
        ])
        let boxes = try BMFFSanityParser.parseTopLevel(fragment)
        let mdat = try XCTUnwrap(boxes.first(where: { $0.type == "mdat" }))
        let payload = Data(fragment[(mdat.startOffset + 8)..<(mdat.startOffset + mdat.size)])

        XCTAssertEqual(payload, Data([
            0x00, 0x00, 0x00, 0x02, 0x26, 0x01,
            0x00, 0x00, 0x00, 0x03, 0x02, 0x01, 0xAA
        ]))
    }

    func testConfiguredFourByteHEVCLengthPrefixThatLooksLikeAnnexBIsPreservedExactly() async throws {
        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 64,
            height: 64,
            bitDepth: 10,
            codecPrivate: makeCompleteHVCC(lengthSizeMinusOne: 3)
        )
        let plan = makeHEVCPlan(videoTrack: videoTrack)
        let streamInfo = StreamInfo(
            durationNanoseconds: 1_000_000_000,
            tracks: [videoTrack],
            hasChapters: false,
            seekable: true
        )
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .hdr10OnlyFallback
        )
        let repackager: any Repackager = FMP4Repackager(plan: plan)
        await repackager.setPackagingDecision(decision)
        _ = try await repackager.generateInitSegment(streamInfo: streamInfo)

        let nalLength = 0x0101
        var nalPayload = Data([0x26, 0x01])
        nalPayload.append(Data(repeating: 0x55, count: nalLength - nalPayload.count))
        var sourceBytes = Data([0x00, 0x00, 0x01, 0x01])
        sourceBytes.append(nalPayload)

        let fragment = try await repackager.generateFragment(samples: [
            Sample(
                trackID: videoTrack.id,
                pts: .zero,
                duration: CMTime(value: 1, timescale: 30),
                isKeyframe: true,
                data: sourceBytes
            )
        ])
        let boxes = try BMFFSanityParser.parseTopLevel(fragment)
        let mdat = try XCTUnwrap(boxes.first(where: { $0.type == "mdat" }))
        let payload = Data(fragment[(mdat.startOffset + 8)..<(mdat.startOffset + mdat.size)])

        XCTAssertEqual(payload, sourceBytes)
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

    private func makeHEVCPlan(videoTrack: TrackInfo) -> NativeBridgePlan {
        NativeBridgePlan(
            itemID: "item-hev1",
            sourceID: "source-hev1",
            sourceURL: URL(string: "https://example.com/video.mp4")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "SDR",
            whyChosen: "hev1-source-entry-test"
        )
    }

    private func makeCompleteHVCC(lengthSizeMinusOne: UInt8) -> Data {
        Data([
            0x01, 0x22, 0x20, 0x00, 0x00, 0x00, 0x90, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x99, 0xF0, 0x00, 0xFC,
            0xFD, 0xFA, 0xFA, 0x00, 0x00, 0x0C | (lengthSizeMinusOne & 0x03), 0x03,
            0xA0, 0x00, 0x01, 0x00, 0x02, 0x40, 0x01,
            0xA1, 0x00, 0x01, 0x00, 0x02, 0x42, 0x01,
            0xA2, 0x00, 0x01, 0x00, 0x02, 0x44, 0x01
        ])
    }
}
