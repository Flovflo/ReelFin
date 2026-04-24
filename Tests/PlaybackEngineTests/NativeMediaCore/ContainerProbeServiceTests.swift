import NativeMediaCore
import XCTest

final class ContainerProbeServiceTests: XCTestCase {
    private let probe = ContainerProbeService()

    func testDetectsMP4FromFtypBox() {
        let data = Data([0, 0, 0, 24]) + Data("ftypisom".utf8)
        let result = probe.probe(bytes: data)
        XCTAssertEqual(result.format, .mp4)
        XCTAssertEqual(result.confidence, .exactSignature)
    }

    func testDetectsMatroskaFromEBMLHeader() {
        let result = probe.probe(bytes: Data([0x1A, 0x45, 0xDF, 0xA3, 0x80]))
        XCTAssertEqual(result.format, .matroska)
    }

    func testDetectsMPEGTSFrom188ByteSyncPattern() {
        var data = Data(repeating: 0, count: 377)
        data[0] = 0x47
        data[188] = 0x47

        let result = probe.probe(bytes: data)

        XCTAssertEqual(result.format, .mpegTS)
        XCTAssertEqual(result.confidence, .strong)
    }

    func testDetectsM2TSFrom192ByteSyncPattern() {
        var data = Data(repeating: 0, count: 389)
        data[4] = 0x47
        data[196] = 0x47

        let result = probe.probe(bytes: data)

        XCTAssertEqual(result.format, .m2ts)
        XCTAssertEqual(result.confidence, .strong)
    }

    func testUsesHintOnlyWhenSignatureUnknown() {
        let result = probe.probe(bytes: Data([0x00, 0x01]), hint: "movie.webm")
        XCTAssertEqual(result.format, .webm)
        XCTAssertEqual(result.confidence, .hinted)
    }
}
