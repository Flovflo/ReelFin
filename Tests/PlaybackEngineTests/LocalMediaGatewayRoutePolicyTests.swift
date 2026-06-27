import Foundation
import XCTest
@testable import PlaybackEngine
@testable import Shared

/// The local cache gateway is DISABLED on the playback path: direct play always streams straight
/// from the origin via AVPlayer. The origin sustains ~100 Mbps with clean 206 range responses at
/// any offset (≈4x what a high-bitrate DV/4K original needs), whereas proxying through the local
/// gateway churned (per-range reconnects + per-window upstream handshakes + cancelled in-flight
/// windows) and stalled playback mid-stream on both first play and resume — even with hundreds of
/// MB already cached. `shouldUseGateway` must therefore return false for every direct-play shape.
final class LocalMediaGatewayRoutePolicyTests: XCTestCase {

    func testGatewayNeverEngagedOnPlaybackPath() {
        let urls = [
            URL(string: "https://media.example.com/video.mp4")!,
            URL(string: "https://media.example.com/Videos/item/stream.mp4?static=true")!,
            URL(string: "https://media.example.com/Videos/item/stream")!,
            URL(string: "http://127.0.0.1:59235/media/session")!
        ]
        let sources = [
            makeSource(container: "mp4", bitrate: 6_000_000),
            makeSource(container: "mp4", bitrate: 26_000_000, fileSize: 12_000_000_000),
            makeSource(container: "mov,mp4,m4a,3gp,3g2,mj2", bitrate: 26_000_000, fileSize: 12_000_000_000, videoRangeType: "DOVIWithHDR10", dvProfile: 8),
            makeSource(container: "mkv", bitrate: 30_000_000)
        ]
        for url in urls {
            for source in sources {
                for isTVOS in [false, true] {
                    for resume in [0.0, 1031.7] {
                        for cached in [(false, Int64(0)), (true, Int64(712_162_066))] {
                            XCTAssertFalse(
                                LocalMediaGatewayRoutePolicy.shouldUseGateway(
                                    route: .directPlay(url),
                                    source: source,
                                    mediaCacheMode: .automatic,
                                    isTVOS: isTVOS,
                                    resumeSeconds: resume,
                                    hasCachedBytes: cached.0,
                                    cachedBytes: cached.1
                                ),
                                "Gateway must never be on the playback path (url=\(url), tvOS=\(isTVOS), resume=\(resume), cached=\(cached.0))"
                            )
                        }
                    }
                }
            }
        }
    }

    func testGatewayOffForNonDirectPlayAndOffMode() {
        XCTAssertFalse(
            LocalMediaGatewayRoutePolicy.shouldUseGateway(
                route: .directPlay(URL(string: "https://media.example.com/video.mp4")!),
                source: makeSource(container: "mp4", bitrate: 30_000_000),
                mediaCacheMode: .off,
                isTVOS: false,
                resumeSeconds: 0,
                hasCachedBytes: true,
                cachedBytes: 64 * 1_024 * 1_024
            )
        )
    }

    private func makeSource(
        container: String,
        bitrate: Int,
        fileSize: Int64? = nil,
        videoRangeType: String? = nil,
        dvProfile: Int? = nil
    ) -> MediaSource {
        MediaSource(
            id: "source-1",
            itemID: "item-1",
            name: "source-1",
            filePath: "/media/movie.\(container)",
            fileSize: fileSize,
            container: container,
            videoCodec: "hevc",
            audioCodec: "aac",
            bitrate: bitrate,
            videoBitDepth: videoRangeType == nil ? nil : 10,
            videoRangeType: videoRangeType,
            dvProfile: dvProfile,
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
    }
}
