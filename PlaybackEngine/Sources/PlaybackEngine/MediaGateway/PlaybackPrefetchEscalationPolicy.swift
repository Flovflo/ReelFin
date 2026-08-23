import Foundation

/// Decides when sustained weak streaming throughput should trigger an immediate,
/// deeper gateway prefetch re-anchor ahead of the playback position.
///
/// The steady-state prefetch schedule assumes throughput comfortably exceeds the
/// source bitrate. When delivered throughput approaches the required bitrate,
/// the ahead cache stops growing and app-side renderers drain toward an audible
/// underrun. This policy watches rolling delivery samples and escalates early —
/// telemetry and prefetch only, never playback pauses.
public struct PlaybackPrefetchEscalationPolicy: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case none
        case escalate(reason: String)
    }

    public var headroomFactor: Double
    public var weakSamplesToEscalate: Int
    public var minimumIntervalSeconds: TimeInterval
    private var consecutiveWeakSamples = 0
    private var lastEscalationUptime: TimeInterval?

    public init(
        headroomFactor: Double = 1.5,
        weakSamplesToEscalate: Int = 2,
        minimumIntervalSeconds: TimeInterval = 10
    ) {
        self.headroomFactor = headroomFactor
        self.weakSamplesToEscalate = max(1, weakSamplesToEscalate)
        self.minimumIntervalSeconds = max(0, minimumIntervalSeconds)
    }

    /// Rolling state carried across streaming chunk deliveries.
    public struct State: Equatable, Sendable {
        public var consecutiveWeakSamples = 0
        public var lastEscalationUptime: TimeInterval?

        public init(
            consecutiveWeakSamples: Int = 0,
            lastEscalationUptime: TimeInterval? = nil
        ) {
            self.consecutiveWeakSamples = max(0, consecutiveWeakSamples)
            self.lastEscalationUptime = lastEscalationUptime
        }
    }

    /// Records one delivered chunk sample and returns the next state plus action.
    ///
    /// - Parameters:
    ///   - deliveredBitrateBps: bitrate observed for this chunk delivery.
    ///   - requiredBitrateBps: source bitrate that realtime playback must sustain.
    ///   - now: monotonic uptime used for debouncing.
    public mutating func record(
        deliveredBitrateBps: Int,
        requiredBitrateBps: Int,
        now: TimeInterval
    ) -> (state: State, action: Action) {
        guard requiredBitrateBps > 0 else { return (self.snapshotState(), .none) }
        // A zero-byte/zero-throughput delivery can be a legitimate connection stall;
        // treat it as weak evidence like any other slow sample.
        let requiredWithHeadroom = Double(requiredBitrateBps) * headroomFactor
        if Double(max(deliveredBitrateBps, 0)) >= requiredWithHeadroom {
            consecutiveWeakSamples = 0
            return (self.snapshotState(), .none)
        }
        consecutiveWeakSamples += 1
        guard consecutiveWeakSamples >= weakSamplesToEscalate else {
            return (self.snapshotState(), .none)
        }
        if let lastEscalationUptime, now - lastEscalationUptime < minimumIntervalSeconds {
            return (self.snapshotState(), .none)
        }
        consecutiveWeakSamples = 0
        lastEscalationUptime = now
        return (
            self.snapshotState(),
            .escalate(reason: "throughput_below_headroom delivered=\(deliveredBitrateBps) required=\(requiredBitrateBps)")
        )
    }

    private func snapshotState() -> State {
        State(
            consecutiveWeakSamples: consecutiveWeakSamples,
            lastEscalationUptime: lastEscalationUptime
        )
    }
}
