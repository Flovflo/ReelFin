import Foundation

public enum PlaybackDiagnosticEventKind: String, Sendable, Codable {
    case startup
    case fallback
    case fragmentValidation
    case seekRecovery
    case planDecision
}

public struct PlaybackDiagnosticEvent: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let kind: PlaybackDiagnosticEventKind
    public let timestamp: Date
    public let attributes: [String: String]

    public init(
        id: UUID = UUID(),
        kind: PlaybackDiagnosticEventKind,
        timestamp: Date = Date(),
        attributes: [String: String]
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.attributes = attributes
    }
}

public actor DiagnosticsStoreActor {
    private var events: [PlaybackDiagnosticEvent] = []

    public init() {}

    public func record(_ event: PlaybackDiagnosticEvent) {
        events.append(event)
    }

    public func drain() -> [PlaybackDiagnosticEvent] {
        defer { events.removeAll() }
        return events
    }

    public func snapshot() -> [PlaybackDiagnosticEvent] {
        events
    }
}

public struct PlaybackDiagnostics: Sendable {
    public let store: DiagnosticsStoreActor

    public init(store: DiagnosticsStoreActor = DiagnosticsStoreActor()) {
        self.store = store
    }

    public func recordPlan(_ plan: PlaybackPlan) {
        Task {
            await store.record(
                PlaybackDiagnosticEvent(
                    kind: .planDecision,
                    attributes: [
                        "lane": plan.lane.rawValue,
                        "sourceID": plan.sourceID ?? "unknown",
                        "summary": plan.reasonChain.summary
                    ]
                )
            )
        }
    }

    public func recordSeekRecovery(targetPTS: Int64, recovered: Bool) {
        Task {
            await store.record(
                PlaybackDiagnosticEvent(
                    kind: .seekRecovery,
                    attributes: [
                        "targetPTS": String(targetPTS),
                        "recovered": String(recovered)
                    ]
                )
            )
        }
    }
}
