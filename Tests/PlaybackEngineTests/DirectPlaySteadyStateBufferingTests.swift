import Foundation
@testable import PlaybackEngine
import XCTest

/// Regression tests for the steady-state buffering policy that prevents direct play from
/// cutting to rebuffer after ~1 min. Startup stays latency-biased; once a frame renders we
/// switch to a stability-biased buffer (`waits == true`, generous forward buffer).
final class DirectPlaySteadyStateBufferingTests: XCTestCase {
    private func directPlay(_ urlString: String) -> PlaybackRoute {
        .directPlay(URL(string: urlString)!)
    }

    func testRemoteDirectPlayGetsStabilityBiasedBuffer() {
        let policy = DirectPlaySessionPolicy.steadyStateBuffering(
            route: directPlay("https://jellyfin.example.com/Videos/item/stream.mp4?static=true"),
            source: nil,
            currentForwardBufferDuration: 2,
            isTVOS: false
        )
        XCTAssertEqual(policy?.waitsToMinimizeStalling, true)
        XCTAssertEqual(policy?.forwardBufferDuration, DirectPlaySessionPolicy.steadyStateForwardBufferSeconds)
        XCTAssertGreaterThanOrEqual(policy?.forwardBufferDuration ?? 0, 30)
    }

    func testLocalGatewayLoopbackDirectPlayStillGetsStabilityBiasedBuffer() {
        // The cache gateway serves a loopback URL, which would otherwise be classified as
        // "directLocal" and given the thinnest (0.75 s) buffer — even though the bytes are
        // actually streamed from a remote server through the proxy. It must be robust too.
        let policy = DirectPlaySessionPolicy.steadyStateBuffering(
            route: directPlay("http://127.0.0.1:52344/media/abc.mp4"),
            source: nil,
            currentForwardBufferDuration: 0.75,
            isTVOS: false
        )
        XCTAssertEqual(policy?.waitsToMinimizeStalling, true)
        XCTAssertGreaterThanOrEqual(policy?.forwardBufferDuration ?? 0, 30)
    }

    func testKeepsLargerExistingForwardBuffer() {
        let policy = DirectPlaySessionPolicy.steadyStateBuffering(
            route: directPlay("https://jellyfin.example.com/Videos/item/stream.mov?static=true"),
            source: nil,
            currentForwardBufferDuration: 90,
            isTVOS: false
        )
        XCTAssertEqual(policy?.forwardBufferDuration, 90)
    }

    func testHLSDirectPlayIsNotOverridden() {
        XCTAssertNil(DirectPlaySessionPolicy.steadyStateBuffering(
            route: directPlay("https://jellyfin.example.com/Videos/item/master.m3u8"),
            source: nil,
            currentForwardBufferDuration: 2,
            isTVOS: false
        ))
    }

    func testNonDirectPlayRouteIsNotOverridden() {
        XCTAssertNil(DirectPlaySessionPolicy.steadyStateBuffering(
            route: .transcode(URL(string: "https://jellyfin.example.com/Videos/item/master.m3u8")!),
            source: nil,
            currentForwardBufferDuration: 2,
            isTVOS: false
        ))
    }

    func testTVOSAlsoGetsStabilityBiasedBuffer() {
        // Shared player base: tvOS must get the same anti-stall steady-state buffer as iOS
        // (its adaptive-caching ramp then grows it further, cooperatively via max()).
        let policy = DirectPlaySessionPolicy.steadyStateBuffering(
            route: directPlay("https://jellyfin.example.com/Videos/item/stream.mp4?static=true"),
            source: nil,
            currentForwardBufferDuration: 4,
            isTVOS: true
        )
        XCTAssertEqual(policy?.waitsToMinimizeStalling, true)
        XCTAssertGreaterThanOrEqual(policy?.forwardBufferDuration ?? 0, 30)
    }

    func testHLSIsNotOverriddenOnTVOSEither() {
        XCTAssertNil(DirectPlaySessionPolicy.steadyStateBuffering(
            route: directPlay("https://jellyfin.example.com/Videos/item/master.m3u8"),
            source: nil,
            currentForwardBufferDuration: 4,
            isTVOS: true
        ))
    }
}
