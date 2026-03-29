import Foundation

enum PlaybackTVOSCachingPolicy {
    private static let directPlayStartupFloorSeconds: Double = 120
    private static let remuxStartupFloorSeconds: Double = 180
    private static let transcodeStartupFloorSeconds: Double = 240
    private static let nativeBridgeStartupFloorSeconds: Double = 180
    private static let aggressiveHeadroomRatio: Double = 1.4
    private static let minimumBufferGrowthSeconds: Double = 45
    private static let maximumWholeAssetBufferHintSeconds: Double = 3 * 60 * 60

    static let syntheticReaderCacheSizeBytes = 192 * 1024 * 1024
    static let syntheticSegmentCacheSizeBytes = 128 * 1024 * 1024
    static let syntheticReadAheadChunks = 6
    static let syntheticPlaylistPreloadCount = 10

    static func startupForwardBufferDuration(
        baseBufferDuration: Double,
        route: PlaybackRoute,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) -> Double {
        guard isTVOS else { return baseBufferDuration }

        let startupFloor: Double
        switch route {
        case .directPlay:
            startupFloor = directPlayStartupFloorSeconds
        case .remux:
            startupFloor = remuxStartupFloorSeconds
        case .transcode:
            startupFloor = transcodeStartupFloorSeconds
        case .nativeBridge:
            startupFloor = nativeBridgeStartupFloorSeconds
        }

        let target = max(baseBufferDuration, startupFloor)
        guard let runtimeSeconds, runtimeSeconds.isFinite, runtimeSeconds > 0 else {
            return target
        }
        return min(target, runtimeSeconds)
    }

    static func aggressiveForwardBufferDuration(
        currentBufferDuration: Double,
        observedBitrate: Double,
        indicatedBitrate: Double,
        sourceBitrate: Int?,
        currentTime: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) -> Double? {
        guard isTVOS else { return nil }
        guard currentBufferDuration.isFinite, currentBufferDuration >= 0 else { return nil }
        guard let runtimeSeconds, runtimeSeconds.isFinite, runtimeSeconds > 0 else { return nil }
        guard observedBitrate.isFinite, observedBitrate > 0 else { return nil }

        let remainingDuration = max(0, runtimeSeconds - max(0, currentTime))
        guard remainingDuration > currentBufferDuration + minimumBufferGrowthSeconds else {
            return nil
        }

        let requiredBitrate = max(
            indicatedBitrate.isFinite ? indicatedBitrate : 0,
            Double(sourceBitrate ?? 0)
        )
        guard requiredBitrate > 0 else { return nil }

        let headroomRatio = observedBitrate / requiredBitrate
        guard headroomRatio >= aggressiveHeadroomRatio else { return nil }

        let target = min(remainingDuration, maximumWholeAssetBufferHintSeconds)
        guard target > currentBufferDuration + minimumBufferGrowthSeconds else {
            return nil
        }
        return target
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
}
