import Foundation

enum PlaybackTVOSCachingPolicy {
    struct StartupBufferingHint: Equatable, Sendable {
        let forwardBufferDuration: Double
        let waitsToMinimizeStalling: Bool
        let minimumStartupBufferDuration: Double
        let preferredStartupBufferDuration: Double
        let startupTimeout: Double
        let fastGrowthRateThreshold: Double
        let syntheticPreloadCount: Int
        let syntheticLookaheadSegments: Int
        let reason: String
    }

    struct AdaptiveCachingHint: Equatable, Sendable {
        enum Phase: Int, Comparable, Sendable {
            case warm
            case hot
            case deep
            case flood

            static func < (lhs: Phase, rhs: Phase) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        let phase: Phase
        let headroomRatio: Double
        let forwardBufferDuration: Double
        let syntheticPreloadCount: Int
        let syntheticLookaheadSegments: Int
    }

    private struct RampConfiguration: Sendable {
        let phase: AdaptiveCachingHint.Phase
        let minimumPlaybackSeconds: Double
        let minimumHealthySamples: Int
        let minimumHeadroomRatio: Double
        let forwardBufferDuration: Double
        let syntheticPreloadCount: Int
        let syntheticLookaheadSegments: Int
    }

    private static let minimumAggressiveBufferPlaybackSeconds: Double = 12
    private static let minimumBufferGrowthSeconds: Double = 15
    private static let healthyHeadroomRatio: Double = 1.25

    private static let rampConfigurations: [RampConfiguration] = [
        RampConfiguration(
            phase: .warm,
            minimumPlaybackSeconds: 12,
            minimumHealthySamples: 1,
            minimumHeadroomRatio: 1.3,
            forwardBufferDuration: 24,
            syntheticPreloadCount: 6,
            syntheticLookaheadSegments: 4
        ),
        RampConfiguration(
            phase: .hot,
            minimumPlaybackSeconds: 45,
            minimumHealthySamples: 3,
            minimumHeadroomRatio: 1.6,
            forwardBufferDuration: 90,
            syntheticPreloadCount: 10,
            syntheticLookaheadSegments: 6
        ),
        RampConfiguration(
            phase: .deep,
            minimumPlaybackSeconds: 120,
            minimumHealthySamples: 6,
            minimumHeadroomRatio: 2.1,
            forwardBufferDuration: 300,
            syntheticPreloadCount: 14,
            syntheticLookaheadSegments: 8
        ),
        RampConfiguration(
            phase: .flood,
            minimumPlaybackSeconds: 300,
            minimumHealthySamples: 10,
            minimumHeadroomRatio: 2.8,
            forwardBufferDuration: 900,
            syntheticPreloadCount: 18,
            syntheticLookaheadSegments: 12
        )
    ]

    static let syntheticReaderCacheSizeBytes = 192 * 1024 * 1024
    static let syntheticSegmentCacheSizeBytes = 128 * 1024 * 1024
    static let syntheticReadAheadChunks = 2
    static let syntheticPlaylistPreloadCount = 4

