@testable import PlaybackEngine
import Foundation
import XCTest

final class DolbyVisionPackagingDecisionTests: XCTestCase {
    func testEvaluatePackagingFallsBackToPQForMain10WhenColourMetadataMissing() {
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
            itemID: "item-pq-fallback",
            sourceID: "source-pq-fallback",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: nil,
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
        XCTAssertEqual(decision.hlsSignaling.videoRange, "PQ")
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
        Data([
            0x01, 0x22, 0x20, 0x00, 0x00, 0x00, 0x90, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x99, 0xF0, 0x00, 0xFC,
            0xFD, 0xFA, 0xFA, 0x00, 0x00, 0x0F, 0x03, 0xA0
        ])
    }

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
