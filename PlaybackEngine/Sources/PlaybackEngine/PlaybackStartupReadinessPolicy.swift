import Foundation

public enum PlaybackStartupReadinessPolicy {
    struct Requirement: Equatable, Sendable {
        let minimumBufferDuration: Double
        let preferredBufferDuration: Double
        let timeout: Double
        let pollInterval: Double
        let reason: String
        let allowsTimeoutStart: Bool
    }

    static func requirement(
        route: PlaybackRoute,
        sourceBitrate: Int?,
        runtimeSeconds: Double?,
        resumeSeconds: Double,
        isTVOS: Bool
    ) -> Requirement? {
        let bitrate = sourceBitrate ?? 0
        let isResume = resumeSeconds > 0

        let base: Requirement?
        switch route {
        case .directPlay:
            base = directPlayRequirement(
                route: route,
                bitrate: bitrate,
                isResume: isResume,
                isTVOS: isTVOS
            )
        case .nativeBridge:
            base = nativeBridgeRequirement(isTVOS: isTVOS)
        case .remux, .transcode:
            base = streamingRequirement(
                bitrate: bitrate,
                isTVOS: isTVOS
            )
        }

        guard let base else { return nil }
        return clamp(base, runtimeSeconds: runtimeSeconds, resumeSeconds: resumeSeconds)
    }

    public static func requiresStartupPreheat(
        route: PlaybackRoute,
        sourceBitrate: Int?,
        runtimeSeconds: Double?,
        resumeSeconds: Double,
        isTVOS: Bool
    ) -> Bool {
        if isProgressiveDirectPlay(route: route) {
            return false
        }

        return requirement(
            route: route,
            sourceBitrate: sourceBitrate,
            runtimeSeconds: runtimeSeconds,
            resumeSeconds: resumeSeconds,
            isTVOS: isTVOS
        ) != nil
    }

    static func shouldStart(
        bufferedDuration: Double,
        likelyToKeepUp: Bool,
        elapsedSeconds: Double,
        requirement: Requirement
    ) -> Bool {
        guard bufferedDuration.isFinite, bufferedDuration >= 0 else {
            if elapsedSeconds >= requirement.timeout {
                return requirement.allowsTimeoutStart
            }
            return likelyToKeepUp && elapsedSeconds >= requirement.pollInterval
        }

        if bufferedDuration >= requirement.preferredBufferDuration {
            return true
        }

        if likelyToKeepUp, bufferedDuration >= requirement.minimumBufferDuration {
            return true
        }

        if elapsedSeconds >= requirement.timeout {
            return requirement.allowsTimeoutStart
        }

        return false
    }

    static func allowsImmediateStartBeforeReadyToPlay(requirement: Requirement) -> Bool {
        requirement.allowsTimeoutStart
            && requirement.minimumBufferDuration <= 0
            && requirement.preferredBufferDuration <= 0
    }

    private static func isProgressiveDirectPlay(route: PlaybackRoute) -> Bool {
        guard case let .directPlay(url) = route else { return false }
        return !isPlaylistURL(url)
    }

    private static func directPlayRequirement(
        route: PlaybackRoute,
        bitrate: Int,
        isResume: Bool,
        isTVOS: Bool
    ) -> Requirement? {
        guard case let .directPlay(url) = route else { return nil }
        if url.pathExtension.lowercased() == "m3u8" {
            return streamingRequirement(bitrate: bitrate, isTVOS: isTVOS)
        }

        guard isTVOS else {
            guard bitrate >= 18_000_000 || (isResume && bitrate >= 12_000_000) else {
                return nil
            }
            return Requirement(
                minimumBufferDuration: 0,
                preferredBufferDuration: 0,
                timeout: 4,
                pollInterval: 0.15,
                reason: isResume ? "ios_resume_directplay_ready" : "ios_high_bitrate_directplay_ready",
                allowsTimeoutStart: false
            )
        }

        let guardedDirectPlay = isResume || bitrate >= 8_000_000
        guard guardedDirectPlay else { return nil }

        if bitrate >= 18_000_000 {
            return Requirement(
                minimumBufferDuration: 4,
                preferredBufferDuration: 12,
                timeout: 6,
                pollInterval: 0.15,
                reason: "tvos_high_bitrate_directplay_ready",
                allowsTimeoutStart: false
            )
        }

        return Requirement(
            minimumBufferDuration: 0,
            preferredBufferDuration: 0,
            timeout: 3,
            pollInterval: 0.15,
            reason: isResume ? "tvos_resume_directplay_ready" : "tvos_directplay_ready",
            allowsTimeoutStart: true
        )
    }

    private static func nativeBridgeRequirement(isTVOS: Bool) -> Requirement {
        Requirement(
            minimumBufferDuration: isTVOS ? 5 : 2,
            preferredBufferDuration: isTVOS ? 12 : 4,
            timeout: isTVOS ? 3 : 1,
            pollInterval: 0.12,
            reason: isTVOS ? "tvos_nativebridge" : "ios_nativebridge",
            allowsTimeoutStart: true
        )
    }

    private static func streamingRequirement(
        bitrate: Int,
        isTVOS: Bool
    ) -> Requirement? {
        if isTVOS {
            return Requirement(
                minimumBufferDuration: bitrate >= 15_000_000 ? 8 : 5,
                preferredBufferDuration: bitrate >= 15_000_000 ? 18 : 10,
                timeout: bitrate >= 15_000_000 ? 3.5 : 2.25,
                pollInterval: 0.15,
                reason: "tvos_hls_startup",
                allowsTimeoutStart: true
            )
        }

        guard bitrate >= 12_000_000 else { return nil }
        return Requirement(
            minimumBufferDuration: 3,
            preferredBufferDuration: 6,
            timeout: 1.25,
            pollInterval: 0.12,
            reason: "ios_high_bitrate_hls",
            allowsTimeoutStart: true
        )
    }

    private static func isPlaylistURL(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return pathExtension == "m3u8" || pathExtension == "m3u"
    }

    private static func clamp(
        _ requirement: Requirement,
        runtimeSeconds: Double?,
        resumeSeconds: Double
    ) -> Requirement {
        guard
            let runtimeSeconds,
            runtimeSeconds.isFinite,
            runtimeSeconds > 0
        else {
            return requirement
        }

        let remaining = max(0, runtimeSeconds - max(0, resumeSeconds))
        guard remaining > 0 else { return requirement }

        let preferred = min(requirement.preferredBufferDuration, max(1, remaining * 0.20))
        let minimum = min(requirement.minimumBufferDuration, preferred)
        return Requirement(
            minimumBufferDuration: minimum,
            preferredBufferDuration: preferred,
            timeout: requirement.timeout,
            pollInterval: requirement.pollInterval,
            reason: requirement.reason,
            allowsTimeoutStart: requirement.allowsTimeoutStart
        )
    }
}