    static func startupBufferingHint(
        defaultForwardBufferDuration: Double,
        defaultWaitsToMinimizeStalling: Bool,
        route: PlaybackRoute,
        sourceBitrate: Int?,
        isPremiumSource: Bool,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) -> StartupBufferingHint? {
        guard isTVOS else { return nil }

        let bitrate = Double(max(0, sourceBitrate ?? 0))
        let runtime = runtimeSeconds.flatMap { value -> Double? in
            guard value.isFinite, value > 0 else { return nil }
            return value
        }

        let hint: StartupBufferingHint
        switch route {
        case .nativeBridge:
            hint = StartupBufferingHint(
                forwardBufferDuration: max(defaultForwardBufferDuration, 6),
                waitsToMinimizeStalling: true,
                minimumStartupBufferDuration: 0,
                preferredStartupBufferDuration: 0,
                startupTimeout: 0,
                fastGrowthRateThreshold: 0,
                syntheticPreloadCount: isPremiumSource ? 16 : 12,
                syntheticLookaheadSegments: isPremiumSource ? 10 : 8,
                reason: "tvos_nativebridge_prefetch"
            )
        case let .directPlay(url) where url.pathExtension.lowercased() != "m3u8":
            if isPremiumSource || bitrate >= 20_000_000 {
                hint = StartupBufferingHint(
                    forwardBufferDuration: max(defaultForwardBufferDuration, 30),
                    waitsToMinimizeStalling: true,
                    minimumStartupBufferDuration: 8,
                    preferredStartupBufferDuration: 18,
                    startupTimeout: 6.5,
                    fastGrowthRateThreshold: 1.8,
                    syntheticPreloadCount: 14,
                    syntheticLookaheadSegments: 10,
                    reason: "tvos_premium_direct_play"
                )
            } else if bitrate >= 8_000_000 {
                hint = StartupBufferingHint(
                    forwardBufferDuration: max(defaultForwardBufferDuration, 18),
                    waitsToMinimizeStalling: true,
                    minimumStartupBufferDuration: 6,
                    preferredStartupBufferDuration: 12,
                    startupTimeout: 5.5,
                    fastGrowthRateThreshold: 1.8,
                    syntheticPreloadCount: 12,
                    syntheticLookaheadSegments: 8,
                    reason: "tvos_mid_bitrate_direct_play"
                )
            } else {
                hint = StartupBufferingHint(
                    forwardBufferDuration: max(defaultForwardBufferDuration, 12),
                    waitsToMinimizeStalling: max(defaultForwardBufferDuration, 12) > defaultForwardBufferDuration || defaultWaitsToMinimizeStalling,
                    minimumStartupBufferDuration: 4,
                    preferredStartupBufferDuration: 8,
                    startupTimeout: 4.5,
                    fastGrowthRateThreshold: 2.1,
                    syntheticPreloadCount: 10,
                    syntheticLookaheadSegments: 6,
                    reason: "tvos_standard_direct_play"
                )
            }
        default:
            if isPremiumSource || bitrate >= 16_000_000 {
                hint = StartupBufferingHint(
                    forwardBufferDuration: max(defaultForwardBufferDuration, 18),
                    waitsToMinimizeStalling: true,
                    minimumStartupBufferDuration: 7,
                    preferredStartupBufferDuration: 14,
                    startupTimeout: 6,
                    fastGrowthRateThreshold: 1.7,
                    syntheticPreloadCount: 14,
                    syntheticLookaheadSegments: 10,
                    reason: "tvos_premium_streaming"
                )
            } else {
                hint = StartupBufferingHint(
                    forwardBufferDuration: max(defaultForwardBufferDuration, 12),
                    waitsToMinimizeStalling: true,
                    minimumStartupBufferDuration: 5,
                    preferredStartupBufferDuration: 10,
                    startupTimeout: 5,
                    fastGrowthRateThreshold: 1.7,
                    syntheticPreloadCount: 12,
                    syntheticLookaheadSegments: 8,
                    reason: "tvos_standard_streaming"
                )
            }
        }

        return clampStartupBufferingHint(hint, runtimeSeconds: runtime)
    }

    static func shouldStartPlayback(
        bufferedDuration: Double,
        growthRate: Double,
        likelyToKeepUp: Bool,
        hint: StartupBufferingHint
    ) -> Bool {
        guard bufferedDuration.isFinite, bufferedDuration >= 0 else { return likelyToKeepUp }
        if hint.preferredStartupBufferDuration <= 0 {
            return true
        }
        if bufferedDuration >= hint.preferredStartupBufferDuration {
            return true
        }
        if likelyToKeepUp && bufferedDuration >= hint.minimumStartupBufferDuration {
            return true
        }
        return growthRate.isFinite
            && growthRate >= hint.fastGrowthRateThreshold
            && bufferedDuration >= hint.minimumStartupBufferDuration
    }

    static func startupForwardBufferDuration(
        baseBufferDuration: Double,
        route _: PlaybackRoute,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) -> Double {
        guard isTVOS else { return baseBufferDuration }
        guard let runtimeSeconds, runtimeSeconds.isFinite, runtimeSeconds > 0 else {
            return baseBufferDuration
        }
        return min(baseBufferDuration, runtimeSeconds)
    }

