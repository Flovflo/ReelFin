import CoreMedia
import NativeMediaCore
import XCTest

final class SubtitleParserTests: XCTestCase {
    func testSRTParserParsesCues() throws {
        let cues = try SRTParser().parse(Data("1\n00:00:01,000 --> 00:00:02,500\nHello\n".utf8))

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Hello")
        XCTAssertEqual(cues[0].start.seconds, 1, accuracy: 0.01)
    }

    func testWebVTTParserParsesCues() throws {
        let cues = try WebVTTParser().parse(Data("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi\n".utf8))

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Hi")
    }

    func testASSParserKeepsStylesAndReportsAnimatedOverrides() throws {
        let script = """
        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, Bold, Italic
        Style: Default,Arial,24,&H00FFFFFF,-1,0
        [Events]
        Format: Start, End, Style, Text
        Dialogue: 0:00:01.00,0:00:02.00,Default,{\\move(0,0,10,10)}Hello\\NWorld
        """
        let parsed = try ASSParser().parseScript(Data(script.utf8))

        XCTAssertEqual(parsed.events.count, 1)
        XCTAssertEqual(parsed.events[0].text, "Hello\nWorld")
        XCTAssertTrue(parsed.unsupportedFeatures.contains("animated_overrides"))
    }

    func testSubtitleClockAdapterAppliesCueTimingAndDelay() {
        let cue = SubtitleCue(
            id: "1",
            start: CMTime(seconds: 10, preferredTimescale: 1000),
            end: CMTime(seconds: 12, preferredTimescale: 1000),
            text: "Bonjour"
        )
        let adapter = SubtitleClockAdapter(delay: CMTime(seconds: 1, preferredTimescale: 1000))

        let active = adapter.activeCues(
            from: [cue],
            at: CMTime(seconds: 11.5, preferredTimescale: 1000)
        )
        let inactive = adapter.activeCues(
            from: [cue],
            at: CMTime(seconds: 13.5, preferredTimescale: 1000)
        )

        XCTAssertEqual(active.map(\.text), ["Bonjour"])
        XCTAssertTrue(inactive.isEmpty)
    }
}
