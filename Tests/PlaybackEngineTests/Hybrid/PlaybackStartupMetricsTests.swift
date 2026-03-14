import XCTest
@testable import PlaybackEngine

@MainActor
final class PlaybackStartupMetricsTests: XCTestCase {

    func testMetricsCollector_recordsTimings() async throws {
        let collector = StartupMetricsCollector()

        collector.markTap()
        // Simulate small delay
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        collector.markDecision(engine: .native, reason: "nativePreferred")
        try await Task.sleep(nanoseconds: 10_000_000)
        collector.markPlayerSetup()
        try await Task.sleep(nanoseconds: 10_000_000)
        collector.markFirstFrame()

        let snapshot = collector.snapshot()
        XCTAssertNotNil(snapshot.tapToDecisionMs)
        XCTAssertNotNil(snapshot.decisionToPlayerSetupMs)
        XCTAssertNotNil(snapshot.playerSetupToFirstFrameMs)
        XCTAssertNotNil(snapshot.tapToFirstFrameMs)
        XCTAssertEqual(snapshot.selectedEngine, .native)
        XCTAssertFalse(snapshot.fallbackOccurred)
        XCTAssertEqual(snapshot.engineDecisionReason, "nativePreferred")
    }

    func testMetricsCollector_recordsFallback() {
        let collector = StartupMetricsCollector()
        collector.markTap()
        collector.markDecision(engine: .native, reason: "nativeThenFallbackIfStartupFails")
        collector.markFallback(reason: "AVPlayer startup timeout")
        collector.markRetry()

        let snapshot = collector.snapshot()
        XCTAssertTrue(snapshot.fallbackOccurred)
        XCTAssertEqual(snapshot.fallbackReason, "AVPlayer startup timeout")
        XCTAssertEqual(snapshot.startupRetryCount, 1)
    }

    func testMetricsCollector_recordsBufferingEvents() {
        let collector = StartupMetricsCollector()
        collector.markBufferingEvent()
        collector.markBufferingEvent()
        collector.markBufferingEvent()

        let snapshot = collector.snapshot()
        XCTAssertEqual(snapshot.bufferingEventsBeforeFirstFrame, 3)
    }

    func testMetricsCollector_reset() {
        let collector = StartupMetricsCollector()
        collector.markTap()
        collector.markDecision(engine: .vlc, reason: "vlcRequired")
        collector.markFallback(reason: "test")
        collector.markRetry()
        collector.markBufferingEvent()

        collector.reset()
        let snapshot = collector.snapshot()
        XCTAssertNil(snapshot.tapToDecisionMs)
        XCTAssertNil(snapshot.selectedEngine)
        XCTAssertFalse(snapshot.fallbackOccurred)
        XCTAssertEqual(snapshot.startupRetryCount, 0)
        XCTAssertEqual(snapshot.bufferingEventsBeforeFirstFrame, 0)
    }

    func testMetricsSnapshot_defaultValues() {
        let snapshot = PlaybackStartupMetrics()
        XCTAssertNil(snapshot.tapToFirstFrameMs)
        XCTAssertNil(snapshot.selectedEngine)
        XCTAssertFalse(snapshot.fallbackOccurred)
        XCTAssertNil(snapshot.fallbackReason)
        XCTAssertEqual(snapshot.startupRetryCount, 0)
        XCTAssertEqual(snapshot.bufferingEventsBeforeFirstFrame, 0)
    }

    func testMetricsSnapshot_equatable() {
        let a = PlaybackStartupMetrics(selectedEngine: .native, fallbackOccurred: false)
        let b = PlaybackStartupMetrics(selectedEngine: .native, fallbackOccurred: false)
        XCTAssertEqual(a, b)

        let c = PlaybackStartupMetrics(selectedEngine: .vlc, fallbackOccurred: true)
        XCTAssertNotEqual(a, c)
    }
}
