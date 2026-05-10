import PlaybackEngine
import XCTest

final class DolbyVisionClassificationTests: XCTestCase {
    func testDolbyVisionProfileClassificationUsesJellyfinMetadata() {
        XCTAssertEqual(DolbyVisionClass.classify(source: makeGuaranteeSource(dvProfile: 5)), .profile5SingleLayer)
        XCTAssertEqual(
            DolbyVisionClass.classify(source: makeGuaranteeSource(dvProfile: 8, dvBlSignalCompatibilityId: 1)),
            .profile8_1HDR10Compatible
        )
        XCTAssertEqual(
            DolbyVisionClass.classify(source: makeGuaranteeSource(dvProfile: 8, dvBlSignalCompatibilityId: 4)),
            .profile8_4HLGCompatible
        )
        XCTAssertEqual(DolbyVisionClass.classify(source: makeGuaranteeSource(dvProfile: 7)), .profile7DualLayer)
        XCTAssertEqual(DolbyVisionClass.classify(source: makeGuaranteeSource(dvProfile: nil)), .none)
    }
}
