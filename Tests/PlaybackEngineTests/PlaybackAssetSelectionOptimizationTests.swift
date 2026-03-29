import PlaybackEngine
import Shared
import XCTest

final class PlaybackAssetSelectionOptimizationTests: XCTestCase {
    func testDirectPlaySelectionIsAppleOptimized() {
        let selection = makeSelection(
            route: .directPlay(URL(string: "https://example.com/direct.mp4")!)
        )

        XCTAssertTrue(selection.isAppleOptimized)
    }

    func testNativeDirectPlanIsAppleOptimized() {
        let selection = makeSelection(
            route: .remux(URL(string: "https://example.com/remux.m3u8")!),
            playbackPlan: PlaybackPlan(
                itemID: "item",
                sourceID: "source",
                lane: .nativeDirectPlay,
                targetURL: URL(string: "https://example.com/direct.mp4"),
                selectedVideoCodec: "hevc",
                selectedAudioCodec: "eac3",
                selectedSubtitleCodec: nil,
                hdrMode: .dolbyVision,
                subtitleMode: .native,
                seekMode: .serverManaged,
                fallbackGraph: [],
                reasonChain: PlaybackReasonChain()
            )
        )

        XCTAssertTrue(selection.isAppleOptimized)
    }

    func testTranscodeSelectionNeedsServerPrep() {
        let selection = makeSelection(
            route: .transcode(URL(string: "https://example.com/transcode.m3u8")!)
        )

        XCTAssertFalse(selection.isAppleOptimized)
    }

    private func makeSelection(
        route: PlaybackRoute,
        playbackPlan: PlaybackPlan? = nil
    ) -> PlaybackAssetSelection {
        let source = MediaSource(
            id: "source",
            itemID: "item",
            name: "Example",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/stream.m3u8"),
            directPlayURL: URL(string: "https://example.com/direct.mp4"),
            transcodeURL: URL(string: "https://example.com/transcode.m3u8")
        )

        let debugInfo = PlaybackDebugInfo(
            container: "mp4",
            videoCodec: "hevc",
            videoBitDepth: 10,
            hdrMode: .dolbyVision,
            audioMode: "EAC3",
            bitrate: 18_000_000,
            playMethod: "DirectPlay"
        )

        return PlaybackAssetSelection(
            source: source,
            decision: PlaybackDecision(sourceID: source.id, route: route, playbackPlan: playbackPlan),
            playbackPlan: playbackPlan,
            assetURL: URL(string: "https://example.com/asset")!,
            headers: [:],
            debugInfo: debugInfo
        )
    }
}
