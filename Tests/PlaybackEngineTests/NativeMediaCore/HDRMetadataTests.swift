import NativeMediaCore
import XCTest

final class HDRMetadataTests: XCTestCase {
    func testMatroskaHDRMetadataMapping() {
        XCTAssertEqual(HDRMetadataMapper.primaries(matroska: 9), .bt2020)
        XCTAssertEqual(HDRMetadataMapper.transfer(matroska: 16), .pq)
        XCTAssertEqual(HDRMetadataMapper.transfer(matroska: 18), .hlg)
        XCTAssertEqual(HDRMetadataMapper.matrix(matroska: 9), .bt2020NonConstant)
    }
}
