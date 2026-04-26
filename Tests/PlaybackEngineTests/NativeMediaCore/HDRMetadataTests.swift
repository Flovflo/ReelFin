import CoreMedia
import NativeMediaCore
import XCTest

final class HDRMetadataTests: XCTestCase {
    func testMatroskaHDRMetadataMapping() {
        XCTAssertEqual(HDRMetadataMapper.primaries(matroska: 9), .bt2020)
        XCTAssertEqual(HDRMetadataMapper.transfer(matroska: 16), .pq)
        XCTAssertEqual(HDRMetadataMapper.transfer(matroska: 18), .hlg)
        XCTAssertEqual(HDRMetadataMapper.matrix(matroska: 9), .bt2020NonConstant)
    }

    func testCoreMediaExtensionsPreserveHDR10ColorTags() throws {
        let metadata = HDRMetadata(
            format: .hdr10,
            colorPrimaries: .bt2020,
            transferFunction: .pq,
            matrixCoefficients: .bt2020NonConstant,
            bitDepth: 10
        )

        let extensions = try XCTUnwrap(HDRCoreMediaMapper.formatDescriptionExtensions(for: metadata) as NSDictionary?)

        XCTAssertEqual(extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String, kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String)
        XCTAssertEqual(extensions[kCMFormatDescriptionExtension_TransferFunction] as? String, kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
        XCTAssertEqual(extensions[kCMFormatDescriptionExtension_YCbCrMatrix] as? String, kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String)
        XCTAssertEqual((extensions[kCMFormatDescriptionExtension_Depth] as? NSNumber)?.intValue, 10)
    }

    func testCoreMediaExtensionsPreserveDolbyVisionDefaults() throws {
        let metadata = HDRMetadata(
            format: .dolbyVision,
            bitDepth: 10,
            dolbyVision: DolbyVisionMetadata(profile: 8, source: "test")
        )

        let extensions = try XCTUnwrap(HDRCoreMediaMapper.formatDescriptionExtensions(for: metadata) as NSDictionary?)

        XCTAssertEqual(extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String, kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String)
        XCTAssertEqual(extensions[kCMFormatDescriptionExtension_TransferFunction] as? String, kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
        XCTAssertEqual(extensions[kCMFormatDescriptionExtension_YCbCrMatrix] as? String, kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String)
        XCTAssertEqual((extensions[kCMFormatDescriptionExtension_Depth] as? NSNumber)?.intValue, 10)
    }

    func testCoreMediaMetadataDetectsDolbyVisionCodec() throws {
        var description: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: FourCharCode("dvh1"),
            width: 3840,
            height: 1604,
            extensions: [
                kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020,
                kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ,
                kCMFormatDescriptionExtension_YCbCrMatrix: kCMFormatDescriptionYCbCrMatrix_ITU_R_2020,
                kCMFormatDescriptionExtension_Depth: 10
            ] as CFDictionary,
            formatDescriptionOut: &description
        )
        XCTAssertEqual(status, noErr)

        let metadata = try XCTUnwrap(HDRCoreMediaMapper.metadata(from: description, codecFourCC: "dvh1"))

        XCTAssertEqual(metadata.format, .dolbyVision)
        XCTAssertEqual(metadata.colorPrimaries, .bt2020)
        XCTAssertEqual(metadata.transferFunction, .pq)
        XCTAssertEqual(metadata.matrixCoefficients, .bt2020NonConstant)
        XCTAssertEqual(metadata.bitDepth, 10)
        XCTAssertEqual(metadata.dolbyVision?.source, "cmFormatDescription")
    }

    func testCoreMediaMetadataDetectsDolbyVisionFromCodecWhenDescriptionIsMissing() throws {
        let metadata = try XCTUnwrap(
            HDRCoreMediaMapper.metadata(from: nil, codecFourCC: "dvh1", fallbackBitDepth: 10)
        )

        XCTAssertEqual(metadata.format, .dolbyVision)
        XCTAssertEqual(metadata.bitDepth, 10)
        XCTAssertEqual(metadata.dolbyVision?.source, "codecFourCC")
    }
}

private extension FourCharCode {
    init(_ string: String) {
        self = string.utf8.reduce(0) { ($0 << 8) + FourCharCode($1) }
    }
}