    static func adaptiveCachingHint(
        currentBufferDuration: Double,
        observedBitrate: Double,
        indicatedBitrate: Double,
        sourceBitrate: Int?,
        currentTime: Double,
        runtimeSeconds: Double?,
        healthySampleCount: Int,
        isTVOS: Bool
    ) -> AdaptiveCachingHint? {
        guard isTVOS else { return nil }
        guard currentBufferDuration.isFinite, currentBufferDuration >= 0 else { return nil }
        guard currentTime.isFinite, currentTime >= minimumAggressiveBufferPlaybackSeconds else { return nil }
        guard let runtimeSeconds, runtimeSeconds.isFinite, runtimeSeconds > 0 else { return nil }
        guard observedBitrate.isFinite, observedBitrate > 0 else { return nil }

        let remainingDuration = max(0, runtimeSeconds - max(0, currentTime))
        guard remainingDuration > currentBufferDuration + minimumBufferGrowthSeconds else {
            return nil
        }

        let requiredBitrate = self.requiredBitrate(
            indicatedBitrate: indicatedBitrate,
            sourceBitrate: sourceBitrate
        )
        guard requiredBitrate > 0 else { return nil }

        let headroomRatio = observedBitrate / requiredBitrate
        guard headroomRatio >= healthyHeadroomRatio else { return nil }

        guard let configuration = rampConfigurations.last(where: {
            currentTime >= $0.minimumPlaybackSeconds &&
                healthySampleCount >= $0.minimumHealthySamples &&
                headroomRatio >= $0.minimumHeadroomRatio
        }) else {
            return nil
        }

        let targetBufferDuration = min(remainingDuration, configuration.forwardBufferDuration)
        guard targetBufferDuration > currentBufferDuration + minimumBufferGrowthSeconds else {
            return nil
        }

        return AdaptiveCachingHint(
            phase: configuration.phase,
            headroomRatio: headroomRatio,
            forwardBufferDuration: targetBufferDuration,
            syntheticPreloadCount: configuration.syntheticPreloadCount,
            syntheticLookaheadSegments: configuration.syntheticLookaheadSegments
        )
    }

    static func isHealthyAccessLogSample(
        observedBitrate: Double,
        indicatedBitrate: Double,
        sourceBitrate: Int?,
        isTVOS: Bool
    ) -> Bool {
        guard isTVOS else { return false }
        guard observedBitrate.isFinite, observedBitrate > 0 else { return false }
        let requiredBitrate = self.requiredBitrate(
            indicatedBitrate: indicatedBitrate,
            sourceBitrate: sourceBitrate
        )
        guard requiredBitrate > 0 else { return false }
        return (observedBitrate / requiredBitrate) >= healthyHeadroomRatio
    }

    static func aggressiveForwardBufferDuration(
        currentBufferDuration: Double,
        observedBitrate: Double,
        indicatedBitrate: Double,
        sourceBitrate: Int?,
        currentTime: Double,
        runtimeSeconds: Double?,
        healthySampleCount: Int = .max,
        isTVOS: Bool
    ) -> Double? {
        adaptiveCachingHint(
            currentBufferDuration: currentBufferDuration,
            observedBitrate: observedBitrate,
            indicatedBitrate: indicatedBitrate,
            sourceBitrate: sourceBitrate,
            currentTime: currentTime,
            runtimeSeconds: runtimeSeconds,
            healthySampleCount: healthySampleCount,
            isTVOS: isTVOS
        )?.forwardBufferDuration
    }

    static func syntheticReaderConfiguration(
        base: HTTPRangeReader.Configuration,
        isTVOS: Bool
    ) -> HTTPRangeReader.Configuration {
        guard isTVOS else { return base }

        var adjusted = base
        adjusted.maxCacheSize = max(base.maxCacheSize, syntheticReaderCacheSizeBytes)
        adjusted.readAheadChunks = max(base.readAheadChunks, syntheticReadAheadChunks)
        adjusted.maxConcurrentRequests = max(base.maxConcurrentRequests, 4)
        return adjusted
    }

    static func syntheticSegmentCacheSize(isTVOS: Bool) -> Int {
        isTVOS ? syntheticSegmentCacheSizeBytes : 16 * 1024 * 1024
    }

    static func syntheticPlaylistPreloadCount(isTVOS: Bool) -> Int {
        isTVOS ? syntheticPlaylistPreloadCount : 3
    }

    private static func requiredBitrate(
        indicatedBitrate: Double,
        sourceBitrate: Int?
    ) -> Double {
        max(
            indicatedBitrate.isFinite ? indicatedBitrate : 0,
            Double(sourceBitrate ?? 0)
        )
    }

    private static func clampStartupBufferingHint(
        _ hint: StartupBufferingHint,
        runtimeSeconds: Double?
    ) -> StartupBufferingHint {
        guard let runtimeSeconds else { return hint }

        let boundedForward = min(hint.forwardBufferDuration, runtimeSeconds)
        let boundedPreferred = min(hint.preferredStartupBufferDuration, boundedForward)
        let boundedMinimum = min(hint.minimumStartupBufferDuration, boundedPreferred)

        return StartupBufferingHint(
            forwardBufferDuration: boundedForward,
            waitsToMinimizeStalling: hint.waitsToMinimizeStalling,
            minimumStartupBufferDuration: boundedMinimum,
            preferredStartupBufferDuration: boundedPreferred,
            startupTimeout: hint.startupTimeout,
            fastGrowthRateThreshold: hint.fastGrowthRateThreshold,
            syntheticPreloadCount: hint.syntheticPreloadCount,
            syntheticLookaheadSegments: hint.syntheticLookaheadSegments,
            reason: hint.reason
        )
    }
}
