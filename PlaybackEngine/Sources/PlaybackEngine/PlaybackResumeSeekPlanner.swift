import Foundation

enum PlaybackResumeSeekPlanner {
    private static let currentTimeToleranceSeconds: Double = 3
    private static let durationToleranceSeconds: Double = 15

    static func shouldApplySeek(
        pendingResumeSeconds: Double?,
        currentPlayerTime: Double,
        currentItemDuration: Double?,
        currentMediaRuntimeSeconds: Double?,
        transcodeStartOffset: Double = 0
    ) -> Bool {
        guard let pendingResumeSeconds, pendingResumeSeconds > 0 else {
            return false
        }

        if transcodeStartOffset > 0 {
            return false
        }

        if currentPlayerTime.isFinite, abs(currentPlayerTime - pendingResumeSeconds) < currentTimeToleranceSeconds {
            return false
        }

        return !streamLooksServerOffset(
            pendingResumeSeconds: pendingResumeSeconds,
            currentPlayerTime: currentPlayerTime,
            currentItemDuration: currentItemDuration,
            currentMediaRuntimeSeconds: currentMediaRuntimeSeconds
        )
    }

    static func streamLooksServerOffset(
        pendingResumeSeconds: Double?,
        currentPlayerTime: Double,
        currentItemDuration: Double?,
        currentMediaRuntimeSeconds: Double?
    ) -> Bool {
        guard let pendingResumeSeconds, pendingResumeSeconds > 0 else {
            return false
        }

        if currentPlayerTime.isFinite, abs(currentPlayerTime - pendingResumeSeconds) < currentTimeToleranceSeconds {
            return false
        }

        guard
            let currentItemDuration,
            currentItemDuration.isFinite,
            currentItemDuration > 0,
            let currentMediaRuntimeSeconds,
            currentMediaRuntimeSeconds > 0
        else {
            return false
        }

        let expectedRemainingSeconds = max(0, currentMediaRuntimeSeconds - pendingResumeSeconds)
        return abs(currentItemDuration - expectedRemainingSeconds) < durationToleranceSeconds
    }
}
