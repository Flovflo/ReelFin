import Foundation

enum PlaybackStartupReadinessPolicy {
    struct Requirement: Equatable, Sendable {
        let minimumBufferDuration: Double
        let preferredBufferDuration: Double
        let timeout: Double
        let pollInterval: Double
        let reason: String
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

    static func shouldStart(
        bufferedDuration: Double,
        likelyToKeepUp: Bool,
        elapsedSeconds: Double,
        requirement: Requirement
    ) -> Bool {
        guard elapsedSeconds < requirement.timeout else { return true }
        guard bufferedDuration.isFinite, bufferedDuration >= 0 else {
            return likelyToKeepUp && elapsedSeconds >= requirement.pollInterval
        }

        if bufferedDuration >= requirement.preferredBufferDuration {
            return true
        }

        if likelyToKeepUp, bufferedDuration >= requirement.minimumBufferDuration {
            return true
        }

        return false
    }

    private static func directPlayRequirement(
        route: PlaybackRoute,
        bitrate: Int,
        isResume: Bool,
        isTVOS: Bool
    ) -> Requirement? {
        guard isTVOS else {
            guard case let .directPlay(url) = route else { return nil }
            if url.pathExtension.lowercased() == "m3u8" {
                return streamingRequirement(bitrate: bitrate, isTVOS: false)
            }
            guard bitrate >= 18_000_000 || (isResume && bitrate >= 12_000_000) else {
                return nil
            }
            return Requirement(
                minimumBufferDuration: 8,
                preferredBufferDuration: 20,
                timeout: 6,
                pollInterval: 0.15,
                reason: isResume ? "ios_resume_directplay_guard" : "ios_high_bitrate_directplay_guard"
            )
        }

        if bitrate >= 18_000_000 {
            return Requirement(
                minimumBufferDuration: 12,
                preferredBufferDuration: 30,
                timeout: 5,
                pollInterval: 0.15,
                reason: "tvos_high_bitrate_directplay"
            )
        }

        return Requirement(
            minimumBufferDuration: isResume || bitrate >= 8_000_000 ? 8 : 5,
            preferredBufferDuration: isResume || bitrate >= 8_000_000 ? 18 : 10,
            timeout: isResume || bitrate >= 8_000_000 ? 3.5 : 2,
            pollInterval: 0.15,
            reason: isResume ? "tvos_resume_directplay" : "tvos_directplay"
        )
    }

    private static func nativeBridgeRequirement(isTVOS: Bool) -> Requirement {
        Requirement(
            minimumBufferDuration: isTVOS ? 5 : 2,
            preferredBufferDuration: isTVOS ? 12 : 4,
            timeout: isTVOS ? 3 : 1,
            pollInterval: 0.12,
            reason: isTVOS ? "tvos_nativebridge" : "ios_nativebridge"
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
                reason: "tvos_hls_startup"
            )
        }

        guard bitrate >= 12_000_000 else { return nil }
        return Requirement(
            minimumBufferDuration: 3,
            preferredBufferDuration: 6,
            timeout: 1.25,
            pollInterval: 0.12,
            reason: "ios_high_bitrate_hls"
        )
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
            reason: requirement.reason
        )
    }
}
