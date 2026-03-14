import Foundation

// MARK: - Startup Metrics

/// Tracks timing for every phase of playback startup.
/// All values are in milliseconds.
public struct PlaybackStartupMetrics: Sendable, Equatable {
    public var tapToDecisionMs: Double?
    public var decisionToPlayerSetupMs: Double?
    public var playerSetupToFirstFrameMs: Double?
    public var tapToFirstFrameMs: Double?
    public var bufferingEventsBeforeFirstFrame: Int
    public var startupRetryCount: Int
    public var selectedEngine: PlaybackEngineType?
    public var fallbackOccurred: Bool
    public var fallbackReason: String?
    public var engineDecisionReason: String?

    public init(
        tapToDecisionMs: Double? = nil,
        decisionToPlayerSetupMs: Double? = nil,
        playerSetupToFirstFrameMs: Double? = nil,
        tapToFirstFrameMs: Double? = nil,
        bufferingEventsBeforeFirstFrame: Int = 0,
        startupRetryCount: Int = 0,
        selectedEngine: PlaybackEngineType? = nil,
        fallbackOccurred: Bool = false,
        fallbackReason: String? = nil,
        engineDecisionReason: String? = nil
    ) {
        self.tapToDecisionMs = tapToDecisionMs
        self.decisionToPlayerSetupMs = decisionToPlayerSetupMs
        self.playerSetupToFirstFrameMs = playerSetupToFirstFrameMs
        self.tapToFirstFrameMs = tapToFirstFrameMs
        self.bufferingEventsBeforeFirstFrame = bufferingEventsBeforeFirstFrame
        self.startupRetryCount = startupRetryCount
        self.selectedEngine = selectedEngine
        self.fallbackOccurred = fallbackOccurred
        self.fallbackReason = fallbackReason
        self.engineDecisionReason = engineDecisionReason
    }
}

// MARK: - Metrics Collector

/// Collects timing data during playback startup.
@MainActor
public final class StartupMetricsCollector {
    private var tapTime: Date?
    private var decisionTime: Date?
    private var playerSetupTime: Date?
    private var firstFrameTime: Date?
    private var bufferingEvents = 0
    private var retryCount = 0
    private var engine: PlaybackEngineType?
    private var didFallback = false
    private var fallbackReason: String?
    private var decisionReason: String?

    public init() {}

    public func markTap() { tapTime = Date() }
    public func markDecision(engine: PlaybackEngineType, reason: String) {
        decisionTime = Date()
        self.engine = engine
        self.decisionReason = reason
    }
    public func markPlayerSetup() { playerSetupTime = Date() }
    public func markFirstFrame() { firstFrameTime = Date() }
    public func markBufferingEvent() { bufferingEvents += 1 }
    public func markRetry() { retryCount += 1 }
    public func markFallback(reason: String) {
        didFallback = true
        fallbackReason = reason
    }

    public func snapshot() -> PlaybackStartupMetrics {
        let tapMs = tapTime.map { t in decisionTime.map { $0.timeIntervalSince(t) * 1000 } ?? nil } ?? nil
        let decisionMs = decisionTime.map { t in playerSetupTime.map { $0.timeIntervalSince(t) * 1000 } ?? nil } ?? nil
        let setupMs = playerSetupTime.map { t in firstFrameTime.map { $0.timeIntervalSince(t) * 1000 } ?? nil } ?? nil
        let totalMs = tapTime.map { t in firstFrameTime.map { $0.timeIntervalSince(t) * 1000 } ?? nil } ?? nil

        return PlaybackStartupMetrics(
            tapToDecisionMs: tapMs,
            decisionToPlayerSetupMs: decisionMs,
            playerSetupToFirstFrameMs: setupMs,
            tapToFirstFrameMs: totalMs,
            bufferingEventsBeforeFirstFrame: bufferingEvents,
            startupRetryCount: retryCount,
            selectedEngine: engine,
            fallbackOccurred: didFallback,
            fallbackReason: fallbackReason,
            engineDecisionReason: decisionReason
        )
    }

    public func reset() {
        tapTime = nil
        decisionTime = nil
        playerSetupTime = nil
        firstFrameTime = nil
        bufferingEvents = 0
        retryCount = 0
        engine = nil
        didFallback = false
        fallbackReason = nil
        decisionReason = nil
    }
}
