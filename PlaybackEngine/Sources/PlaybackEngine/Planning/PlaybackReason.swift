import Foundation

public enum PlaybackDecisionStage: String, Sendable, Codable, CaseIterable {
    case probe
    case capability
    case laneSelection
    case audioSelection
    case subtitleSelection
    case hdrSelection
    case fallback
    case finalization
}

public enum PlaybackDecisionOutcome: String, Sendable, Codable {
    case accepted
    case rejected
    case downgraded
    case info
}

public struct PlanDecisionTrace: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let stage: PlaybackDecisionStage
    public let outcome: PlaybackDecisionOutcome
    public let code: String
    public let message: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        stage: PlaybackDecisionStage,
        outcome: PlaybackDecisionOutcome,
        code: String,
        message: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.stage = stage
        self.outcome = outcome
        self.code = code
        self.message = message
        self.timestamp = timestamp
    }
}

public struct PlaybackReasonChain: Sendable, Equatable, Codable {
    public private(set) var traces: [PlanDecisionTrace]

    public init(traces: [PlanDecisionTrace] = []) {
        self.traces = traces
    }

    public mutating func append(_ trace: PlanDecisionTrace) {
        traces.append(trace)
    }

    public var summary: String {
        traces.last?.message ?? "No decision trace available"
    }
}
