import Foundation
import XCTest
@testable import PlaybackEngine
@testable import Shared

final class LocalMediaGatewayRoutePolicyTests: XCTestCase {
    func testTVOSUsesGatewayForAppleCompatibleDirectPlayInAutomaticMode() {
        XCTAssertTrue(
            LocalMediaGatewayRoutePolicy.shouldUseGateway(
                route: .directPlay(URL(string: "https://media.example.com/video.mp4")!),
                source: makeSource(container: "mp4", bitrate: 12_000_000),
                mediaCacheMode: .automatic,
                isTVOS: true,
                resumeSeconds: 0,
                hasCachedBytes: false
            )
        )
    }

    func testIOSUsesGatewayForHighBitrateOrResumedDirectPlayOnly() {
        XCTAssertFalse(
            LocalMediaGatewayRoutePolicy.shouldUseGateway(
                route: .directPlay(URL(string: "https://media.example.com/video.mp4")!),
                source: makeSource(container: "mp4", bitrate: 6_000_000),
                mediaCacheMode: .automatic,
                isTVOS: false,
                resumeSeconds: 0,
                hasCachedBytes: false
            )
        )

        XCTAssertTrue(
            LocalMediaGatewayRoutePolicy.shouldUseGateway(
                route: .directPlay(URL(string: "https://media.example.com/video.mp4")!),
                source: makeSource(container: "mp4", bitrate: 22_000_000),
                mediaCacheMode: .automatic,
                isTVOS: false,
                resumeSeconds: 0,
                hasCachedBytes: false
            )
        )

        XCTAssertTrue(
            LocalMediaGatewayRoutePolicy.shouldUseGateway(
                route: .directPlay(URL(string: "https://media.example.com/video.mp4")!),
                source: makeSource(container: "mp4", bitrate: 6_000_000),
                mediaCacheMode: .automatic,
                isTVOS: false,
                resumeSeconds: 900,
                hasCachedBytes: false
            )
        )
    }

    func testOffModeNeverUsesGateway() {
        XCTAssertFalse(
            LocalMediaGatewayRoutePolicy.shouldUseGateway(
                route: .directPlay(URL(string: "https://media.example.com/video.mp4")!),
                source: makeSource(container: "mp4", bitrate: 30_000_000),
                mediaCacheMode: .off,
                isTVOS: true,
                resumeSeconds: 900,
                hasCachedBytes: true
            )
        )
    }

    private func makeSource(container: String, bitrate: Int) -> MediaSource {
        MediaSource(
            id: "source-1",
            itemID: "item-1",
            name: "source-1",
            filePath: "/media/movie.\(container)",
            container: container,
            videoCodec: "hevc",
            audioCodec: "aac",
            bitrate: bitrate,
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
    }
}
