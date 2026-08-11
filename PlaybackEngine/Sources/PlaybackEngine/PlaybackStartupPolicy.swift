import Foundation

public enum PlaybackStartupPolicy {
    public struct Configuration: Sendable, Equatable {
        public let preferredForwardBufferDuration: Double
        public let automaticallyWaitsToMinimizeStalling: Bool
        public let usePlayImmediatelyWhenReady: Bool

        public init(
            preferredForwardBufferDuration: Double,
            automaticallyWaitsToMinimizeStalling: Bool,
            usePlayImmediatelyWhenReady: Bool
        ) {
            self.preferredForwardBufferDuration = preferredForwardBufferDuration
            self.automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling
            self.usePlayImmediatelyWhenReady = usePlayImmediatelyWhenReady
        }
    }

    public static func configuration(for startupClass: PlaybackStartupClass) -> Configuration {
        switch startupClass {
        case .directLocal:
            return Configuration(
                preferredForwardBufferDuration: 0.75,
                automaticallyWaitsToMinimizeStalling: false,
                usePlayImmediatelyWhenReady: true
            )
        case .directLAN, .nativeDirect:
            return Configuration(
                preferredForwardBufferDuration: 1.0,
                automaticallyWaitsToMinimizeStalling: false,
                usePlayImmediatelyWhenReady: true
            )
        case .remoteDirect, .progressiveRemux:
            return Configuration(
                preferredForwardBufferDuration: 2.0,
                automaticallyWaitsToMinimizeStalling: false,
                usePlayImmediatelyWhenReady: true
            )
        case .hlsRemux:
            return Configuration(
                preferredForwardBufferDuration: 3.0,
                automaticallyWaitsToMinimizeStalling: true,
                usePlayImmediatelyWhenReady: false
            )
        case .transcode:
            return Configuration(
                preferredForwardBufferDuration: 5.0,
                automaticallyWaitsToMinimizeStalling: true,
                usePlayImmediatelyWhenReady: false
            )
        case .unknown:
            return Configuration(
                preferredForwardBufferDuration: 3.0,
                automaticallyWaitsToMinimizeStalling: true,
                usePlayImmediatelyWhenReady: false
            )
        }
    }
}

public struct PlaybackStartupTrace: Codable, Sendable, Equatable {
    public var userTappedPlayAt: Date?
    public var playbackInfoStartedAt: Date?
    public var playbackInfoReturnedAt: Date?
    public var routeSelectedAt: Date?
    public var assetCreatedAt: Date?
    public var itemCreatedAt: Date?
    public var itemReadyAt: Date?
    public var firstFrameAt: Date?
    public var playbackStartedAt: Date?
    public var firstStallAt: Date?

    public init(
        userTappedPlayAt: Date? = nil,
        playbackInfoStartedAt: Date? = nil,
        playbackInfoReturnedAt: Date? = nil,
        routeSelectedAt: Date? = nil,
        assetCreatedAt: Date? = nil,
        itemCreatedAt: Date? = nil,
        itemReadyAt: Date? = nil,
        firstFrameAt: Date? = nil,
        playbackStartedAt: Date? = nil,
        firstStallAt: Date? = nil
    ) {
        self.userTappedPlayAt = userTappedPlayAt
        self.playbackInfoStartedAt = playbackInfoStartedAt
        self.playbackInfoReturnedAt = playbackInfoReturnedAt
        self.routeSelectedAt = routeSelectedAt
        self.assetCreatedAt = assetCreatedAt
        self.itemCreatedAt = itemCreatedAt
        self.itemReadyAt = itemReadyAt
        self.firstFrameAt = firstFrameAt
        self.playbackStartedAt = playbackStartedAt
        self.firstStallAt = firstStallAt
    }

    public func milliseconds(from start: Date?, to end: Date?) -> Double? {
        guard let start, let end else { return nil }
        return max(0, end.timeIntervalSince(start) * 1_000)
    }
}

/// Monotonic startup stages used to diagnose tap-to-player delays without wall-clock skew.
public struct PlaybackStartupStageTrace: Sendable, Equatable {
    public struct Sample: Sendable, Equatable {
        public let stage: String
        public let elapsedMilliseconds: Double
    }

    public let sessionID: String
    public let build: String
    public let platform: String
    public private(set) var samples: [Sample] = []
    private let startedAtUptime: TimeInterval

    public init(
        sessionID: String,
        build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
        platform: String = Self.currentPlatform,
        startedAtUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.sessionID = sessionID
        self.build = build
        self.platform = platform
        self.startedAtUptime = startedAtUptime
    }

    @discardableResult
    public mutating func mark(
        _ stage: String,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Sample {
        let sample = Sample(
            stage: stage,
            elapsedMilliseconds: max(0, uptime - startedAtUptime) * 1_000
        )
        samples.append(sample)
        return sample
    }

    public static var currentPlatform: String {
#if os(tvOS)
        "tvOS"
#elseif os(iOS)
        "iOS"
#else
        "Apple"
#endif
    }
}
