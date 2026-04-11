import Foundation

public enum EpisodeReleaseNotificationAuthorization: String, Codable, CaseIterable, Sendable {
    case notDetermined
    case denied
    case authorized
    case unsupported
}

public struct EpisodeReleaseState: Codable, Hashable, Sendable {
    public var seriesID: String
    public var seriesName: String
    public var lastKnownNextUpEpisodeID: String?
    public var lastKnownNextUpSeasonNumber: Int?
    public var lastKnownNextUpEpisodeNumber: Int?
    public var lastNotifiedEpisodeID: String?
    public var updatedAt: Date

    public init(
        seriesID: String,
        seriesName: String,
        lastKnownNextUpEpisodeID: String? = nil,
        lastKnownNextUpSeasonNumber: Int? = nil,
        lastKnownNextUpEpisodeNumber: Int? = nil,
        lastNotifiedEpisodeID: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.lastKnownNextUpEpisodeID = lastKnownNextUpEpisodeID
        self.lastKnownNextUpSeasonNumber = lastKnownNextUpSeasonNumber
        self.lastKnownNextUpEpisodeNumber = lastKnownNextUpEpisodeNumber
        self.lastNotifiedEpisodeID = lastNotifiedEpisodeID
        self.updatedAt = updatedAt
    }
}

public struct EpisodeReleaseAlert: Hashable, Sendable {
    public var seriesID: String
    public var seriesName: String
    public var episodeID: String
    public var episodeTitle: String
    public var seasonNumber: Int?
    public var episodeNumber: Int?

    public init(
        seriesID: String,
        seriesName: String,
        episodeID: String,
        episodeTitle: String,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil
    ) {
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.episodeID = episodeID
        self.episodeTitle = episodeTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }
}

public protocol EpisodeReleaseTrackingProtocol: AnyObject, Sendable {
    func markSeriesFollowed(from episode: MediaItem) async
    func reconcileAfterSync(feed: HomeFeed) async -> [EpisodeReleaseAlert]
}

public protocol EpisodeReleaseNotificationManaging: AnyObject, Sendable {
    func authorizationStatus() async -> EpisodeReleaseNotificationAuthorization
    func notificationsEnabled() async -> Bool
    func setNotificationsEnabled(_ enabled: Bool) async
    func deliver(alerts: [EpisodeReleaseAlert], reason: SyncReason) async
}

public actor NoopEpisodeReleaseNotificationManager: EpisodeReleaseNotificationManaging {
    public init() {}

    public func authorizationStatus() async -> EpisodeReleaseNotificationAuthorization {
        .unsupported
    }

    public func notificationsEnabled() async -> Bool {
        false
    }

    public func setNotificationsEnabled(_ enabled: Bool) async {
        _ = enabled
    }

    public func deliver(alerts: [EpisodeReleaseAlert], reason: SyncReason) async {
        _ = alerts
        _ = reason
    }
}

