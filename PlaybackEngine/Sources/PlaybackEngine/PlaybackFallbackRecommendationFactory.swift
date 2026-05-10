import Foundation
import Shared

public enum PlaybackFallbackRecommendationFactory {
    public static func healthRecommendation(
        sourceDescription: String,
        routeGuarantees: PlaybackRouteGuarantees,
        health: PlaybackHealthSnapshot,
        mediaBitrate: Int?
    ) -> PlaybackFallbackRecommendation? {
        guard let trigger = trigger(for: health.state) else { return nil }
        return PlaybackFallbackRecommendation(
            trigger: trigger,
            message: "Your connection is struggling with \(sourceDescription).",
            options: qualityOptions(routeGuarantees: routeGuarantees, mediaBitrate: mediaBitrate)
        )
    }

    public static func qualityRecommendation(
        sourceDescription: String,
        routeGuarantees: PlaybackRouteGuarantees,
        mediaBitrate: Int?
    ) -> PlaybackFallbackRecommendation {
        PlaybackFallbackRecommendation(
            trigger: .routeFailed,
            message: "\(sourceDescription) is not preserved by the selected route.",
            options: qualityOptions(routeGuarantees: routeGuarantees, mediaBitrate: mediaBitrate)
        )
    }

    public static func subtitleBurnInRecommendation(
        source: MediaSource,
        subtitleTrack: MediaTrack
    ) -> PlaybackFallbackRecommendation? {
        let impact = SubtitleCompatibilityPolicy().qualityImpact(track: subtitleTrack, source: source)
        guard impact == .requiresBurnIn || impact == .riskyStyledText else { return nil }
        return PlaybackFallbackRecommendation(
            trigger: .subtitleBurnInRequired,
            message: "This subtitle track requires video transcoding.",
            options: [keepOriginalOption(source: source), subtitleTranscodeOption(source: source)]
        )
    }

    private static func trigger(for state: PlaybackHealthState) -> PlaybackFallbackRecommendation.Trigger? {
        switch state {
        case .startupSlow: return .startupSlow
        case .repeatedStalls: return .repeatedStalls
        case .bandwidthLikelyInsufficient: return .bandwidthLikelyInsufficient
        case .routeFailed: return .routeFailed
        case .healthy, .buffering: return nil
        }
    }

    private static func qualityOptions(routeGuarantees: PlaybackRouteGuarantees, mediaBitrate: Int?) -> [PlaybackFallbackOption] {
        [
            PlaybackFallbackOption(kind: .keepOriginal, title: "Keep Original Quality", subtitle: "Do not change playback quality.", preservesOriginalVideo: routeGuarantees.preservesOriginalVideo, preservesHDR: routeGuarantees.preservesHDR, preservesDolbyVision: routeGuarantees.preservesDolbyVision, estimatedBitrate: mediaBitrate),
            PlaybackFallbackOption(kind: .smooth4K, title: "Switch to Smooth 4K", subtitle: "Lower bitrate for stability. Original video is not preserved.", preservesOriginalVideo: false, preservesHDR: routeGuarantees.preservesHDR, preservesDolbyVision: false, estimatedBitrate: 35_000_000),
            PlaybackFallbackOption(kind: .fullHD1080p, title: "Switch to 1080p", subtitle: "Use a smaller stream for this network.", preservesOriginalVideo: false, preservesHDR: false, preservesDolbyVision: false, estimatedBitrate: 12_000_000)
        ]
    }

    private static func keepOriginalOption(source: MediaSource) -> PlaybackFallbackOption {
        let hdrClass = PlaybackMediaHDRClass.classify(source: source)
        return PlaybackFallbackOption(kind: .keepOriginal, title: "Keep Original Quality", subtitle: "Disable this subtitle and keep original video.", preservesOriginalVideo: true, preservesHDR: hdrClass != .sdr, preservesDolbyVision: DolbyVisionClass.classify(source: source).isDolbyVision, estimatedBitrate: source.bitrate)
    }

    private static func subtitleTranscodeOption(source: MediaSource) -> PlaybackFallbackOption {
        PlaybackFallbackOption(kind: .smooth4K, title: "Switch to Compatible Playback", subtitle: "Burn subtitles into video. HDR or Dolby Vision may be lost.", preservesOriginalVideo: false, preservesHDR: false, preservesDolbyVision: false, estimatedBitrate: min(source.bitrate ?? 30_000_000, 30_000_000))
    }
}
