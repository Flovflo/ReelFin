@testable import PlaybackEngine
import XCTest

/// Deterministic (injected time) — proves the connection monitor measures throughput and tracks a
/// SUSTAINED below-bitrate window correctly, so SDR fallback fires only on genuine sustained
/// failure (never a dip).
final class ConnectionMonitorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func t(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    func testSustainedMbpsAveragesRecentWindow() {
        var m = ConnectionMonitor(sourceBitrateMbps: 26, window: 10)
        m.record(mbps: 100, at: t(0))
        m.record(mbps: 50, at: t(1))
        XCTAssertEqual(m.sustainedMbps(now: t(1)), 75, accuracy: 0.01)
        XCTAssertGreaterThan(m.headroom(now: t(1)), 1)
    }

    func testHealthyLinkNeverAccumulatesBelowTime() {
        var m = ConnectionMonitor(sourceBitrateMbps: 26, window: 10)
        for i in 0..<10 { m.record(mbps: 60, at: t(Double(i))) }
        XCTAssertEqual(m.sustainedBelowBitrateSeconds(now: t(9)), 0)
    }

    func testSustainedBelowBitrateAccumulatesWhileBelow() {
        var m = ConnectionMonitor(sourceBitrateMbps: 26, window: 10)
        m.record(mbps: 10, at: t(0))           // below 26 -> belowSince = t0
        m.record(mbps: 12, at: t(5))           // still below
        XCTAssertEqual(m.sustainedBelowBitrateSeconds(now: t(5)), 5, accuracy: 0.01)
        m.tick(now: t(40))                      // time passes, samples age out, still below (avg 0)
        XCTAssertGreaterThanOrEqual(m.sustainedBelowBitrateSeconds(now: t(40)), 40 - 1)
    }

    func testRecoveryResetsBelowTimer() {
        var m = ConnectionMonitor(sourceBitrateMbps: 26, window: 10)
        m.record(mbps: 8, at: t(0))            // below
        XCTAssertGreaterThan(m.sustainedBelowBitrateSeconds(now: t(3)), 0)
        m.record(mbps: 200, at: t(3))          // burst recovers the windowed avg above bitrate
        XCTAssertEqual(m.sustainedBelowBitrateSeconds(now: t(3)), 0, "Recovery must reset the sustained-below timer.")
    }

    func testBriefBlipInsideSlowWindowDoesNotFakeRecovery() {
        var m = ConnectionMonitor(sourceBitrateMbps: 26, window: 10)
        m.record(mbps: 5, at: t(0))
        m.record(mbps: 5, at: t(1))
        m.record(mbps: 30, at: t(2))   // one decent sample, but window avg = (5+5+30)/3 = 13.3 < 26
        XCTAssertGreaterThan(m.sustainedBelowBitrateSeconds(now: t(2)), 0,
            "A single good sample inside an otherwise-slow window must NOT reset the sustained-below timer.")
    }
}
