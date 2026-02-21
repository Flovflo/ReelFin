import PlaybackEngine
import Shared
import XCTest

final class PlaybackDecisionEngineTests: XCTestCase {
    private let server = ServerConfiguration(serverURL: URL(string: "https://example.com")!)

    func testDirectPlayPreferredWhenCompatible() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "direct",
                itemID: "item",
                name: "Direct",
                container: "mp4",
                videoCodec: "h264",
                audioCodec: "aac",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/direct-stream.mp4"),
                directPlayURL: URL(string: "https://example.com/direct-play.mp4"),
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "direct")
        XCTAssertEqual(decision?.route, .directPlay(URL(string: "https://example.com/direct-play.mp4")!))
    }

    func testRemuxUsedWhenDirectPlayNotCompatible() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "remux",
                itemID: "item",
                name: "Remux",
                container: "mkv",
                videoCodec: "hevc",
                audioCodec: "aac",
                supportsDirectPlay: false,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/remux/master.m3u8"),
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "remux")
        XCTAssertEqual(decision?.route, .remux(URL(string: "https://example.com/remux/master.m3u8")!))
    }

    func testTranscodeFallbackWhenNoDirectOptions() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "transcode",
                itemID: "item",
                name: "Transcode",
                container: "avi",
                videoCodec: "mpeg2",
                audioCodec: "dts",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "transcode")
        XCTAssertEqual(decision?.route, .transcode(URL(string: "https://example.com/transcode.m3u8")!))
    }

    func testPerformanceModeCanRejectWhenOnlyTranscodeAvailable() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "transcode-only",
                itemID: "item",
                name: "Only Transcode",
                container: "mkv",
                videoCodec: "hevc",
                audioCodec: "dts",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(
            itemID: "item",
            sources: sources,
            configuration: server,
            token: "abc",
            allowTranscoding: false
        )

        XCTAssertNil(decision)
    }

    func testDolbyVisionDirectPlayWinsOverH264() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "h264",
                itemID: "item",
                name: "h264",
                container: "mp4",
                videoCodec: "h264",
                audioCodec: "aac",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/h264.mp4"),
                directPlayURL: URL(string: "https://example.com/h264.mp4"),
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            ),
            MediaSource(
                id: "dv",
                itemID: "item",
                name: "dv",
                container: "mp4",
                videoCodec: "dvh1",
                audioCodec: "eac3",
                videoBitDepth: 10,
                videoRange: "DolbyVision",
                audioChannelLayout: "7.1 Atmos",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/dv.mp4"),
                directPlayURL: URL(string: "https://example.com/dv.mp4"),
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "dv")
        XCTAssertEqual(decision?.route, .directPlay(URL(string: "https://example.com/dv.mp4")!))
    }
}
