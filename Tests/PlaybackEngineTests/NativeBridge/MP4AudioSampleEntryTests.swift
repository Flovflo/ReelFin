@testable import PlaybackEngine
import Foundation
import XCTest

final class MP4AudioSampleEntryTests: XCTestCase {
    func testEC3SampleEntrySerializesValidChannelsSampleRateAndDec3() throws {
        let track = TrackInfo(
            id: 2,
            trackType: .audio,
            codecID: "A_EAC3",
            codecName: "eac3",
            isDefault: true,
            sampleRate: 48_000,
            channels: 8
        )

        let stsd = MP4BoxWriter.writeStsd(track: track)
        let nodes = try BMFFInspector.inspect(stsd)

        guard let stsdNode = nodes.first(where: { $0.type == "stsd" }) else {
            XCTFail("stsd box missing")
            return
        }
        guard let ec3Node = stsdNode.children.first(where: { $0.type == "ec-3" }) else {
            XCTFail("ec-3 sample entry missing")
            return
        }

        XCTAssertTrue((ec3Node.summary ?? "").contains("channels=8"))
        XCTAssertTrue((ec3Node.summary ?? "").contains("sampleRate=48000"))

        let sampleEntryOffset = ec3Node.offset
        let channelCount = Int(readUInt16(stsd, at: sampleEntryOffset + 24))
        let sampleRateFixed = readUInt32(stsd, at: sampleEntryOffset + 32)
        let sampleRate = Int(sampleRateFixed >> 16)

        XCTAssertEqual(channelCount, 8)
        XCTAssertEqual(sampleRate, 48_000)
        XCTAssertEqual(sampleRateFixed & 0xFFFF, 0, "Sample rate must be encoded as 16.16 fixed-point integer.")

        guard let dec3Node = ec3Node.children.first(where: { $0.type == "dec3" }) else {
            XCTFail("dec3 box missing inside ec-3 sample entry")
            return
        }

        XCTAssertEqual(dec3Node.size, 14, "7.1 E-AC-3 should serialize with a 6-byte dec3 payload (14-byte box).")

        let dec3PayloadOffset = dec3Node.offset + 8
        let dec3Word0 = readUInt16(stsd, at: dec3PayloadOffset)
        let numIndSubMinusOne = Int(dec3Word0 & 0x0007)
        XCTAssertEqual(numIndSubMinusOne, 0)

        let fscod = (stsd[dec3PayloadOffset + 2] & 0b1100_0000) >> 6
        XCTAssertEqual(fscod, 0, "fscod=0 must be used for 48 kHz E-AC-3.")

        let numDepSub = Int((stsd[dec3PayloadOffset + 4] & 0b0001_1110) >> 1)
        XCTAssertEqual(numDepSub, 1, "7.1 signaling should use one dependent substream.")
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        return (b0 << 8) | b1
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }
}
