import Foundation

/// Single source of truth for measured link throughput and — crucially — how long the link has
/// *sustainably* failed to carry the current file. Feeds `PlaybackLanePolicy` (blueprint §0-R5:
/// SDR is decided over TIME, never on a dip). Deterministic: callers inject timestamps, so it is
/// fully unit-testable offline.
///
/// "Below bitrate" is judged on the WINDOWED average (not a single noisy sample), and the
/// sustained-below timer only resets when the windowed average actually recovers to/above the
/// file's bitrate — so a brief blip inside an otherwise-too-slow window does not pretend the link
/// recovered.
public struct ConnectionMonitor: Sendable {
    public let sourceBitrateMbps: Double
    public let window: TimeInterval

    private var samples: [(t: Date, mbps: Double)] = []
    private var belowSince: Date?

    public init(sourceBitrateMbps: Double, window: TimeInterval = 10) {
        self.sourceBitrateMbps = max(0.001, sourceBitrateMbps)
        self.window = window
    }

    /// Record a throughput sample (Mbps) measured from the real keep-alive download session.
    public mutating func record(mbps: Double, at now: Date) {
        samples.append((now, max(0, mbps)))
        prune(before: now.addingTimeInterval(-window))
        updateSustained(now: now)
    }

    /// Recompute time-based state without a new sample (e.g. while idle/paused) so a stall during
    /// idle is still accounted for — the windowed average decays as old samples age out.
    public mutating func tick(now: Date) {
        prune(before: now.addingTimeInterval(-window))
        updateSustained(now: now)
    }

    /// Average measured throughput over the window. Zero if no recent samples.
    public func sustainedMbps(now: Date) -> Double {
        let recent = samples.filter { $0.t >= now.addingTimeInterval(-window) }
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0) { $0 + $1.mbps } / Double(recent.count)
    }

    public func headroom(now: Date) -> Double {
        sustainedMbps(now: now) / sourceBitrateMbps
    }

    /// Continuous seconds the windowed average has stayed below the file's own bitrate. 0 when the
    /// link is keeping up. This is the input that lets the policy fall back to SDR only after a
    /// genuine, sustained inability — never on a momentary dip.
    public func sustainedBelowBitrateSeconds(now: Date) -> Double {
        guard let belowSince else { return 0 }
        return max(0, now.timeIntervalSince(belowSince))
    }

    // MARK: - Private

    private mutating func prune(before cutoff: Date) {
        samples.removeAll { $0.t < cutoff }
    }

    private mutating func updateSustained(now: Date) {
        // No data yet -> not a verdict; don't start the sustained timer on emptiness alone.
        guard !samples.isEmpty else { return }
        let avg = sustainedMbps(now: now)
        if avg < sourceBitrateMbps {
            if belowSince == nil { belowSince = now }
        } else {
            belowSince = nil
        }
    }
}
