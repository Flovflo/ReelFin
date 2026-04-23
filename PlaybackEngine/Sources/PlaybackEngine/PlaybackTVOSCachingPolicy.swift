import Foundation

enum PlaybackTVOSCachingPolicy {
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
        playbackElapsedSeconds: Double,
        runtimeSeconds: Double?,
        healthySampleCount: Int,
        isTVOS: Bool
    ) -> AdaptiveCachingHint? {
        guard isTVOS else { return nil }
        guard currentBufferDuration.isFinite, currentBufferDuration >= 0 else { return nil }
        guard currentTime.isFinite, currentTime >= 0 else { return nil }
        guard playbackElapsedSeconds.isFinite, playbackElapsedSeconds >= minimumAggressiveBufferPlaybackSeconds else { return nil }
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
            playbackElapsedSeconds >= $0.minimumPlaybackSeconds &&
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
        playbackElapsedSeconds: Double,
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
            playbackElapsedSeconds: playbackElapsedSeconds,
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
}
