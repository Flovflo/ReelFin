import Foundation
import XCTest
@testable import PlaybackEngine

final class PlaybackMediaCachePolicyTests: XCTestCase {
    func testTVOSGoodHeadroomPromotesToCompleteItemCaching() {
        let decision = PlaybackMediaCachePolicy.decision(
            context: PlaybackMediaCachePolicy.Context(
                platform: .tvOS,
                mediaCacheMode: .automatic,
                routeKind: .directPlayOriginal,
                sourceBitrate: 20_000_000,
                observedBitrate: 60_000_000,
                currentBufferDuration: 300,
                playbackElapsedSeconds: 420,
                remainingDuration: 3_600,
                isExpensiveNetwork: false,
                isConstrainedNetwork: false,
                availableDiskBytes: 80 * 1_024 * 1_024 * 1_024,
                activeItemCachedBytes: 900 * 1_024 * 1_024
            )
        )

        XCTAssertEqual(decision.phase, .complete)
        XCTAssertTrue(decision.allowCompleteItem)
        XCTAssertEqual(decision.targetAheadSeconds, 3_600)
        XCTAssertGreaterThanOrEqual(decision.prefetchConcurrency, 3)
    }

    func testIOSCellularLowDataDoesNotEnterDeepOrCompleteCache() {
        let decision = PlaybackMediaCachePolicy.decision(
            context: PlaybackMediaCachePolicy.Context(
                platform: .iOS,
                mediaCacheMode: .automatic,
                routeKind: .directPlayOriginal,
                sourceBitrate: 18_000_000,
                observedBitrate: 90_000_000,
                currentBufferDuration: 45,
                playbackElapsedSeconds: 600,
                remainingDuration: 5_000,
                isExpensiveNetwork: true,
                isConstrainedNetwork: true,
                availableDiskBytes: 90 * 1_024 * 1_024 * 1_024,
                activeItemCachedBytes: 0
            )
        )

        XCTAssertEqual(decision.phase, .steady)
        XCTAssertFalse(decision.allowCompleteItem)
        XCTAssertLessThanOrEqual(decision.targetAheadSeconds, 120)
    }

    func testLowStoragePausesPrefetchButKeepsPlaybackRequestsEligible() {
        let decision = PlaybackMediaCachePolicy.decision(
            context: PlaybackMediaCachePolicy.Context(
                platform: .tvOS,
                mediaCacheMode: .automatic,
                routeKind: .directPlayOriginal,
                sourceBitrate: 12_000_000,
                observedBitrate: 80_000_000,
                currentBufferDuration: 180,
                playbackElapsedSeconds: 700,
                remainingDuration: 3_000,
                isExpensiveNetwork: false,
                isConstrainedNetwork: false,
                availableDiskBytes: 160 * 1_024 * 1_024,
                activeItemCachedBytes: 50 * 1_024 * 1_024
            )
        )

        XCTAssertEqual(decision.phase, .paused)
        XCTAssertEqual(decision.prefetchConcurrency, 0)
        XCTAssertEqual(decision.targetAheadSeconds, 0)
        XCTAssertEqual(decision.reason, "low_storage")
    }

    func testOffModeDisablesSpeculativeMediaCache() {
        let decision = PlaybackMediaCachePolicy.decision(
            context: PlaybackMediaCachePolicy.Context(
                platform: .tvOS,
                mediaCacheMode: .off,
                routeKind: .directPlayOriginal,
                sourceBitrate: 12_000_000,
                observedBitrate: 80_000_000,
                currentBufferDuration: 0,
                playbackElapsedSeconds: 700,
                remainingDuration: 3_000,
                isExpensiveNetwork: false,
                isConstrainedNetwork: false,
                availableDiskBytes: 80 * 1_024 * 1_024 * 1_024,
                activeItemCachedBytes: 0
            )
        )

        XCTAssertEqual(decision.phase, .paused)
        XCTAssertEqual(decision.reason, "cache_mode_off")
    }
}
