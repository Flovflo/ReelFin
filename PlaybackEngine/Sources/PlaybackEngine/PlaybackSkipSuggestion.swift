import Foundation
import Shared

public enum PlaybackSkipTarget: Hashable, Sendable {
    case seek(to: Double)
    case nextEpisode
}

public struct PlaybackSkipSuggestion: Hashable, Sendable {
    public let title: String
    public let systemImageName: String
    public let target: PlaybackSkipTarget

    public init(title: String, systemImageName: String, target: PlaybackSkipTarget) {
        self.title = title
        self.systemImageName = systemImageName
        self.target = target
    }
}

enum PlaybackSkipSuggestionResolver {
    private static let nextEpisodeFallbackWindow: Double = 30
    private static let seekPadding: Double = 0.5

    static func suggestion(
        segments: [MediaSegment],
        currentTime: Double,
        duration: Double,
        currentItem: MediaItem?,
        nextEpisodeQueue: [MediaItem]
    ) -> PlaybackSkipSuggestion? {
        let activeSegment = activeSegment(in: segments, currentTime: currentTime)
        if let activeSegment {
            return suggestion(
                for: activeSegment,
                currentItem: currentItem,
                nextEpisodeAvailable: !nextEpisodeQueue.isEmpty,
                currentTime: currentTime
            )
        }

        return fallbackSuggestion(
            currentTime: currentTime,
            duration: duration,
            currentItem: currentItem,
            nextEpisodeAvailable: !nextEpisodeQueue.isEmpty
        )
    }

    private static func activeSegment(in segments: [MediaSegment], currentTime: Double) -> MediaSegment? {
        segments
            .filter(\.isValid)
            .sorted(by: segmentSort)
            .first(where: { $0.contains(time: currentTime) })
    }

    private static func segmentSort(_ lhs: MediaSegment, _ rhs: MediaSegment) -> Bool {
        if lhs.startTicks != rhs.startTicks {
            return lhs.startTicks < rhs.startTicks
        }
        return priority(for: lhs.type) < priority(for: rhs.type)
    }

    private static func priority(for type: MediaSegmentType) -> Int {
        switch type {
        case .intro: return 0
        case .recap: return 1
        case .preview: return 2
        case .commercial: return 3
        case .outro: return 4
        case .unknown: return 5
        }
    }

    private static func suggestion(
        for segment: MediaSegment,
        currentItem: MediaItem?,
        nextEpisodeAvailable: Bool,
        currentTime _: Double
    ) -> PlaybackSkipSuggestion {
        let isEpisode = currentItem?.mediaType == .episode
        if segment.type == .outro, isEpisode, nextEpisodeAvailable {
            return PlaybackSkipSuggestion(
                title: "Next Episode",
                systemImageName: "forward.end.circle.fill",
                target: .nextEpisode
            )
        }

        let title = segment.type.skipTitle(isEpisode: isEpisode, nextEpisodeAvailable: nextEpisodeAvailable)
        return PlaybackSkipSuggestion(
            title: title,
            systemImageName: "forward.end.circle.fill",
            target: .seek(to: max(segment.endSeconds + seekPadding, segment.startSeconds + seekPadding))
        )
    }

    private static func fallbackSuggestion(
        currentTime: Double,
        duration: Double,
        currentItem: MediaItem?,
        nextEpisodeAvailable: Bool
    ) -> PlaybackSkipSuggestion? {
        guard currentItem?.mediaType == .episode, nextEpisodeAvailable, duration > 0 else {
            return nil
        }

        let remaining = duration - currentTime
        guard remaining <= nextEpisodeFallbackWindow else {
            return nil
        }

        return PlaybackSkipSuggestion(
            title: "Next Episode",
            systemImageName: "forward.end.circle.fill",
            target: .nextEpisode
        )
    }
}
