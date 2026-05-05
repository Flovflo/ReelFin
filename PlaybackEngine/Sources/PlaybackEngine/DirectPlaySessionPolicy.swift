import AVFoundation
import Foundation
import Shared

enum DirectPlaySessionPolicy {
    static func isResumePositionSatisfied(
        currentTime: Double,
        resumeSeconds: Double,
        toleranceSeconds: Double = 3
    ) -> Bool {
        guard currentTime.isFinite, resumeSeconds.isFinite else { return false }
        return abs(currentTime - resumeSeconds) <= toleranceSeconds
    }

    static func shouldDelayFirstFrameUntilResumePosition(
        route: PlaybackRoute?,
        pendingResumeSeconds: Double?,
        currentTime: Double,
        transcodeStartOffset: Double
    ) -> Bool {
        guard case .directPlay = route else { return false }
        guard transcodeStartOffset <= 0 else { return false }
        guard let pendingResumeSeconds, pendingResumeSeconds > 0 else { return false }
        return !isResumePositionSatisfied(
            currentTime: currentTime,
            resumeSeconds: pendingResumeSeconds
        )
    }

    static func shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
        route: PlaybackRoute,
        hasMarkedFirstFrame: Bool,
        pendingResumeSeconds: Double?,
        currentTime: Double,
        itemStatus: AVPlayerItem.Status,
        transcodeStartOffset: Double
    ) -> Bool {
        guard hasMarkedFirstFrame else { return false }
        guard itemStatus == .readyToPlay else { return false }
        return !shouldDelayFirstFrameUntilResumePosition(
            route: route,
            pendingResumeSeconds: pendingResumeSeconds,
            currentTime: currentTime,
            transcodeStartOffset: transcodeStartOffset
        )
    }

    static func shouldReassertResumePositionAfterStartupSelection(
        route: PlaybackRoute?,
        resumeSeconds: Double?,
        currentTime: Double,
        transcodeStartOffset: Double,
        toleranceSeconds: Double = 3
    ) -> Bool {
        guard case .directPlay = route else { return false }
        guard transcodeStartOffset <= 0 else { return false }
        guard let resumeSeconds, resumeSeconds > 0, currentTime.isFinite else { return false }
        return currentTime + toleranceSeconds < resumeSeconds
    }

    static func shouldSuppressPlaybackFailureRecoveryAfterFirstFrame(
        hasMarkedFirstFrame: Bool,
        route: PlaybackRoute?
    ) -> Bool {
        guard hasMarkedFirstFrame else { return false }
        guard case .directPlay = route else { return true }
        return false
    }

    static func shouldAttemptStallRecovery(
        route: PlaybackRoute,
        source: MediaSource?,
        recentStallCount: Int,
        elapsedSecondsSinceLoad: Double,
        elapsedSecondsSinceFirstFrame: Double?,
        isTVOS: Bool
    ) -> Bool {
        guard isStallResistantDirectPlay(route: route, source: source) else { return false }

        if elapsedSecondsSinceFirstFrame != nil {
            return false
        }

        return elapsedSecondsSinceLoad <= 12 && recentStallCount >= 2
    }

    static func shouldKeepCurrentItemAfterPostStartStall(
        route: PlaybackRoute,
        source: MediaSource?,
        isTVOS: Bool
    ) -> Bool {
        _ = isTVOS
        return isStallResistantDirectPlay(route: route, source: source)
    }

    static func shouldMarkRouteFragileAfterPostStartStall(
        route: PlaybackRoute,
        source: MediaSource?,
        recentStallCount: Int,
        elapsedSecondsSinceFirstFrame: Double?
    ) -> Bool {
        guard elapsedSecondsSinceFirstFrame != nil else { return false }
        guard recentStallCount >= 3 else { return false }
        return isStallResistantDirectPlay(route: route, source: source)
    }

    static func postStartStallBufferDuration(
        currentForwardBufferDuration: Double,
        recentStallCount: Int = 1,
        isTVOS: Bool = false
    ) -> Double {
        guard isTVOS else { return max(currentForwardBufferDuration, 24) }

        let target: Double
        switch recentStallCount {
        case ..<2:
            target = 24
        case 2:
            target = 60
        case 3 ..< 6:
            target = 120
        default:
            target = 240
        }
        return max(currentForwardBufferDuration, target)
    }

    static func postStartStallWaitsToMinimizeStalling(isTVOS: Bool) -> Bool {
        _ = isTVOS
        return true
    }

    static func isIPhoneNoStallGuardedDirectPlay(route: PlaybackRoute, source: MediaSource?) -> Bool {
        guard case let .directPlay(url) = route else { return false }
        guard url.pathExtension.lowercased() != "m3u8" else { return false }
        return (source?.bitrate ?? 0) >= 18_000_000
    }

    static func isStallResistantDirectPlay(route: PlaybackRoute, source: MediaSource?) -> Bool {
        guard case let .directPlay(url) = route else { return false }
        guard url.pathExtension.lowercased() != "m3u8" else { return false }
        guard let source else { return false }
        return source.isPremiumVideoSource || (source.bitrate ?? 0) >= 12_000_000
    }
}
