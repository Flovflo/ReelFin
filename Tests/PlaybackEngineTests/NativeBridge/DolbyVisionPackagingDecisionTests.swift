@testable import PlaybackEngine
import Foundation
import XCTest

final class DolbyVisionPackagingDecisionTests: XCTestCase {
    func testAVCFallbackPreservesSDRSampleEntryAndCapabilities() {
        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEG4/ISO/AVC",
            codecName: "h264",
            isDefault: true,
            width: 1920,
            height: 1080,
            bitDepth: 8,
            codecPrivate: Self.avcC
        )
        let plan = makePlan(videoTrack: videoTrack, videoRangeType: "SDR")
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: makeStreamInfo(videoTrack: videoTrack),
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .dvProfile81Compatible
        )

        XCTAssertEqual(decision.mode, .hdr10OnlyFallback)
        XCTAssertEqual(decision.videoEntry.sampleEntryType, "avc1")
        XCTAssertFalse(decision.videoEntry.includeHvcC)
        XCTAssertFalse(decision.videoEntry.includeDvcC)
        XCTAssertFalse(decision.videoEntry.stripDolbyVisionRPUNALs)
        XCTAssertNil(decision.hlsSignaling.videoRange)
        XCTAssertEqual(decision.expectation.floor, .sdr)
        XCTAssertEqual(decision.expectation.ceiling, .sdr)
    }

    func testHEVCHDR10FallbackKeepsHvcCAndRPUFilteringContract() {
        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 3840,
            height: 2160,
            bitDepth: 10,
            codecPrivate: makeHVCC()
        )
        let plan = makePlan(videoTrack: videoTrack, videoRangeType: "HDR10")
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: makeStreamInfo(videoTrack: videoTrack),
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .hdr10OnlyFallback
        )

        XCTAssertEqual(decision.videoEntry.sampleEntryType, "hvc1")
        XCTAssertTrue(decision.videoEntry.includeHvcC)
        XCTAssertFalse(decision.videoEntry.includeDvcC)
        XCTAssertTrue(decision.videoEntry.stripDolbyVisionRPUNALs)
        XCTAssertEqual(decision.hlsSignaling.videoRange, "PQ")
        XCTAssertEqual(decision.expectation.floor, .hdr10)
        XCTAssertEqual(decision.expectation.ceiling, .hdr10)
    }

    func testEvaluatePackagingKeepsMain10SDRWithoutVideoRange() {
        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 3840,
            height: 1608,
            bitDepth: 10,
            codecPrivate: makeHVCC(),
            colourPrimaries: nil,
            transferCharacteristic: nil,
            matrixCoefficients: nil
        )

        let plan = NativeBridgePlan(
            itemID: "item-main10-sdr",
            sourceID: "source-main10-sdr",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "SDR",
            dvProfile: nil,
            whyChosen: "test"
        )

        let streamInfo = StreamInfo(
            durationNanoseconds: 120_000_000_000,
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

        XCTAssertEqual(decision.mode, .hdr10OnlyFallback)
        XCTAssertNil(decision.hlsSignaling.videoRange)
        XCTAssertEqual(decision.expectation.floor, .sdr)
        XCTAssertEqual(decision.expectation.ceiling, .sdr)
    }

    func testEvaluatePackagingDerivesFullyQualifiedHVC1CodecFromHVCC() {
        let videoTrack = makeHEVCTrack(codecName: "hevc", codecPrivate: makeHVCC())
        let decision = evaluate(videoTrack: videoTrack, videoRangeType: "SDR")

        XCTAssertEqual(decision.hlsSignaling.codecs, "hvc1.2.4.H153.90")
        XCTAssertEqual(decision.videoEntry.sampleEntryType, "hvc1")
    }

    func testEvaluatePackagingUsesEffectiveHEV1EntryAndAlternateHVCCFields() {
        let alternateHVCC = Data([
            0x01, 0x41, 0x40, 0x00, 0x00, 0x00,
            0xAA, 0xBB, 0x00, 0x00, 0x00, 0x00,
            0x78, 0xF0, 0x00, 0xFC, 0xFD, 0xF8,
            0xF8, 0x00, 0x00, 0x0F, 0x01,
            0xA0, 0x00, 0x01, 0x00, 0x02, 0x40, 0x01
        ])
        let videoTrack = makeHEVCTrack(codecName: "hev1", codecPrivate: alternateHVCC)
        let decision = evaluate(videoTrack: videoTrack, videoRangeType: "SDR")

        XCTAssertEqual(decision.hlsSignaling.codecs, "hev1.A1.2.L120.AA.BB")
        XCTAssertEqual(decision.videoEntry.sampleEntryType, "hev1")
    }

    func testEvaluatePackagingRecognizesAllSupportedHEVCIdentifiers() {
        let expectedEntries = [
            "hevc": "hvc1",
            "h265": "hvc1",
            "hvc1": "hvc1",
            "hev1": "hev1"
        ]

        for (identifier, expectedEntry) in expectedEntries {
            let videoTrack = makeHEVCTrack(
                codecName: identifier,
                codecID: identifier,
                codecPrivate: makeHVCC()
            )
            let decision = evaluate(videoTrack: videoTrack, videoRangeType: "SDR")

            XCTAssertTrue(decision.hlsSignaling.codecs.hasPrefix("\(expectedEntry)."), identifier)
            XCTAssertEqual(decision.videoEntry.sampleEntryType, expectedEntry, identifier)
            XCTAssertTrue(decision.videoEntry.includeHvcC, identifier)
        }
    }

    func testDefaultModeTreatsZeroDVProfileAsNonDVAndPreservesHEV1() {
        let videoTrack = makeHEVCTrack(
            codecName: "hev1",
            codecID: "hev1",
            codecPrivate: makeHVCC()
        )
        let plan = NativeBridgePlan(
            itemID: "item-hev1-zero-dv",
            sourceID: "source-hev1-zero-dv",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "SDR",
            dvProfile: 0,
            whyChosen: "zero-dv-profile-is-not-dv"
        )
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: makeStreamInfo(videoTrack: videoTrack),
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .dvProfile81Compatible
        )

        XCTAssertEqual(decision.videoEntry.sampleEntryType, "hev1")
        XCTAssertTrue(decision.hlsSignaling.codecs.hasPrefix("hev1."))
        XCTAssertFalse(decision.videoEntry.includeDvcC)
    }

    func testEvaluatePackagingSignalsPQOnlyFromExplicitPQTransfer() {
        let videoTrack = makeHEVCTrack(
            codecName: "hevc",
            codecPrivate: makeHVCC(),
            transferCharacteristic: 16
        )
        let decision = evaluate(videoTrack: videoTrack, videoRangeType: "SDR")

        XCTAssertEqual(decision.hlsSignaling.videoRange, "PQ")
        XCTAssertEqual(decision.expectation.floor, .hdr10)
        XCTAssertEqual(decision.expectation.ceiling, .hdr10)
    }

    func testEvaluatePackagingSignalsHLGOnlyFromExplicitHLGTransfer() {
        let videoTrack = makeHEVCTrack(
            codecName: "hevc",
            codecPrivate: makeHVCC(),
            transferCharacteristic: 18
        )
        let decision = evaluate(videoTrack: videoTrack, videoRangeType: "SDR")

        XCTAssertEqual(decision.hlsSignaling.videoRange, "HLG")
        XCTAssertEqual(decision.expectation.floor, .hdr10)
        XCTAssertEqual(decision.expectation.ceiling, .hdr10)
    }

    func testEvaluatePackagingFailsClosedForMalformedOrTruncatedHVCC() {
        let validHVCC = makeHVCC()
        let trailingByteRecord = validHVCC + Data([0x00])
        let wrongVersionRecord = Data([0x02]) + Data(validHVCC.dropFirst())
        let zeroLengthNALRecord = Data(validHVCC.prefix(26)) + Data([0x00, 0x00])
        let oneByteNALRecord = Data(validHVCC.prefix(26)) + Data([0x00, 0x01, 0x40])
        let malformedRecords: [Data] = [
            Data(),
            Data(validHVCC.prefix(13)),
            Data(validHVCC.prefix(22)),
            Data(validHVCC.prefix(23)),
            Data(validHVCC.prefix(24)),
            Data(validHVCC.prefix(26)),
            Data(validHVCC.prefix(28)),
            zeroLengthNALRecord,
            oneByteNALRecord,
            trailingByteRecord,
            wrongVersionRecord
        ]

        for codecPrivate in malformedRecords {
            let videoTrack = makeHEVCTrack(codecName: "hevc", codecPrivate: codecPrivate)
            let decision = evaluate(videoTrack: videoTrack, videoRangeType: "SDR")

            XCTAssertEqual(decision.hlsSignaling.codecs, "")
            XCTAssertFalse(decision.videoEntry.includeHvcC)
            XCTAssertEqual(decision.reason, "unsupported_hevc_configuration")
        }
    }

    func testEvaluatePackagingRejectsSemanticallyInvalidHVCCArraysAndNALHeaders() {
        let validHVCC = makeHVCC()
        var reservedArrayBit = validHVCC
        reservedArrayBit[23] |= 0x40
        var forbiddenZeroBit = validHVCC
        forbiddenZeroBit[28] |= 0x80
        var zeroTemporalID = validHVCC
        zeroTemporalID[29] &= 0xF8
        var mismatchedNALType = validHVCC
        mismatchedNALType[23] = 0xA1

        for codecPrivate in [reservedArrayBit, forbiddenZeroBit, zeroTemporalID, mismatchedNALType] {
            let videoTrack = makeHEVCTrack(codecName: "hevc", codecPrivate: codecPrivate)
            let decision = evaluate(videoTrack: videoTrack, videoRangeType: "SDR")

            XCTAssertEqual(decision.hlsSignaling.codecs, "")
            XCTAssertFalse(decision.videoEntry.includeHvcC)
            XCTAssertEqual(decision.reason, "unsupported_hevc_configuration")
        }
    }

    func testEvaluatePackagingAcceptsSemanticallyValidVPSSPSPPSArrays() {
        let videoTrack = makeHEVCTrack(
            codecName: "hevc",
            codecPrivate: makeHVCCWithVPSSPSPPS()
        )
        let decision = evaluate(videoTrack: videoTrack, videoRangeType: "SDR")

        XCTAssertEqual(decision.hlsSignaling.codecs, "hvc1.2.4.H153.90")
        XCTAssertTrue(decision.videoEntry.includeHvcC)
    }

    func testEvaluatePackagingRejectsInvalidHVCCFixedHeaderReservedBits() {
        let validHVCC = makeHVCCWithVPSSPSPPS()
        var invalidSpatialSegmentationReservedBits = validHVCC
        invalidSpatialSegmentationReservedBits[13] &= 0x0F
        var invalidParallelismReservedBits = validHVCC
        invalidParallelismReservedBits[15] &= 0x3F
        var invalidChromaReservedBits = validHVCC
        invalidChromaReservedBits[16] &= 0x3F
        var invalidLumaDepthReservedBits = validHVCC
        invalidLumaDepthReservedBits[17] &= 0x1F
        var invalidChromaDepthReservedBits = validHVCC
        invalidChromaDepthReservedBits[18] &= 0x1F

        for codecPrivate in [
            invalidSpatialSegmentationReservedBits,
            invalidParallelismReservedBits,
            invalidChromaReservedBits,
            invalidLumaDepthReservedBits,
            invalidChromaDepthReservedBits
        ] {
            let videoTrack = makeHEVCTrack(codecName: "hvc1", codecPrivate: codecPrivate)
            let decision = evaluate(videoTrack: videoTrack, videoRangeType: "SDR")

            XCTAssertEqual(decision.hlsSignaling.codecs, "")
            XCTAssertFalse(decision.videoEntry.includeHvcC)
            XCTAssertEqual(decision.reason, "unsupported_hevc_configuration")
        }
    }

    func testHVC1RequiresCompleteVPSSPSPPSWhileHEV1AllowsInBandParameterSets() {
        let missingRequiredArrays = makeHVCCWithOnlyVPS()
        var incompleteRequiredArrays = makeHVCCWithVPSSPSPPS()
        incompleteRequiredArrays[23] &= 0x7F
        incompleteRequiredArrays[30] &= 0x7F
        incompleteRequiredArrays[37] &= 0x7F

        for codecPrivate in [missingRequiredArrays, incompleteRequiredArrays] {
            let hvc1Track = makeHEVCTrack(
                codecName: "hvc1",
                codecID: "hvc1",
                codecPrivate: codecPrivate
            )
            let hvc1Decision = evaluate(videoTrack: hvc1Track, videoRangeType: "SDR")
            XCTAssertEqual(hvc1Decision.reason, "unsupported_hevc_configuration")
            XCTAssertEqual(hvc1Decision.hlsSignaling.codecs, "")

            let hev1Track = makeHEVCTrack(
                codecName: "hev1",
                codecID: "hev1",
                codecPrivate: codecPrivate
            )
            let hev1Decision = evaluate(videoTrack: hev1Track, videoRangeType: "SDR")
            XCTAssertTrue(hev1Decision.hlsSignaling.codecs.hasPrefix("hev1."))
            XCTAssertEqual(hev1Decision.videoEntry.sampleEntryType, "hev1")
        }

        let completeTrack = makeHEVCTrack(
            codecName: "hvc1",
            codecID: "hvc1",
            codecPrivate: makeHVCCWithVPSSPSPPS()
        )
        let completeDecision = evaluate(videoTrack: completeTrack, videoRangeType: "SDR")
        XCTAssertTrue(completeDecision.hlsSignaling.codecs.hasPrefix("hvc1."))
    }

    func testHEV1RewrittenToHVC1RequiresCompleteOutOfBandParameterSets() {
        var incompleteHVCC = makeHVCCWithVPSSPSPPS()
        incompleteHVCC[23] &= 0x7F
        incompleteHVCC[30] &= 0x7F
        incompleteHVCC[37] &= 0x7F
        let videoTrack = makeHEVCTrack(
            codecName: "hev1",
            codecID: "hev1",
            codecPrivate: incompleteHVCC
        )
        let plan = NativeBridgePlan(
            itemID: "hev1-rewritten-hvc1",
            sourceID: "hev1-rewritten-hvc1-source",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVI",
            dvProfile: 8,
            whyChosen: "effective-hvc1-completeness-test"
        )
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: makeStreamInfo(videoTrack: videoTrack),
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .dvProfile81Compatible
        )

        XCTAssertEqual(decision.videoEntry.sampleEntryType, "hvc1")
        XCTAssertEqual(decision.hlsSignaling.codecs, "")
        XCTAssertEqual(decision.reason, "unsupported_hevc_configuration")
    }

    func testHEV1RewrittenToPrimaryDVH1RequiresCompleteOutOfBandParameterSets() {
        var incompleteHVCC = makeHVCCWithVPSSPSPPS()
        incompleteHVCC[23] &= 0x7F
        incompleteHVCC[30] &= 0x7F
        incompleteHVCC[37] &= 0x7F
        let videoTrack = makeHEVCTrack(
            codecName: "hev1",
            codecID: "hev1",
            codecPrivate: incompleteHVCC
        )
        let plan = NativeBridgePlan(
            itemID: "hev1-rewritten-dvh1",
            sourceID: "hev1-rewritten-dvh1-source",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVI",
            dvProfile: 8,
            whyChosen: "effective-dvh1-completeness-test"
        )
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: makeStreamInfo(videoTrack: videoTrack),
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .primaryDolbyVisionExperimental
        )

        XCTAssertEqual(decision.videoEntry.sampleEntryType, "dvh1")
        XCTAssertEqual(decision.hlsSignaling.codecs, "")
        XCTAssertEqual(decision.reason, "unsupported_hevc_configuration")
    }

    func testHVC1AllowsIncompleteSEIArraysAlongsideCompleteParameterSets() async throws {
        let videoTrack = makeHEVCTrack(
            codecName: "hvc1",
            codecID: "hvc1",
            codecPrivate: makeHVCCWithVPSSPSPPSAndSEI()
        )
        let plan = makePlan(videoTrack: videoTrack, videoRangeType: "SDR")
        let streamInfo = makeStreamInfo(videoTrack: videoTrack)
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .hdr10OnlyFallback
        )

        XCTAssertTrue(decision.hlsSignaling.codecs.hasPrefix("hvc1."))
        XCTAssertEqual(decision.videoEntry.sampleEntryType, "hvc1")
        XCTAssertTrue(decision.videoEntry.includeHvcC)

        let repackager: any Repackager = FMP4Repackager(plan: plan)
        await repackager.setPackagingDecision(decision)
        let initSegment = try await repackager.generateInitSegment(streamInfo: streamInfo)
        XCTAssertEqual(InitSegmentInspector.inspect(initSegment).videoSampleEntry, "hvc1")
        XCTAssertNotNil(initSegment.range(of: Data("hvcC".utf8)))
    }

    func testDVH1AllowsIncompleteSEIArraysAlongsideCompleteParameterSets() async throws {
        let videoTrack = makeHEVCTrack(
            codecName: "hev1",
            codecID: "hev1",
            codecPrivate: makeHVCCWithVPSSPSPPSAndSEI()
        )
        let plan = NativeBridgePlan(
            itemID: "dvh1-with-sei",
            sourceID: "dvh1-with-sei-source",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVI",
            dvProfile: 8,
            whyChosen: "dvh1-sei-completeness-test"
        )
        let streamInfo = makeStreamInfo(videoTrack: videoTrack)
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .primaryDolbyVisionExperimental
        )

        XCTAssertEqual(decision.hlsSignaling.codecs, "dvh1.08.06")
        XCTAssertEqual(decision.videoEntry.sampleEntryType, "dvh1")
        XCTAssertTrue(decision.videoEntry.includeHvcC)

        let repackager: any Repackager = FMP4Repackager(plan: plan)
        await repackager.setPackagingDecision(decision)
        let initSegment = try await repackager.generateInitSegment(streamInfo: streamInfo)
        XCTAssertEqual(InitSegmentInspector.inspect(initSegment).videoSampleEntry, "dvh1")
        XCTAssertNotNil(initSegment.range(of: Data("hvcC".utf8)))
    }

    func testHVC1RejectsCompleteNonParameterSetArray() {
        let videoTrack = makeHEVCTrack(
            codecName: "hvc1",
            codecID: "hvc1",
            codecPrivate: makeHVCCWithVPSSPSPPSAndSEI(nonParameterArrayComplete: true)
        )
        let decision = evaluate(videoTrack: videoTrack, videoRangeType: "SDR")

        XCTAssertEqual(decision.hlsSignaling.codecs, "")
        XCTAssertFalse(decision.videoEntry.includeHvcC)
        XCTAssertEqual(decision.reason, "unsupported_hevc_configuration")
    }

    func testDecisionDrivenRepackagerInjectsBT2020PQColrDefaultsWhenMissing() async throws {
        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 3840,
            height: 1608,
            bitDepth: 10,
            codecPrivate: makeHVCC(),
            colourPrimaries: nil,
            transferCharacteristic: nil,
            matrixCoefficients: nil
        )
        let audioTrack = TrackInfo(
            id: 2,
            trackType: .audio,
            codecID: "A_EAC3",
            codecName: "eac3",
            isDefault: true,
            sampleRate: 48_000,
            channels: 8
        )

        let plan = NativeBridgePlan(
            itemID: "item-colr-defaults",
            sourceID: "source-colr-defaults",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: videoTrack,
            audioTrack: audioTrack,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: nil,
            dvProfile: 8,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            whyChosen: "test"
        )

        let streamInfo = StreamInfo(
            durationNanoseconds: 120_000_000_000,
            tracks: [videoTrack, audioTrack],
            hasChapters: false,
            seekable: true
        )

        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .primaryDolbyVisionExperimental
        )

        let repackager = FMP4Repackager(plan: plan)
        await repackager.setPackagingDecision(decision)
        let initSegment = try await repackager.generateInitSegment(streamInfo: streamInfo)

        guard let colr = try parseFirstColrNclx(from: initSegment) else {
            XCTFail("colr(nclx) box missing")
            return
        }

        XCTAssertEqual(colr.primaries, 9)
        XCTAssertEqual(colr.transfer, 16)
        XCTAssertEqual(colr.matrix, 9)
    }

    private func makeHVCC() -> Data {
        makeHVCCWithVPSSPSPPS()
    }

    private func makeHVCCWithOnlyVPS() -> Data {
        Data([
            0x01, 0x22, 0x20, 0x00, 0x00, 0x00, 0x90, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x99, 0xF0, 0x00, 0xFC,
            0xFD, 0xFA, 0xFA, 0x00, 0x00, 0x0F, 0x01,
            0xA0, 0x00, 0x01, 0x00, 0x02, 0x40, 0x01
        ])
    }

    private func makeHVCCWithVPSSPSPPS() -> Data {
        Data([
            0x01, 0x22, 0x20, 0x00, 0x00, 0x00, 0x90, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x99, 0xF0, 0x00, 0xFC,
            0xFD, 0xFA, 0xFA, 0x00, 0x00, 0x0F, 0x03,
            0xA0, 0x00, 0x01, 0x00, 0x02, 0x40, 0x01,
            0xA1, 0x00, 0x01, 0x00, 0x02, 0x42, 0x01,
            0xA2, 0x00, 0x01, 0x00, 0x02, 0x44, 0x01
        ])
    }

    private func makeHVCCWithVPSSPSPPSAndSEI(
        nonParameterArrayComplete: Bool = false
    ) -> Data {
        let prefixSEIArrayHeader: UInt8 = nonParameterArrayComplete ? 0xA7 : 0x27
        let suffixSEIArrayHeader: UInt8 = nonParameterArrayComplete ? 0xA8 : 0x28
        return Data([
            0x01, 0x22, 0x20, 0x00, 0x00, 0x00, 0x90, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x99, 0xF0, 0x00, 0xFC,
            0xFD, 0xFA, 0xFA, 0x00, 0x00, 0x0F, 0x05,
            0xA0, 0x00, 0x01, 0x00, 0x02, 0x40, 0x01,
            0xA1, 0x00, 0x01, 0x00, 0x02, 0x42, 0x01,
            0xA2, 0x00, 0x01, 0x00, 0x02, 0x44, 0x01,
            prefixSEIArrayHeader, 0x00, 0x01, 0x00, 0x02, 0x4E, 0x01,
            suffixSEIArrayHeader, 0x00, 0x01, 0x00, 0x02, 0x50, 0x01
        ])
    }

    private func makeHEVCTrack(
        codecName: String,
        codecID: String? = nil,
        codecPrivate: Data,
        transferCharacteristic: Int? = nil
    ) -> TrackInfo {
        TrackInfo(
            id: 1,
            trackType: .video,
            codecID: codecID ?? (codecName == "hev1" ? "hev1" : "V_MPEGH/ISO/HEVC"),
            codecName: codecName,
            isDefault: true,
            width: 3840,
            height: 2160,
            bitDepth: 10,
            codecPrivate: codecPrivate,
            colourPrimaries: transferCharacteristic == nil ? nil : 9,
            transferCharacteristic: transferCharacteristic,
            matrixCoefficients: transferCharacteristic == nil ? nil : 9
        )
    }

    private func evaluate(videoTrack: TrackInfo, videoRangeType: String?) -> NativeBridgePackagingDecision {
        let plan = NativeBridgePlan(
            itemID: "item-hevc-codec",
            sourceID: "source-hevc-codec",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: videoRangeType,
            whyChosen: "test"
        )
        return DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: makeStreamInfo(videoTrack: videoTrack),
            device: DeviceCapabilityFingerprint.current(),
            requestedMode: .hdr10OnlyFallback
        )
    }

    private func makePlan(videoTrack: TrackInfo, videoRangeType: String) -> NativeBridgePlan {
        NativeBridgePlan(
            itemID: "item-codec-fallback",
            sourceID: "source-codec-fallback",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: videoRangeType,
            whyChosen: "test"
        )
    }

    private func makeStreamInfo(videoTrack: TrackInfo) -> StreamInfo {
        StreamInfo(
            durationNanoseconds: 120_000_000_000,
            tracks: [videoTrack],
            hasChapters: false,
            seekable: true
        )
    }

    private static let avcC = Data([
        0x01, 0x42, 0x00, 0x1F, 0xFF, 0xE1, 0x00, 0x04,
        0x67, 0x42, 0x00, 0x1F, 0x01, 0x00, 0x02, 0x68, 0xCE
    ])

    private func parseFirstColrNclx(from data: Data) throws -> (primaries: UInt16, transfer: UInt16, matrix: UInt16)? {
        let nodes = try BMFFInspector.inspect(data)
        var colrNode: BMFFInspectNode?

        func walk(_ current: [BMFFInspectNode]) {
            for node in current {
                if node.type == "colr", colrNode == nil {
                    colrNode = node
                    return
                }
                walk(node.children)
                if colrNode != nil { return }
            }
        }
        walk(nodes)

        guard let colr = colrNode else { return nil }
        let payloadOffset = colr.offset + 8
        guard payloadOffset + 10 <= data.count else { return nil }
        let colorType = String(decoding: Array(data[payloadOffset..<(payloadOffset + 4)]), as: UTF8.self)
        guard colorType == "nclx" else { return nil }

        let primaries = readUInt16(data, at: payloadOffset + 4)
        let transfer = readUInt16(data, at: payloadOffset + 6)
        let matrix = readUInt16(data, at: payloadOffset + 8)
        return (primaries, transfer, matrix)
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        return (b0 << 8) | b1
    }
}
