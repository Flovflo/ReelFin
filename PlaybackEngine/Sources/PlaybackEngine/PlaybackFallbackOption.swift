import Foundation

public struct PlaybackFallbackOption: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case keepOriginal
        case smooth4K
        case fullHD1080p
        case dataSaver
    }

    public var id: Kind { kind }
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let preservesOriginalVideo: Bool
    public let preservesHDR: Bool
    public let preservesDolbyVision: Bool
    public let estimatedBitrate: Int?

    public init(
        kind: Kind,
        title: String,
        subtitle: String,
        preservesOriginalVideo: Bool,
        preservesHDR: Bool,
        preservesDolbyVision: Bool,
        estimatedBitrate: Int?
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.preservesOriginalVideo = preservesOriginalVideo
        self.preservesHDR = preservesHDR
        self.preservesDolbyVision = preservesDolbyVision
        self.estimatedBitrate = estimatedBitrate
    }
}

public struct PlaybackFallbackRecommendation: Codable, Sendable, Equatable {
    public enum Trigger: String, Codable, Sendable, Equatable {
        case startupSlow
        case repeatedStalls
        case bandwidthLikelyInsufficient
        case subtitleBurnInRequired
        case routeFailed
    }

    public let trigger: Trigger
    public let message: String
    public let options: [PlaybackFallbackOption]

    public init(trigger: Trigger, message: String, options: [PlaybackFallbackOption]) {
        self.trigger = trigger
        self.message = message
        self.options = options
    }
}
