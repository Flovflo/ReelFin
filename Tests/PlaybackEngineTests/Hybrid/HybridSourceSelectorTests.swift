import XCTest
@testable import PlaybackEngine
@testable import Shared

final class HybridSourceSelectorTests: XCTestCase {
    private let selector = HybridSourceSelector()

    func testAnalysisSourcePrefersDirectPlayableOriginalSource() {
        let transcodeOnly = makeSource(
            id: "transcode",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directPlayURL: nil,
            directStreamURL: nil,
            transcodeURL: URL(string: "https://example.com/master.m3u8"),
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3"
        )
        let direct = makeSource(
            id: "direct",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directPlayURL: URL(string: "https://example.com/video.mkv"),
            directStreamURL: URL(string: "https://example.com/video.mkv"),
            transcodeURL: URL(string: "https://example.com/master.m3u8"),
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3"
        )

        let selected = selector.analysisSource(from: [transcodeOnly, direct])

        XCTAssertEqual(selected?.id, direct.id)
    }

    func testVLCPlaybackSourcePrefersDirectURLOverTranscode() {
        let direct = makeSource(
            id: "direct",
            supportsDirectPlay: false,
            supportsDirectStream: true,
            directPlayURL: nil,
            directStreamURL: URL(string: "https://example.com/video.mkv"),
            transcodeURL: URL(string: "https://example.com/master.m3u8")
        )
        let transcodeOnly = makeSource(
            id: "transcode",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directPlayURL: nil,
            directStreamURL: nil,
            transcodeURL: URL(string: "https://example.com/master.m3u8")
        )

        let selected = selector.playbackSource(for: .vlc, from: [transcodeOnly, direct], preferred: nil)

        XCTAssertEqual(selected?.id, direct.id)
    }

    func testNativePlaybackSourceRejectsTranscodeOnlySource() {
        let transcodeOnly = makeSource(
            id: "transcode",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directPlayURL: nil,
            directStreamURL: nil,
            transcodeURL: URL(string: "https://example.com/master.m3u8")
        )

        let selected = selector.playbackSource(for: .native, from: [transcodeOnly], preferred: transcodeOnly)

        XCTAssertNil(selected)
    }

    private func makeSource(
        id: String,
        supportsDirectPlay: Bool,
        supportsDirectStream: Bool,
        directPlayURL: URL?,
        directStreamURL: URL?,
        transcodeURL: URL?,
        container: String? = "mkv",
        videoCodec: String? = "hevc",
        audioCodec: String? = "eac3"
    ) -> MediaSource {
        MediaSource(
            id: id,
            itemID: "item",
            name: id,
            container: container,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            supportsDirectPlay: supportsDirectPlay,
            supportsDirectStream: supportsDirectStream,
            directStreamURL: directStreamURL,
            directPlayURL: directPlayURL,
            transcodeURL: transcodeURL
        )
    }
}
