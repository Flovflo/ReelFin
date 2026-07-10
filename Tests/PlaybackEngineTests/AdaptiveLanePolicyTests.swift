import Foundation
import XCTest
@testable import PlaybackEngine

/// The last-resort lane brain, fully offline. Proves the ORIGINAL-FIRST discipline: a drop needs a
/// PROVEN sustained inability + real starvation; the way back is hysteretic and anti-flap; two
/// failed upgrades lock SDR for the title.
final class AdaptiveLanePolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testShortDipNeverDrops() {
        var state = AdaptiveLanePolicy.State()
        let change = AdaptiveLanePolicy.decision(
            now: t0, isBuffering: true, sustainedBelowBitrateSeconds: 30,
            headroom: 0.5, dvReservoirSeconds: 0, state: &state)
        XCTAssertNil(change)
        XCTAssertEqual(state.lane, .original)
    }

    func testSustainedBelowWithoutStarvationNeverDrops() {
        // The reservoir is absorbing it — motion never stopped, so the original stays.
        var state = AdaptiveLanePolicy.State()
        let change = AdaptiveLanePolicy.decision(
            now: t0, isBuffering: false, sustainedBelowBitrateSeconds: 600,
            headroom: 0.5, dvReservoirSeconds: 120, state: &state)
        XCTAssertNil(change)
    }

    func testDeepReservoirBlocksTheDrop() {
        // With minutes of original already on disk the title cannot starve for long — a buffering
        // signal there is a transient (serve hiccup / poisoned sample while the fill idles at its
        // cap), never link inability. Device 2026-07-08: SDR fired on a gigabit LAN with a ~240s
        // reservoir; this locks that class of false drop out.
        var state = AdaptiveLanePolicy.State()
        let change = AdaptiveLanePolicy.decision(
            now: t0, isBuffering: true,
            sustainedBelowBitrateSeconds: AdaptiveLanePolicy.dropSustainedBelowSeconds + 100,
            headroom: 0.5, dvReservoirSeconds: 240, state: &state)
        XCTAssertNil(change, "a deep reservoir must veto the SDR drop")
        XCTAssertEqual(state.lane, .original)
    }

    func testDropRequiresSustainedBelowAndBuffering() {
        var state = AdaptiveLanePolicy.State()
        let change = AdaptiveLanePolicy.decision(
            now: t0, isBuffering: true,
            sustainedBelowBitrateSeconds: AdaptiveLanePolicy.dropSustainedBelowSeconds,
            headroom: 0.5, dvReservoirSeconds: 0, state: &state)
        XCTAssertEqual(change, .dropToSDR)
        XCTAssertEqual(state.lane, .sdrFallback)
    }

    func testUpgradeRequiresHeldHeadroomReservoirAndDwell() {
        var state = AdaptiveLanePolicy.State()
        _ = AdaptiveLanePolicy.decision(
            now: t0, isBuffering: true,
            sustainedBelowBitrateSeconds: AdaptiveLanePolicy.dropSustainedBelowSeconds,
            headroom: 0.5, dvReservoirSeconds: 0, state: &state)

        // Headroom becomes great immediately, but the SDR dwell (60s) gates any return.
        var change = AdaptiveLanePolicy.decision(
            now: t0.addingTimeInterval(10), isBuffering: false, sustainedBelowBitrateSeconds: 0,
            headroom: 2.0, dvReservoirSeconds: 120, state: &state)
        XCTAssertNil(change, "no upgrade before the SDR dwell")

        // Past dwell but hold not yet satisfied from a fresh headroomOKSince? It was set at t0+10
        // and held since → at t0+61 the hold (30s) AND dwell (60s) are both satisfied…
        change = AdaptiveLanePolicy.decision(
            now: t0.addingTimeInterval(61), isBuffering: false, sustainedBelowBitrateSeconds: 0,
            headroom: 2.0, dvReservoirSeconds: 120, state: &state)
        XCTAssertEqual(change, .returnToOriginal)
        XCTAssertEqual(state.lane, .original)
    }

    func testUpgradeBlockedByThinDVReservoir() {
        var state = AdaptiveLanePolicy.State()
        _ = AdaptiveLanePolicy.decision(
            now: t0, isBuffering: true,
            sustainedBelowBitrateSeconds: AdaptiveLanePolicy.dropSustainedBelowSeconds,
            headroom: 0.5, dvReservoirSeconds: 0, state: &state)
        _ = AdaptiveLanePolicy.decision(
            now: t0.addingTimeInterval(10), isBuffering: false, sustainedBelowBitrateSeconds: 0,
            headroom: 2.0, dvReservoirSeconds: 120, state: &state)
        let change = AdaptiveLanePolicy.decision(
            now: t0.addingTimeInterval(120), isBuffering: false, sustainedBelowBitrateSeconds: 0,
            headroom: 2.0, dvReservoirSeconds: AdaptiveLanePolicy.upgradeMinReservoirSeconds - 1, state: &state)
        XCTAssertNil(change, "never swap back onto a thin DV reservoir")
    }

    func testHeadroomBlipResetsTheHold() {
        var state = AdaptiveLanePolicy.State()
        _ = AdaptiveLanePolicy.decision(
            now: t0, isBuffering: true,
            sustainedBelowBitrateSeconds: AdaptiveLanePolicy.dropSustainedBelowSeconds,
            headroom: 0.5, dvReservoirSeconds: 0, state: &state)
        _ = AdaptiveLanePolicy.decision(
            now: t0.addingTimeInterval(70), isBuffering: false, sustainedBelowBitrateSeconds: 0,
            headroom: 2.0, dvReservoirSeconds: 120, state: &state)
        // Blip below the bar resets the hold…
        _ = AdaptiveLanePolicy.decision(
            now: t0.addingTimeInterval(90), isBuffering: false, sustainedBelowBitrateSeconds: 0,
            headroom: 1.0, dvReservoirSeconds: 120, state: &state)
        // …so 20s later (total held only 20s from the new start) there is still no return.
        let change = AdaptiveLanePolicy.decision(
            now: t0.addingTimeInterval(110), isBuffering: false, sustainedBelowBitrateSeconds: 0,
            headroom: 2.0, dvReservoirSeconds: 120, state: &state)
        XCTAssertNil(change)
    }

    func testTwoQuickRelapsesLockSDRForTheTitle() {
        var state = AdaptiveLanePolicy.State()
        var now = t0

        func drop() {
            let change = AdaptiveLanePolicy.decision(
                now: now, isBuffering: true,
                sustainedBelowBitrateSeconds: AdaptiveLanePolicy.dropSustainedBelowSeconds,
                headroom: 0.5, dvReservoirSeconds: 0, state: &state)
            XCTAssertEqual(change, .dropToSDR)
        }
        func upgrade() {
            _ = AdaptiveLanePolicy.decision(
                now: now.addingTimeInterval(5), isBuffering: false, sustainedBelowBitrateSeconds: 0,
                headroom: 2.0, dvReservoirSeconds: 120, state: &state)
            now = now.addingTimeInterval(70)
            let change = AdaptiveLanePolicy.decision(
                now: now, isBuffering: false, sustainedBelowBitrateSeconds: 0,
                headroom: 2.0, dvReservoirSeconds: 120, state: &state)
            XCTAssertEqual(change, .returnToOriginal)
        }

        drop()          // 1st drop
        upgrade()       // 1st return
        now = now.addingTimeInterval(30) // relapse 30s later → failed upgrade #1
        drop()
        upgrade()       // 2nd return
        now = now.addingTimeInterval(30) // relapse again → failed upgrade #2 → LOCK
        drop()
        XCTAssertTrue(state.lockedToSDR)

        // Even with perfect conditions forever, no more upgrades this title.
        _ = AdaptiveLanePolicy.decision(
            now: now.addingTimeInterval(10), isBuffering: false, sustainedBelowBitrateSeconds: 0,
            headroom: 3.0, dvReservoirSeconds: 600, state: &state)
        let final = AdaptiveLanePolicy.decision(
            now: now.addingTimeInterval(600), isBuffering: false, sustainedBelowBitrateSeconds: 0,
            headroom: 3.0, dvReservoirSeconds: 600, state: &state)
        XCTAssertNil(final)
        XCTAssertEqual(state.lane, .sdrFallback)
    }
}
