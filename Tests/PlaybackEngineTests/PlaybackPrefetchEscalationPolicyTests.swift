import Foundation
import XCTest
@testable import PlaybackEngine

final class PlaybackPrefetchEscalationPolicyTests: XCTestCase {
    func testStrongThroughputNeverEscalates() {
        var policy = PlaybackPrefetchEscalationPolicy()
        var state = PlaybackPrefetchEscalationPolicy.State()

        for tick in 0..<10 {
            let (nextState, action) = policy.record(
                deliveredBitrateBps: 30_000_000,
                requiredBitrateBps: 20_000_000,
                now: TimeInterval(tick)
            )
            state = nextState
            XCTAssertEqual(action, .none)
        }
        XCTAssertEqual(state.consecutiveWeakSamples, 0)
        XCTAssertNil(state.lastEscalationUptime)
    }

    func testSingleWeakSampleDoesNotEscalate() {
        var policy = PlaybackPrefetchEscalationPolicy()
        var state = PlaybackPrefetchEscalationPolicy.State()

        let (nextState, action) = policy.record(
            deliveredBitrateBps: 10_000_000,
            requiredBitrateBps: 20_000_000,
            now: 100
        )
        state = nextState
        XCTAssertEqual(action, .none)
        XCTAssertEqual(state.consecutiveWeakSamples, 1)
    }

    func testConsecutiveWeakSamplesEscalateOnce() {
        var policy = PlaybackPrefetchEscalationPolicy()
        var state = PlaybackPrefetchEscalationPolicy.State()

        let first = policy.record(
            deliveredBitrateBps: 10_000_000,
            requiredBitrateBps: 20_000_000,
            now: 100
        )
        state = first.state
        XCTAssertEqual(first.action, .none)

        let second = policy.record(
            deliveredBitrateBps: 10_000_000,
            requiredBitrateBps: 20_000_000,
            now: 101
        )
        state = second.state
        guard case .escalate = second.action else {
            return XCTFail("Expected escalation after two consecutive weak samples")
        }
        XCTAssertEqual(state.consecutiveWeakSamples, 0)
        XCTAssertEqual(state.lastEscalationUptime, 101)
    }

    func testStrongSampleResetsWeakStreak() {
        var policy = PlaybackPrefetchEscalationPolicy()
        var state = PlaybackPrefetchEscalationPolicy.State()

        state = policy.record(
            deliveredBitrateBps: 10_000_000,
            requiredBitrateBps: 20_000_000,
            now: 100
        ).state
        state = policy.record(
            deliveredBitrateBps: 40_000_000,
            requiredBitrateBps: 20_000_000,
            now: 101
        ).state
        XCTAssertEqual(state.consecutiveWeakSamples, 0)

        let after = policy.record(
            deliveredBitrateBps: 10_000_000,
            requiredBitrateBps: 20_000_000,
            now: 102
        )
        XCTAssertEqual(after.action, .none, "A single weak sample after recovery must not escalate")
    }

    func testEscalationDebouncesWithinMinimumInterval() {
        var policy = PlaybackPrefetchEscalationPolicy(minimumIntervalSeconds: 10)
        var state = PlaybackPrefetchEscalationPolicy.State()

        state = policy.record(deliveredBitrateBps: 10_000_000, requiredBitrateBps: 20_000_000, now: 100).state
        let firstEscalation = policy.record(deliveredBitrateBps: 10_000_000, requiredBitrateBps: 20_000_000, now: 101)
        state = firstEscalation.state
        guard case .escalate = firstEscalation.action else {
            return XCTFail("Expected first escalation")
        }

        // Second burst arrives 5s later — inside the debounce window.
        state = policy.record(deliveredBitrateBps: 10_000_000, requiredBitrateBps: 20_000_000, now: 106).state
        let suppressed = policy.record(deliveredBitrateBps: 10_000_000, requiredBitrateBps: 20_000_000, now: 107)
        state = suppressed.state
        XCTAssertEqual(suppressed.action, .none, "Escalation inside the debounce window must be suppressed")
        XCTAssertEqual(state.lastEscalationUptime, 101, "Suppressed escalation must not move the debounce anchor")

        // After the debounce window passes, the next weak burst escalates again.
        let later = policy.record(deliveredBitrateBps: 10_000_000, requiredBitrateBps: 20_000_000, now: 112)
        guard case .escalate = later.action else {
            return XCTFail("Expected escalation once the debounce window has elapsed")
        }
    }

    func testZeroRequiredBitrateNeverEscalates() {
        var policy = PlaybackPrefetchEscalationPolicy()

        for tick in 0..<5 {
            let (_, action) = policy.record(
                deliveredBitrateBps: 1,
                requiredBitrateBps: 0,
                now: TimeInterval(tick)
            )
            XCTAssertEqual(action, .none, "Unknown source bitrate must disable escalation")
        }
    }

    func testZeroDeliveredThroughputCountsAsWeak() {
        var policy = PlaybackPrefetchEscalationPolicy()

        let first = policy.record(deliveredBitrateBps: 0, requiredBitrateBps: 20_000_000, now: 100)
        XCTAssertEqual(first.action, .none)
        let second = policy.record(deliveredBitrateBps: 0, requiredBitrateBps: 20_000_000, now: 101)
        guard case .escalate = second.action else {
            return XCTFail("A stalled delivery must count toward escalation")
        }
    }
}
