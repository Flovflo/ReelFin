import Foundation

/// Last-resort lane brain — pure, deterministic, fully unit-testable. Decides when the player may
/// leave the ORIGINAL (DV/HDR) for the clean SDR fallback stream, and when to come back.
///
/// Philosophy (blueprint R1/R5, user-confirmed): the original is sacred. Dropping requires a
/// PROVEN, SUSTAINED inability — the link measured below the file's own bitrate long enough
/// (`dropSustainedBelowSeconds`) AND playback actually starved (buffering) despite the deep disk
/// reservoir. A dip, a stall, a slow start never drop. Returning is generous but hysteretic: held
/// headroom + a rebuilt DV reservoir, with anti-flap dwell/cooldown and a lock after repeated
/// failed upgrades (twice back-to-SDR quickly → stay SDR for the rest of the title).
enum AdaptiveLanePolicy {
    enum Lane: Equatable { case original, sdrFallback }
    enum LaneChange: Equatable { case dropToSDR, returnToOriginal }

    struct State: Equatable {
        var lane: Lane = .original
        /// Continuous time the measured headroom has held ≥ `upgradeHeadroom` while in SDR.
        var headroomOKSince: Date?
        var lastDropAt: Date?
        var lastReturnAt: Date?
        var failedUpgrades: Int = 0
        var lockedToSDR: Bool = false
        init() {}
    }

    /// Sustained below-bitrate time (with starvation) before the drop. Mirrors
    /// `PlaybackLanePolicy.lastResortSustainedSeconds`.
    static let dropSustainedBelowSeconds: Double = PlaybackLanePolicy.lastResortSustainedSeconds
    /// Headroom the link must HOLD to earn the original back.
    static let upgradeHeadroom: Double = 1.3
    static let upgradeHoldSeconds: Double = 30
    /// DV disk reservoir required at the current position before swapping back (no blind swap).
    static let upgradeMinReservoirSeconds: Double = 30
    /// Minimum dwell in SDR before any upgrade attempt (anti-flap).
    static let sdrMinDwellSeconds: Double = 60
    /// A drop this soon after a return counts as a FAILED upgrade.
    static let failedUpgradeWindowSeconds: Double = 120
    static let maxFailedUpgrades: Int = 2

    /// One evaluation per monitor tick. Mutates `state` bookkeeping; returns the change to apply.
    static func decision(
        now: Date,
        isBuffering: Bool,
        sustainedBelowBitrateSeconds: Double,
        headroom: Double,
        dvReservoirSeconds: Double,
        state: inout State
    ) -> LaneChange? {
        switch state.lane {
        case .original:
            guard isBuffering, sustainedBelowBitrateSeconds >= dropSustainedBelowSeconds else { return nil }
            // Relapsing right after an upgrade = that upgrade failed; two failures lock SDR.
            if let lastReturn = state.lastReturnAt, now.timeIntervalSince(lastReturn) <= failedUpgradeWindowSeconds {
                state.failedUpgrades += 1
                if state.failedUpgrades >= maxFailedUpgrades {
                    state.lockedToSDR = true
                }
            }
            state.lane = .sdrFallback
            state.lastDropAt = now
            state.headroomOKSince = nil
            return .dropToSDR

        case .sdrFallback:
            guard !state.lockedToSDR else { return nil }
            if headroom >= upgradeHeadroom {
                if state.headroomOKSince == nil { state.headroomOKSince = now }
            } else {
                state.headroomOKSince = nil
            }
            guard let okSince = state.headroomOKSince,
                  now.timeIntervalSince(okSince) >= upgradeHoldSeconds,
                  dvReservoirSeconds >= upgradeMinReservoirSeconds,
                  let droppedAt = state.lastDropAt,
                  now.timeIntervalSince(droppedAt) >= sdrMinDwellSeconds
            else { return nil }
            state.lane = .original
            state.lastReturnAt = now
            state.headroomOKSince = nil
            return .returnToOriginal
        }
    }
}
