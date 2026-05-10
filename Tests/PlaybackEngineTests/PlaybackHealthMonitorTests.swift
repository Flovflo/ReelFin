import PlaybackEngine
import XCTest

final class PlaybackHealthMonitorTests: XCTestCase {
    func testRepeatedStallsWithinWindowBecomesRepeatedStalls() {
        var monitor = PlaybackHealthMonitor(stallWindowSeconds: 120)
        let start = Date(timeIntervalSince1970: 100)

        _ = monitor.recordStall(at: start)
        let snapshot = monitor.recordStall(at: start.addingTimeInterval(60))

        XCTAssertEqual(snapshot.state, .repeatedStalls)
        XCTAssertEqual(snapshot.stallCount, 2)
    }

    func testSafetyRatioUsesObservedOverRequiredBitrate() {
        var monitor = PlaybackHealthMonitor(safetyMultiplier: 1.5)

        let snapshot = monitor.recordBitrate(
            observedBitrate: 90_000_000,
            mediaBitrate: 80_000_000,
            at: Date()
        )

        XCTAssertEqual(snapshot.requiredBitrate, 120_000_000)
        XCTAssertEqual(snapshot.safetyRatio ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(snapshot.state, .bandwidthLikelyInsufficient)
    }

    func testFallbackRecommendationForBandwidthDoesNotAutoDowngradeOriginalDV() {
        let guarantees = PlaybackRouteGuarantees(
            videoIntegrity: .originalBitstream,
            hdrIntegrity: .dolbyVision,
            startupClass: .remoteDirect,
            userVisibleSummary: "Direct Original",
            debugReason: "test"
        )
        let snapshot = PlaybackHealthSnapshot(
            state: .bandwidthLikelyInsufficient,
            stallCount: 2,
            observedBitrate: 70_000_000,
            requiredBitrate: 120_000_000,
            safetyRatio: 0.58,
            recentStallTimestamps: []
        )

        let recommendation = PlaybackFallbackRecommendationFactory.healthRecommendation(
            sourceDescription: "Original 4K Dolby Vision",
            routeGuarantees: guarantees,
            health: snapshot,
            mediaBitrate: 80_000_000
        )

        XCTAssertEqual(recommendation?.trigger, .bandwidthLikelyInsufficient)
        XCTAssertEqual(recommendation?.options.first?.kind, .keepOriginal)
        XCTAssertTrue(recommendation?.options.first?.preservesDolbyVision == true)
        XCTAssertTrue(recommendation?.options.contains(where: { $0.kind == .fullHD1080p && !$0.preservesOriginalVideo }) == true)
    }
}
