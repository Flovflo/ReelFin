import PlaybackEngine
import Shared
import XCTest

final class PlaybackAssetSelectionOptimizationTests: XCTestCase {
    func test_directPlaySelection_isAppleOptimized() {
        let selection = makeSelection(
            route: .directPlay(URL(string: "https://example.com/movie.mp4")!)
        )

        XCTAssertTrue(selection.isAppleOptimized)
    }

    func test_transcodeSelection_isNotAppleOptimized() {
        let selection = makeSelection(
            route: .transcode(URL(string: "https://example.com/movie.m3u8")!)
        )

        XCTAssertFalse(selection.isAppleOptimized)
    }

    private func makeSelection(route: PlaybackRoute) -> PlaybackAssetSelection {
        PlaybackAssetSelection(
            source: MediaSource(
                id: "movie-1",
                itemID: "movie-1",
                name: "Movie",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/movie.m3u8"),
                directPlayURL: URL(string: "https://example.com/movie.mp4"),
                transcodeURL: URL(string: "https://example.com/movie-transcode.m3u8")
            ),
            decision: PlaybackDecision(
                sourceID: "movie-1",
                route: route
            ),
            assetURL: URL(string: "https://example.com/movie.mp4")!,
            headers: [:],
            debugInfo: PlaybackDebugInfo(
                container: "mp4",
                videoCodec: "hevc",
                videoBitDepth: 10,
                hdrMode: .dolbyVision,
                audioMode: "eac3",
                bitrate: 28_000_000,
                playMethod: "DirectPlay"
            )
        )
    }
}
