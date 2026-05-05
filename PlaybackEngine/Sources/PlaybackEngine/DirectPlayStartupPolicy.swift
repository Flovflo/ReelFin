import Foundation

enum DirectPlayStartupPolicy {
    enum Mode: Equatable { case fast, guarded, blocked }

    struct Decision: Equatable {
        let mode: Mode
        let minimumBufferDuration: Double
        let preferredBufferDuration: Double
        let timeout: Double
        let allowsTimeoutStart: Bool
        let failureReason: StartupFailureReason?
    }

    private static let guardedBitrateThreshold = 12_000_000
    private static let badHeadroomRatio = 0.85
    private static let fastHeadroomRatio = 1.75
    private static let baselineBadHeadroomRatio = 1.05
    private static let baselineGuardedHeadroomRatio = 1.25
    private static let baselineFastHeadroomRatio = 3.0

    static func decision(
        route: PlaybackRoute,
        sourceBitrate: Int?,
        preheatResult: PlaybackStartupPreheater.Result?,
        isTVOS: Bool
    ) -> Decision {
        decision(
            route: route,
            sourceBitrate: sourceBitrate,
            itemPreheatResult: preheatResult,
            serverBaselineResult: nil,
            isTVOS: isTVOS
        )
    }

    static func decision(
        route: PlaybackRoute,
        sourceBitrate: Int?,
        itemPreheatResult: PlaybackStartupPreheater.Result?,
        serverBaselineResult: PlaybackServerNetworkBaseline.Result?,
        isTVOS: Bool,
        now: Date = Date()
    ) -> Decision {
        guard isProgressiveDirectPlay(route) else {
            return fastDecision(isTVOS: isTVOS)
        }

        let bitrate = sourceBitrate ?? 0
        guard bitrate >= guardedBitrateThreshold else {
            return fastDecision(isTVOS: isTVOS)
        }

        if let itemPreheatResult {
            return decisionFromItemPreheat(
                itemPreheatResult,
                sourceBitrate: bitrate,
                isTVOS: isTVOS
            )
        }

        if let serverBaselineResult, serverBaselineResult.isFresh(at: now) {
            return decisionFromServerBaseline(
                serverBaselineResult,
                sourceBitrate: bitrate,
                isTVOS: isTVOS
            )
        }

        return guardedDecision(isTVOS: isTVOS)
    }

    private static func decisionFromItemPreheat(
        _ preheatResult: PlaybackStartupPreheater.Result,
        sourceBitrate: Int,
        isTVOS: Bool
    ) -> Decision {
        let observedBitrate = preheatResult.observedBitrate
        guard observedBitrate.isFinite, observedBitrate > 0 else {
            return blockedDecision(isTVOS: isTVOS)
        }

        let headroom = observedBitrate / Double(sourceBitrate)
        if headroom < badHeadroomRatio { return blockedDecision(isTVOS: isTVOS) }
        if headroom >= fastHeadroomRatio { return fastDecision(isTVOS: isTVOS) }
        return guardedDecision(isTVOS: isTVOS)
    }

    private static func decisionFromServerBaseline(
        _ baselineResult: PlaybackServerNetworkBaseline.Result,
        sourceBitrate: Int,
        isTVOS: Bool
    ) -> Decision {
        let observedBitrate = baselineResult.observedBitrate
        guard observedBitrate.isFinite, observedBitrate > 0 else {
            return blockedDecision(isTVOS: isTVOS)
        }

        let headroom = observedBitrate / Double(sourceBitrate)
        if headroom < baselineBadHeadroomRatio { return blockedDecision(isTVOS: isTVOS) }
        if headroom >= baselineFastHeadroomRatio { return fastDecision(isTVOS: isTVOS) }
        if headroom >= baselineGuardedHeadroomRatio { return guardedDecision(isTVOS: isTVOS) }
        return blockedDecision(isTVOS: isTVOS)
    }

    static func guardedDecision(isTVOS: Bool) -> Decision {
        Decision(
            mode: .guarded,
            minimumBufferDuration: isTVOS ? 4 : 2,
            preferredBufferDuration: isTVOS ? 4 : 2,
            timeout: isTVOS ? 6 : 4,
            allowsTimeoutStart: true,
            failureReason: nil
        )
    }

    private static func fastDecision(isTVOS: Bool) -> Decision {
        Decision(
            mode: .fast,
            minimumBufferDuration: 0,
            preferredBufferDuration: 0,
            timeout: isTVOS ? 3 : 2,
            allowsTimeoutStart: true,
            failureReason: nil
        )
    }

    private static func blockedDecision(isTVOS: Bool) -> Decision {
        Decision(
            mode: .blocked,
            minimumBufferDuration: isTVOS ? 4 : 2,
            preferredBufferDuration: isTVOS ? 4 : 2,
            timeout: 0,
            allowsTimeoutStart: false,
            failureReason: .directPlayPreflightInsufficient
        )
    }

    private static func isProgressiveDirectPlay(_ route: PlaybackRoute) -> Bool {
        guard case let .directPlay(url) = route else { return false }
        return !["m3u8", "m3u"].contains(url.pathExtension.lowercased())
    }
}
