import Foundation
import XCTest
@testable import PlaybackEngine

final class PlaybackTVOSCachingPolicyTests: XCTestCase {
    func testStartupBufferingHintDisabledOutsideTvOS() {
        let hint = PlaybackTVOSCachingPolicy.startupBufferingHint(
            defaultForwardBufferDuration: 6,
            defaultWaitsToMinimizeStalling: false,
            route: .directPlay(URL(string: "https://example.com/video.mp4")!),
            sourceBitrate: 18_000_000,
            isPremiumSource: true,
            runtimeSeconds: 7_200,
            isTVOS: false
        )

        XCTAssertNil(hint)
    }

    func testStartupBufferingHintPrefersLargePremiumDirectPlayBufferOnTvOS() {
        let hint = PlaybackTVOSCachingPolicy.startupBufferingHint(
            defaultForwardBufferDuration: 2,
            defaultWaitsToMinimizeStalling: false,
            route: .directPlay(URL(string: "https://example.com/video.mp4")!),
            sourceBitrate: 24_000_000,
            isPremiumSource: true,
            runtimeSeconds: 7_200,
            isTVOS: true
        )

        XCTAssertEqual(hint?.forwardBufferDuration, 30)
        XCTAssertEqual(hint?.minimumStartupBufferDuration, 8)
        XCTAssertEqual(hint?.preferredStartupBufferDuration, 18)
        XCTAssertEqual(hint?.startupTimeout, 6.5)
        XCTAssertTrue(hint?.waitsToMinimizeStalling ?? false)
        XCTAssertEqual(hint?.syntheticPreloadCount, 14)
        XCTAssertEqual(hint?.syntheticLookaheadSegments, 10)
    }

    func testStartupBufferingHintClampsToShortRuntime() {
        let hint = PlaybackTVOSCachingPolicy.startupBufferingHint(
            defaultForwardBufferDuration: 6,
            defaultWaitsToMinimizeStalling: false,
            route: .transcode(URL(string: "https://example.com/master.m3u8")!),
            sourceBitrate: 8_000_000,
            isPremiumSource: false,
            runtimeSeconds: 9,
            isTVOS: true
        )

        XCTAssertEqual(hint?.forwardBufferDuration, 9)
        XCTAssertEqual(hint?.minimumStartupBufferDuration, 5)
        XCTAssertEqual(hint?.preferredStartupBufferDuration, 9)
    }

    func testShouldStartPlaybackWhenPreferredBufferReached() {
        let hint = PlaybackTVOSCachingPolicy.StartupBufferingHint(
            forwardBufferDuration: 18,
            waitsToMinimizeStalling: true,
            minimumStartupBufferDuration: 6,
            preferredStartupBufferDuration: 12,
            startupTimeout: 5,
            fastGrowthRateThreshold: 1.8,
            syntheticPreloadCount: 12,
            syntheticLookaheadSegments: 8,
            reason: "test"
        )

        XCTAssertTrue(
            PlaybackTVOSCachingPolicy.shouldStartPlayback(
                bufferedDuration: 12,
                growthRate: 0.4,
                likelyToKeepUp: false,
                hint: hint
            )
        )
    }

    func testShouldStartPlaybackAllowsEarlyStartForFastGrowingBuffer() {
        let hint = PlaybackTVOSCachingPolicy.StartupBufferingHint(
            forwardBufferDuration: 18,
            waitsToMinimizeStalling: true,
            minimumStartupBufferDuration: 6,
            preferredStartupBufferDuration: 12,
            startupTimeout: 5,
            fastGrowthRateThreshold: 1.8,
            syntheticPreloadCount: 12,
            syntheticLookaheadSegments: 8,
            reason: "test"
        )

        XCTAssertTrue(
            PlaybackTVOSCachingPolicy.shouldStartPlayback(
                bufferedDuration: 6.2,
                growthRate: 2.4,
                likelyToKeepUp: false,
                hint: hint
            )
        )
        XCTAssertFalse(
            PlaybackTVOSCachingPolicy.shouldStartPlayback(
                bufferedDuration: 6.2,
                growthRate: 0.6,
                likelyToKeepUp: false,
                hint: hint
            )
        )
    }

    func testStartupForwardBufferDurationKeepsTvOSStartupBufferModest() {
        let target = PlaybackTVOSCachingPolicy.startupForwardBufferDuration(
            baseBufferDuration: 6,
            route: .transcode(URL(string: "https://example.com/master.m3u8")!),
            runtimeSeconds: 7_200,
            isTVOS: true
        )

        XCTAssertEqual(target, 6)
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

    func testAdaptiveCachingHintEntersWarmPhaseAfterStartup() {
        let hint = PlaybackTVOSCachingPolicy.adaptiveCachingHint(
            currentBufferDuration: 6,
            observedBitrate: 20_000_000,
            indicatedBitrate: 12_000_000,
            sourceBitrate: 10_000_000,
            currentTime: 20,
            runtimeSeconds: 3_600,
            healthySampleCount: 1,
            isTVOS: true
        )

        XCTAssertEqual(hint?.phase, .warm)
        XCTAssertEqual(hint?.forwardBufferDuration, 24)
        XCTAssertEqual(hint?.syntheticPreloadCount, 6)
        XCTAssertEqual(hint?.syntheticLookaheadSegments, 4)
    }

    func testAdaptiveCachingHintPromotesToDeepPhaseAfterSustainedHeadroom() {
        let hint = PlaybackTVOSCachingPolicy.adaptiveCachingHint(
            currentBufferDuration: 90,
            observedBitrate: 28_000_000,
            indicatedBitrate: 12_000_000,
            sourceBitrate: 10_000_000,
            currentTime: 180,
            runtimeSeconds: 3_600,
            healthySampleCount: 6,
            isTVOS: true
        )

        XCTAssertEqual(hint?.phase, .deep)
        XCTAssertEqual(hint?.forwardBufferDuration, 300)
        XCTAssertEqual(hint?.syntheticPreloadCount, 14)
        XCTAssertEqual(hint?.syntheticLookaheadSegments, 8)
    }

    func testAdaptiveCachingHintIgnoresLowHeadroom() {
        let hint = PlaybackTVOSCachingPolicy.adaptiveCachingHint(
            currentBufferDuration: 24,
            observedBitrate: 13_000_000,
            indicatedBitrate: 12_000_000,
            sourceBitrate: 10_000_000,
            currentTime: 90,
            runtimeSeconds: 3_600,
            healthySampleCount: 3,
            isTVOS: true
        )

        XCTAssertNil(hint)
    }

    func testAdaptiveCachingHintStaysDisabledDuringStartupWindow() {
        let hint = PlaybackTVOSCachingPolicy.adaptiveCachingHint(
            currentBufferDuration: 6,
            observedBitrate: 30_000_000,
            indicatedBitrate: 12_000_000,
            sourceBitrate: 10_000_000,
            currentTime: 8,
            runtimeSeconds: 3_600,
            healthySampleCount: 1,
            isTVOS: true
        )

        XCTAssertNil(hint)
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
