import Foundation

public enum MediaSegmentType: String, CaseIterable, Hashable, Sendable {
    case unknown
    case commercial
    case preview
    case recap
    case outro
    case intro

    public init(jellyfinValue: String) {
        switch jellyfinValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "commercial": self = .commercial
        case "preview": self = .preview
        case "recap": self = .recap
        case "outro": self = .outro
        case "intro": self = .intro
        default: self = .unknown
        }
    }

    public func skipTitle(isEpisode: Bool, nextEpisodeAvailable: Bool) -> String {
        switch self {
        case .intro:
            return "Skip Intro"
        case .commercial:
            return "Skip Ad"
        case .preview:
            return "Skip Preview"
        case .recap:
            return "Skip Recap"
        case .outro:
            return isEpisode && nextEpisodeAvailable ? "Next Episode" : "Skip Credits"
        case .unknown:
            return "Skip"
        }
    }
}

public struct MediaSegment: Hashable, Identifiable, Sendable {
    public let id: String
    public let itemID: String
    public let type: MediaSegmentType
    public let startTicks: Int64
    public let endTicks: Int64

    public init(id: String, itemID: String, type: MediaSegmentType, startTicks: Int64, endTicks: Int64) {
        self.id = id
        self.itemID = itemID
        self.type = type
        self.startTicks = startTicks
        self.endTicks = endTicks
    }

    public var startSeconds: Double {
        Double(startTicks) / 10_000_000
    }

    public var endSeconds: Double {
        Double(endTicks) / 10_000_000
    }

    public var durationSeconds: Double {
        max(0, endSeconds - startSeconds)
    }

    public var isValid: Bool {
        endTicks > startTicks
    }

    public func contains(time seconds: Double) -> Bool {
        seconds >= startSeconds && seconds < endSeconds
    }
}
