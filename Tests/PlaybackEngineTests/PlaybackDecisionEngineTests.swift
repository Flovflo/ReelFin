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
                container: "avi",
                videoCodec: "mpeg2",
                audioCodec: "aac",
                supportsDirectPlay: false,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/remux.mkv"),
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "remux")
        XCTAssertEqual(decision?.route, .remux(URL(string: "https://example.com/remux.mkv")!))
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
}
