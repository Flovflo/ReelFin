import Foundation
import XCTest
@testable import PlaybackEngine

final class PlaybackTVOSCachingPolicyTests: XCTestCase {
    func testStartupForwardBufferDurationUsesLargeTvOSFloor() {
        let target = PlaybackTVOSCachingPolicy.startupForwardBufferDuration(
            baseBufferDuration: 6,
            route: .transcode(URL(string: "https://example.com/master.m3u8")!),
            runtimeSeconds: 7_200,
            isTVOS: true
        )

        XCTAssertEqual(target, 240)
    }

    func testStartupForwardBufferDurationLeavesNonTvOSUnchanged() {
        let target = PlaybackTVOSCachingPolicy.startupForwardBufferDuration(
            baseBufferDuration: 6,
            route: .transcode(URL(string: "https://example.com/master.m3u8")!),
            runtimeSeconds: 7_200,
            isTVOS: false
        )

        XCTAssertEqual(target, 6)
    }

    func testAggressiveForwardBufferDurationExpandsToRemainingRuntimeWhenHeadroomIsHigh() {
        let target = PlaybackTVOSCachingPolicy.aggressiveForwardBufferDuration(
            currentBufferDuration: 240,
            observedBitrate: 30_000_000,
            indicatedBitrate: 12_000_000,
            sourceBitrate: 10_000_000,
            currentTime: 120,
            runtimeSeconds: 3_600,
            isTVOS: true
        )

        XCTAssertEqual(target, 3_480)
    }

    func testAggressiveForwardBufferDurationIgnoresLowHeadroom() {
        let target = PlaybackTVOSCachingPolicy.aggressiveForwardBufferDuration(
            currentBufferDuration: 240,
            observedBitrate: 13_000_000,
            indicatedBitrate: 12_000_000,
            sourceBitrate: 10_000_000,
            currentTime: 120,
            runtimeSeconds: 3_600,
            isTVOS: true
        )

        XCTAssertNil(target)
    }

    func testSyntheticReaderConfigurationOnlyGrowsOnTvOS() {
        let base = HTTPRangeReader.Configuration(
            chunkSize: 64 * 1024,
            maxCacheSize: 24 * 1024 * 1024,
            maxRetries: 4,
            baseRetryDelayMs: 150,
            timeoutInterval: 20,
            maxConcurrentRequests: 2,
            readAheadChunks: 0
        )

        let adjusted = PlaybackTVOSCachingPolicy.syntheticReaderConfiguration(base: base, isTVOS: true)

        XCTAssertEqual(adjusted.maxCacheSize, PlaybackTVOSCachingPolicy.syntheticReaderCacheSizeBytes)
        XCTAssertEqual(adjusted.readAheadChunks, PlaybackTVOSCachingPolicy.syntheticReadAheadChunks)
        XCTAssertEqual(adjusted.maxConcurrentRequests, 4)
    }
}
