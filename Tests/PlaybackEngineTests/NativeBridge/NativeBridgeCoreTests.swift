@testable import PlaybackEngine
import CoreMedia
import XCTest

final class NativeBridgeCoreTests: XCTestCase {
    func testBMFFSanityParserValidatesInitSegmentStructure() async throws {
        let repackager = FMP4Repackager(plan: makePlan())
        let initSegment = try await repackager.generateInitSegment(streamInfo: makeStreamInfo())
        let boxes = try BMFFSanityParser.parseTopLevel(initSegment)

        XCTAssertTrue(BMFFSanityParser.containsPath(["ftyp"], in: boxes))
        XCTAssertTrue(BMFFSanityParser.containsPath(["moov", "trak", "mdia", "minf", "stbl", "stsd"], in: boxes))
    }

    func testBMFFSanityParserRejectsTruncatedHeader() {
        let data = Data([0x00, 0x00, 0x00])
        XCTAssertThrowsError(try BMFFSanityParser.parseTopLevel(data)) { error in
            XCTAssertEqual(error as? BMFFSanityParserError, .truncatedHeader(offset: 0))
        }
    }

    func testDiagnosticsCollectorDumpsInitSegment() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let collector = NativeBridgeDiagnosticsCollector(
            config: NativeBridgeDiagnosticsConfig(
                enabled: true,
                dumpSegments: true,
                maxFragmentDumpCount: 2,
                outputDirectoryURL: temp
            )
        )

        let repackager = FMP4Repackager(plan: makePlan(), diagnostics: collector)
        let initSegment = try await repackager.generateInitSegment(streamInfo: makeStreamInfo())
        XCTAssertFalse(initSegment.isEmpty)

