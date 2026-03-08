@testable import PlaybackEngine
import XCTest

final class SRTWebVTTConverterTests: XCTestCase {
    func testConvertsSimpleSRTToWebVTT() throws {
        let input = """
        1
        00:00:01,500 --> 00:00:03,200
        Hello world

        2
        00:00:04,000 --> 00:00:05,000
        Next line
        """

        let doc = try SRTWebVTTConverter().convert(input)

        XCTAssertEqual(doc.cues.count, 2)
        XCTAssertEqual(doc.cues[0].start, "00:00:01.500")
        XCTAssertEqual(doc.cues[0].end, "00:00:03.200")
        XCTAssertTrue(doc.text.contains("WEBVTT"))
        XCTAssertTrue(doc.text.contains("Hello world"))
    }

    func testPreservesBasicStylingTokens() throws {
        let input = """
        1
        00:00:01,000 --> 00:00:02,000
        {\\i1}Italic{\\i0}
        """

        let doc = try SRTWebVTTConverter().convert(input)
        XCTAssertEqual(doc.cues.first?.payload, "<i>Italic</i>")
    }

    func testThrowsOnInvalidTimestamp() {
        let input = """
        1
        BAD --> 00:00:02,000
        Oops
        """

        XCTAssertThrowsError(try SRTWebVTTConverter().convert(input))
    }
}
