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

        if let elapsedSecondsSinceFirstFrame {
            if isTVOS {
                return elapsedSecondsSinceFirstFrame <= 20 && recentStallCount >= 2
            }
            return recentStallCount >= 3
        }

        return elapsedSecondsSinceLoad <= 12 && recentStallCount >= 2
    }

    static func shouldKeepCurrentItemAfterPostStartStall(
        route: PlaybackRoute,
        source: MediaSource?,
        isTVOS: Bool
    ) -> Bool {
        guard !isTVOS else { return false }
        return isStallResistantDirectPlay(route: route, source: source)
    }

    static func postStartStallBufferDuration(currentForwardBufferDuration: Double) -> Double {
        max(currentForwardBufferDuration, 24)
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