        guard let bundle = await collector.snapshot(itemID: "item1", trackDump: "tracks=1"),
              let initURL = bundle.initSegmentURL else {
            XCTFail("Expected diagnostics bundle with init dump")
            return
        }
        let dumped = try Data(contentsOf: initURL)
        let boxes = try BMFFSanityParser.parseTopLevel(dumped)
        XCTAssertTrue(BMFFSanityParser.containsPath(["ftyp"], in: boxes))
    }

    func testEBMLInvalidVarIntThrowsInvalidMKV() {
        XCTAssertThrowsError(try EBMLParser.readElementSize(data: Data([0x00]), offset: 0)) { error in
            guard case NativeBridgeError.invalidMKV = error else {
                XCTFail("Expected invalidMKV, got \(error)")
                return
            }
        }
    }

    func testEBMLNegativeOffsetIsRejected() {
        XCTAssertThrowsError(try EBMLParser.readElementID(data: Data([0x1A, 0x45, 0xDF, 0xA3]), offset: -1)) { error in
            guard case NativeBridgeError.invalidMKV = error else {
                XCTFail("Expected invalidMKV, got \(error)")
                return
            }
        }
    }

    func testEBMLRangeOverflowIsRejected() {
        XCTAssertThrowsError(try EBMLParser.readUInt(data: Data([0x01]), offset: Int.max - 1, size: 8)) { error in
            guard case NativeBridgeError.invalidMKV = error else {
                XCTFail("Expected invalidMKV, got \(error)")
                return
            }
        }
    }

    func testEBMLParserHandlesRebasedDataOffsets() throws {
        var data = Data([0x00, 0x1A, 0x45, 0xDF, 0xA3])
        data.removeFirst() // Data now has non-zero startIndex internally.
        let (id, length) = try EBMLParser.readElementID(data: data, offset: 0)
        XCTAssertEqual(id, EBMLParser.idEBML)
        XCTAssertEqual(length, 4)
    }

    func testDolbyVisionGateDecision() {
        DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(true)
        DolbyVisionGate.setRuntimeDVPackagingEnabled(nil)
        defer {
            DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(nil)
            DolbyVisionGate.setRuntimeDVPackagingEnabled(nil)
        }

        let plan = NativeBridgePlan(
            itemID: "item1",
            sourceID: "source1",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: makeVideoTrack(),
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVI",
            dvProfile: 7,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            hdr10PlusPresentFlag: false,
            whyChosen: "test"
        )
        let streamInfo = makeStreamInfo()
        let decision = DolbyVisionGate.evaluate(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current()
        )
        if DeviceCapabilityFingerprint.current().supportsDolbyVision {
            XCTAssertTrue(decision.isEnabled)
        } else if case .disableDV = decision {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected DV disable on non-DV device")
        }
    }

    func testDolbyVisionGateAllowsProfile8InStrictRuntimeMode() {
        DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(true)
        DolbyVisionGate.setRuntimeDVPackagingEnabled(true)
        defer {
            DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(nil)
            DolbyVisionGate.setRuntimeDVPackagingEnabled(nil)
        }

        let plan = NativeBridgePlan(
            itemID: "item1",
            sourceID: "source1",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: makeVideoTrack(),
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            hdr10PlusPresentFlag: false,
            whyChosen: "test"
        )
        let streamInfo = makeStreamInfo()
        let decision = DolbyVisionGate.evaluate(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current()
        )
        if DeviceCapabilityFingerprint.current().supportsDolbyVision {
            XCTAssertTrue(decision.isEnabled)
        } else if case .disableDV(let reason) = decision {
            XCTAssertEqual(reason, "device_no_dolby_vision")
        } else {
            XCTFail("Expected DV disable on non-DV device")
        }
    }

    func testDolbyVisionGateUsesHVCCBitDepthWhenMetadataMissing() {
        DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(true)
        defer { DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(nil) }

        let hvcc10Bit = Data([
            0x01, 0x22, 0x20, 0x00, 0x00, 0x00, 0x90, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x99, 0xF0, 0x00, 0xFC,
            0xFD, 0xFA, 0xFA, 0x00, 0x00, 0x0F, 0x03, 0xA0
        ])
        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 3840,
            height: 1608,
            bitDepth: nil,
            codecPrivate: hvcc10Bit,
            colourPrimaries: 9,
            transferCharacteristic: 16,
            matrixCoefficients: 9
        )
        let plan = NativeBridgePlan(
            itemID: "item1",
            sourceID: "source1",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVI",
            dvProfile: 7,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            whyChosen: "test"
        )
        let streamInfo = StreamInfo(
            durationNanoseconds: 120_000_000_000,
            tracks: [videoTrack],
            hasChapters: false,
            seekable: true
        )
        let device = DeviceCapabilityFingerprint(
            supportsHEVC: true,
            supportsHEVCMain10: true,
            supportsH264: true,
            supportsAV1: false,
            supportsDolbyVision: true,
            supportsHDR10: true,
            supportsHLG: true,
            supportsAAC: true,
            supportsAC3: true,
            supportsEAC3: true,
            supportsAtmos: true,
            supportsFLAC: true,
            supportsALAC: true,
            supportsOpus: true,
            nativeContainers: ["mp4", "m4v", "mov", "m4a"],
            hlsSupported: true,
            modelIdentifier: "test-device",
            osVersion: "1.0",
            chipGeneration: .a15
        )

        let decision = DolbyVisionGate.evaluate(plan: plan, streamInfo: streamInfo, device: device)
        XCTAssertTrue(decision.isEnabled, "DV should not be disabled when hvcC indicates 10-bit.")
    }

    func testDolbyVisionGateRejectsWhenNeitherMetadataNorHVCCProvide10Bit() {
        DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(true)
        defer { DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(nil) }

        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 1920,
            height: 1080,
            bitDepth: nil,
            codecPrivate: nil
        )
        let plan = NativeBridgePlan(
            itemID: "item1",
            sourceID: "source1",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            whyChosen: "test"
        )
        let streamInfo = StreamInfo(
            durationNanoseconds: 120_000_000_000,
            tracks: [videoTrack],
            hasChapters: false,
            seekable: true
        )
        let device = DeviceCapabilityFingerprint(
            supportsHEVC: true,
            supportsHEVCMain10: true,
            supportsH264: true,
            supportsAV1: false,
            supportsDolbyVision: true,
            supportsHDR10: true,
            supportsHLG: true,
            supportsAAC: true,
            supportsAC3: true,
            supportsEAC3: true,
            supportsAtmos: true,
            supportsFLAC: true,
            supportsALAC: true,
            supportsOpus: true,
            nativeContainers: ["mp4", "m4v", "mov", "m4a"],
            hlsSupported: true,
            modelIdentifier: "test-device",
            osVersion: "1.0",
            chipGeneration: .a15
        )

        let decision = DolbyVisionGate.evaluate(plan: plan, streamInfo: streamInfo, device: device)
        guard case .disableDV(let reason) = decision else {
            XCTFail("Expected DV to be disabled when bit depth is unknown.")
            return
        }
        XCTAssertTrue(reason.contains("bit_depth_below_10"))
    }

    func testDolbyVisionGateDisabledWhenExperimentalFlagIsOff() {
        DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(nil)

        let plan = NativeBridgePlan(
            itemID: "item1",
            sourceID: "source1",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: makeVideoTrack(),
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            whyChosen: "test"
        )

        let decision = DolbyVisionGate.evaluate(
            plan: plan,
            streamInfo: makeStreamInfo(),
            device: DeviceCapabilityFingerprint.current()
        )
        guard case .disableDV(let reason) = decision else {
            XCTFail("Expected DV to be disabled when experimental flag is off.")
            return
        }
        XCTAssertEqual(reason, "experimental_dv_packaging_disabled")
    }

    func testDolbyVisionGateIgnoresPersistedUserDefaultsFlag() {
        UserDefaults.standard.set(true, forKey: "reelfin.nativebridge.dv.experimental")
        defer { UserDefaults.standard.removeObject(forKey: "reelfin.nativebridge.dv.experimental") }
        DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(nil)

        let plan = NativeBridgePlan(
            itemID: "item1",
            sourceID: "source1",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: makeVideoTrack(),
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            whyChosen: "test"
        )
        let decision = DolbyVisionGate.evaluate(
            plan: plan,
            streamInfo: makeStreamInfo(),
            device: DeviceCapabilityFingerprint.current()
        )

        guard case .disableDV(let reason) = decision else {
            XCTFail("Expected DV to stay disabled unless explicit env/test override is enabled.")
            return
        }
        XCTAssertEqual(reason, "experimental_dv_packaging_disabled")
    }

    func testAnnexBConversionHandlesMixedStartCodes() async throws {
        let repackager = FMP4Repackager(plan: makePlan())
        let packet = DemuxedPacket(
            trackID: 1,
            timestamp: 0,
            duration: 41_708_333,
            isKeyframe: true,
            data: Data([0x00, 0x00, 0x01, 0x65, 0x88, 0x00, 0x00, 0x00, 0x01, 0x41, 0x99, 0xAA])
        )
        let fragment = try await repackager.generateFragment(packets: [packet])
        let boxes = try BMFFSanityParser.parseTopLevel(fragment)
        guard let mdat = boxes.first(where: { $0.type == "mdat" }) else {
            XCTFail("Expected mdat box")
            return
        }
        let payloadStart = mdat.startOffset + 8
        let payloadEnd = mdat.startOffset + mdat.size
        let payload = fragment[payloadStart..<payloadEnd]
        let expectedPrefix = Data([0x00, 0x00, 0x00, 0x02, 0x65, 0x88, 0x00, 0x00, 0x00, 0x03, 0x41, 0x99, 0xAA])
        XCTAssertEqual(Data(payload), expectedPrefix)
    }

    func testSampleTimestampRoundtripStability() {
        for idx in 0..<10_000 {
            let ts = Int64(idx) * 41_708_333
            let sample = Sample(trackID: 1, pts: CMTime(value: ts, timescale: 1_000_000_000), duration: CMTime(value: 41_708_333, timescale: 1_000_000_000), isKeyframe: idx % 24 == 0, data: Data([0x01]))
            XCTAssertLessThanOrEqual(abs(sample.ptsNanoseconds - ts), 1)
        }
    }

    func testProfile8InitSegmentFallsBackToCleanHDR10SampleEntry() async throws {
        DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(true)
        defer { DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(nil) }

        let plan = NativeBridgePlan(
            itemID: "item1",
            sourceID: "source1",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: makeVideoTrack(),
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            whyChosen: "test"
        )

        let repackager = FMP4Repackager(plan: plan)
        let initSegment = try await repackager.generateInitSegment(streamInfo: makeStreamInfo())
        let nodes = try BMFFInspector.inspect(initSegment)
        let allTypes = flattenTypes(nodes)

        XCTAssertTrue(allTypes.contains("hvc1"))
        XCTAssertFalse(allTypes.contains("dvh1"))
        XCTAssertFalse(allTypes.contains("dvcC"))
    }

    func testFragmentStripsDolbyVisionRPUNALsWhenDVDisabled() async throws {
        DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(nil)
        defer { DolbyVisionGate.setExperimentalDVPackagingEnabledForTesting(nil) }

        let plan = NativeBridgePlan(
            itemID: "item1",
            sourceID: "source1",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: makeVideoTrack(),
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            whyChosen: "test"
        )

        let repackager = FMP4Repackager(plan: plan)
        _ = try await repackager.generateInitSegment(streamInfo: makeStreamInfo())

        let frame = makeLengthPrefixedHEVCFrameWithRPU()
        let packet = DemuxedPacket(
            trackID: 1,
            timestamp: 0,
            duration: 41_708_333,
            isKeyframe: true,
            data: frame
        )
        let fragment = try await repackager.generateFragment(packets: [packet])
        let boxes = try BMFFSanityParser.parseTopLevel(fragment)
        guard let mdat = boxes.first(where: { $0.type == "mdat" }) else {
            XCTFail("Missing mdat box")
            return
        }
        let payload = fragment[(mdat.startOffset + 8)..<(mdat.startOffset + mdat.size)]
        let naluTypes = extractHEVCNALUTypesFromLengthPrefixedPayload(Data(payload))
        XCTAssertTrue(naluTypes.contains(20), "IDR should be preserved.")
        XCTAssertFalse(naluTypes.contains(62), "DV RPU (UNSPEC62) should be stripped in HDR10 fallback.")
    }

    func testFragmentContainsExpectedTrunAndTfdtMetadata() async throws {
        let repackager = FMP4Repackager(plan: makePlan())
        _ = try await repackager.generateInitSegment(streamInfo: makeStreamInfo())

        let packets = [
            DemuxedPacket(trackID: 1, timestamp: 0, duration: 41_708_333, isKeyframe: true, data: Data([0x00, 0x00, 0x00, 0x02, 0x26, 0x01])),
            DemuxedPacket(trackID: 1, timestamp: 41_708_333, duration: 41_708_333, isKeyframe: false, data: Data([0x00, 0x00, 0x00, 0x02, 0x02, 0x01]))
        ]
        let fragment = try await repackager.generateFragment(packets: packets)
        let nodes = try BMFFInspector.inspect(fragment)
        let trunNodes = collectNodes(ofType: "trun", in: nodes)
        let tfdtNodes = collectNodes(ofType: "tfdt", in: nodes)

        XCTAssertFalse(trunNodes.isEmpty)
        XCTAssertFalse(tfdtNodes.isEmpty)
        XCTAssertTrue(trunNodes.contains { ($0.summary ?? "").contains("sampleCount=2") })
        XCTAssertTrue(trunNodes.contains { ($0.summary ?? "").contains("dataOffset=") })
        XCTAssertTrue(tfdtNodes.contains { ($0.summary ?? "").contains("baseDecodeTime=") })
    }

    private func makePlan() -> NativeBridgePlan {
        NativeBridgePlan(
            itemID: "item1",
            sourceID: "source1",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: makeVideoTrack(),
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "HDR10",
            whyChosen: "test"
        )
    }

    private func makeVideoTrack() -> TrackInfo {
        TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 3840,
            height: 1608,
            bitDepth: 10,
            codecPrivate: Data([0x01, 0x01, 0x60, 0x00]),
            colourPrimaries: 9,
            transferCharacteristic: 16,
            matrixCoefficients: 9
        )
    }

    private func makeStreamInfo() -> StreamInfo {
        StreamInfo(
            durationNanoseconds: 120_000_000_000,
            tracks: [makeVideoTrack()],
            hasChapters: false,
            seekable: true
        )
    }

    private func flattenTypes(_ nodes: [BMFFInspectNode]) -> [String] {
        var output: [String] = []
        func walk(_ items: [BMFFInspectNode]) {
            for node in items {
                output.append(node.type)
                walk(node.children)
            }
        }
        walk(nodes)
        return output
    }

    private func collectNodes(ofType type: String, in nodes: [BMFFInspectNode]) -> [BMFFInspectNode] {
        var output: [BMFFInspectNode] = []
        func walk(_ items: [BMFFInspectNode]) {
            for node in items {
                if node.type == type {
                    output.append(node)
                }
                walk(node.children)
            }
        }
        walk(nodes)
        return output
    }

    private func makeLengthPrefixedHEVCFrameWithRPU() -> Data {
        // AUD(35), VPS(32), SPS(33), PPS(34), IDR(20), RPU(62)
        let nalus: [Data] = [
            Data([0x46, 0x01]),
            Data([0x40, 0x01, 0x0C]),
            Data([0x42, 0x01, 0x01]),
            Data([0x44, 0x01, 0xC0]),
            Data([0x28, 0x01, 0xAA, 0xBB]),
            Data([0x7C, 0x01, 0x11, 0x22]) // type 62
        ]
        var out = Data()
        for nalu in nalus {
            let len = UInt32(nalu.count).bigEndian
            withUnsafeBytes(of: len) { out.append(contentsOf: $0) }
            out.append(nalu)
        }
        return out
    }

    private func extractHEVCNALUTypesFromLengthPrefixedPayload(_ data: Data) -> [Int] {
        var types: [Int] = []
        var offset = 0
        while offset + 4 <= data.count {
            let len = Int(data[offset]) << 24
                | Int(data[offset + 1]) << 16
                | Int(data[offset + 2]) << 8
                | Int(data[offset + 3])
            offset += 4
            guard len > 0, offset + len <= data.count else { break }
            let naluType = Int((data[offset] >> 1) & 0x3F)
            types.append(naluType)
            offset += len
        }
        return types
    }
}
