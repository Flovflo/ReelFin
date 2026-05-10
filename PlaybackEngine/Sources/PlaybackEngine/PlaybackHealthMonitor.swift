import Foundation

public enum PlaybackHealthState: String, Codable, Sendable, Equatable {
    case healthy
    case startupSlow
    case buffering
    case repeatedStalls
    case bandwidthLikelyInsufficient
    case routeFailed
}

public struct PlaybackHealthSnapshot: Codable, Sendable, Equatable {
    public let state: PlaybackHealthState
    public let stallCount: Int
    public let observedBitrate: Int?
    public let requiredBitrate: Int?
    public let safetyRatio: Double?
    public let recentStallTimestamps: [Date]

    public init(
        state: PlaybackHealthState = .healthy,
        stallCount: Int = 0,
        observedBitrate: Int? = nil,
        requiredBitrate: Int? = nil,
        safetyRatio: Double? = nil,
        recentStallTimestamps: [Date] = []
    ) {
        self.state = state
        self.stallCount = stallCount
        self.observedBitrate = observedBitrate
        self.requiredBitrate = requiredBitrate
        self.safetyRatio = safetyRatio
        self.recentStallTimestamps = recentStallTimestamps
    }
}

public struct PlaybackHealthMonitor: Sendable {
    private let stallWindowSeconds: TimeInterval
    private let repeatedStallThreshold: Int
    private let safetyMultiplier: Double
    private let insufficientRatioThreshold: Double
    private var stallTimestamps: [Date] = []
    private var latestObservedBitrate: Int?
    private var latestRequiredBitrate: Int?
    private var latestSafetyRatio: Double?
    private var state: PlaybackHealthState = .healthy

    public init(
        stallWindowSeconds: TimeInterval = 120,
        repeatedStallThreshold: Int = 2,
        safetyMultiplier: Double = 1.5,
        insufficientRatioThreshold: Double = 1.0
    ) {
        self.stallWindowSeconds = stallWindowSeconds
        self.repeatedStallThreshold = repeatedStallThreshold
        self.safetyMultiplier = safetyMultiplier
        self.insufficientRatioThreshold = insufficientRatioThreshold
    }

    public mutating func recordStall(at date: Date = Date()) -> PlaybackHealthSnapshot {
        stallTimestamps = stallTimestamps.filter { date.timeIntervalSince($0) <= stallWindowSeconds }
        stallTimestamps.append(date)
        if stallTimestamps.count >= repeatedStallThreshold {
            state = .repeatedStalls
        } else if state == .healthy {
            state = .buffering
        }
        return snapshot()
    }

    public mutating func recordBitrate(
        observedBitrate: Int?,
        mediaBitrate: Int?,
        at _: Date = Date()
    ) -> PlaybackHealthSnapshot {
        guard let observedBitrate, observedBitrate > 0 else { return snapshot() }
        latestObservedBitrate = observedBitrate
        if let mediaBitrate, mediaBitrate > 0 {
            latestRequiredBitrate = Int((Double(mediaBitrate) * safetyMultiplier).rounded())
            latestSafetyRatio = Double(observedBitrate) / Double(latestRequiredBitrate ?? mediaBitrate)
            if let ratio = latestSafetyRatio, ratio < insufficientRatioThreshold {
                state = .bandwidthLikelyInsufficient
            }
        }
        return snapshot()
    }

    public mutating func recordStartup(firstFrameMs: Double, thresholdMs: Double = 2_500) -> PlaybackHealthSnapshot {
        if firstFrameMs > thresholdMs, state == .healthy {
            state = .startupSlow
        }
        return snapshot()
    }

    public mutating func markRouteFailed() -> PlaybackHealthSnapshot {
        state = .routeFailed
        return snapshot()
    }

    public func snapshot() -> PlaybackHealthSnapshot {
        PlaybackHealthSnapshot(
            state: state,
            stallCount: stallTimestamps.count,
            observedBitrate: latestObservedBitrate,
            requiredBitrate: latestRequiredBitrate,
            safetyRatio: latestSafetyRatio,
            recentStallTimestamps: stallTimestamps
        )
    }
}
