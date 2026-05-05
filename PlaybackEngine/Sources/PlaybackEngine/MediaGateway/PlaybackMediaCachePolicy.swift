import Foundation
import Shared

public enum PlaybackMediaCachePolicy {
    public enum Platform: Sendable { case iOS, tvOS }
    public enum RouteKind: Sendable { case directPlayOriginal, nativeOriginal, hlsFallback }
    public enum Phase: String, Sendable { case startup, steady, deep, complete, paused }

    public struct Context: Sendable {
        public var platform: Platform
        public var mediaCacheMode: MediaCacheMode
        public var routeKind: RouteKind
        public var sourceBitrate: Int
        public var observedBitrate: Int
        public var currentBufferDuration: TimeInterval
        public var playbackElapsedSeconds: TimeInterval
        public var remainingDuration: TimeInterval
        public var isExpensiveNetwork: Bool
        public var isConstrainedNetwork: Bool
        public var availableDiskBytes: Int64
        public var activeItemCachedBytes: Int64

        public init(
            platform: Platform,
            mediaCacheMode: MediaCacheMode,
            routeKind: RouteKind,
            sourceBitrate: Int,
            observedBitrate: Int,
            currentBufferDuration: TimeInterval,
            playbackElapsedSeconds: TimeInterval,
            remainingDuration: TimeInterval,
            isExpensiveNetwork: Bool,
            isConstrainedNetwork: Bool,
            availableDiskBytes: Int64,
            activeItemCachedBytes: Int64
        ) {
            self.platform = platform
            self.mediaCacheMode = mediaCacheMode
            self.routeKind = routeKind
            self.sourceBitrate = sourceBitrate
            self.observedBitrate = observedBitrate
            self.currentBufferDuration = currentBufferDuration
            self.playbackElapsedSeconds = playbackElapsedSeconds
            self.remainingDuration = remainingDuration
            self.isExpensiveNetwork = isExpensiveNetwork
            self.isConstrainedNetwork = isConstrainedNetwork
            self.availableDiskBytes = availableDiskBytes
            self.activeItemCachedBytes = activeItemCachedBytes
        }
    }

    public struct Decision: Equatable, Sendable {
        public var phase: Phase
        public var targetAheadSeconds: TimeInterval
        public var maxActiveItemBytes: Int64
        public var allowCompleteItem: Bool
        public var prefetchConcurrency: Int
        public var reason: String
    }

    public static func decision(context: Context) -> Decision {
        if context.mediaCacheMode == .off {
            return paused(reason: "cache_mode_off", cachedBytes: context.activeItemCachedBytes)
        }
        if context.availableDiskBytes < 512 * mib {
            return paused(reason: "low_storage", cachedBytes: context.activeItemCachedBytes)
        }
        if context.routeKind == .hlsFallback {
            return make(.steady, seconds: 60, context: context, complete: false, concurrency: 1, reason: "hls_session_cache")
        }

        let headroom = Double(max(context.observedBitrate, 0)) / Double(max(context.sourceBitrate, 1))
        switch context.platform {
        case .tvOS:
            return tvOSDecision(context: context, headroom: headroom)
        case .iOS:
            return iOSDecision(context: context, headroom: headroom)
        }
    }

    private static func tvOSDecision(context: Context, headroom: Double) -> Decision {
        if context.mediaCacheMode == .reduced {
            return make(.steady, seconds: 180, context: context, complete: false, concurrency: 1, reason: "tvos_reduced")
        }
        if headroom >= 2.5, context.playbackElapsedSeconds >= 300, context.remainingDuration > 0 {
            return make(.complete, seconds: context.remainingDuration, context: context, complete: true, concurrency: 3, reason: "tvos_complete")
        }
        if headroom >= 2.0, context.playbackElapsedSeconds >= 120 {
            return make(.deep, seconds: 900, context: context, complete: false, concurrency: 2, reason: "tvos_deep")
        }
        if headroom >= 1.25 {
            return make(.steady, seconds: 240, context: context, complete: false, concurrency: 1, reason: "tvos_steady")
        }
        return make(.startup, seconds: 45, context: context, complete: false, concurrency: 1, reason: "tvos_startup")
    }

    private static func iOSDecision(context: Context, headroom: Double) -> Decision {
        if context.isExpensiveNetwork || context.isConstrainedNetwork || context.mediaCacheMode == .reduced {
            return make(.steady, seconds: 120, context: context, complete: false, concurrency: 1, reason: "ios_constrained")
        }
        if headroom >= 2.5, context.playbackElapsedSeconds >= 240 {
            return make(.deep, seconds: 420, context: context, complete: false, concurrency: 1, reason: "ios_wifi_deep")
        }
        if headroom >= 1.25 {
            return make(.steady, seconds: 180, context: context, complete: false, concurrency: 1, reason: "ios_steady")
        }
        return make(.startup, seconds: 30, context: context, complete: false, concurrency: 1, reason: "ios_startup")
    }

    private static func make(
        _ phase: Phase,
        seconds: TimeInterval,
        context: Context,
        complete: Bool,
        concurrency: Int,
        reason: String
    ) -> Decision {
        let budget = max(0, context.availableDiskBytes - 512 * mib)
        let targetBytes = Int64(Double(max(context.sourceBitrate, 1)) * max(seconds, 0) / 8)
        return Decision(
            phase: phase,
            targetAheadSeconds: seconds,
            maxActiveItemBytes: min(budget, max(context.activeItemCachedBytes, targetBytes)),
            allowCompleteItem: complete,
            prefetchConcurrency: concurrency,
            reason: reason
        )
    }

    private static func paused(reason: String, cachedBytes: Int64) -> Decision {
        Decision(
            phase: .paused,
            targetAheadSeconds: 0,
            maxActiveItemBytes: cachedBytes,
            allowCompleteItem: false,
            prefetchConcurrency: 0,
            reason: reason
        )
    }

    private static let mib: Int64 = 1_024 * 1_024
}
