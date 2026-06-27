import AVFoundation
import Foundation
import Shared

enum DirectPlaySessionPolicy {
    static let materializedResumePositionStartupWaitTimeout: TimeInterval = 2.0
    private static let resumedSparseMinimumBufferedDuration: Double = 20
    private static let resumedSparseMinimumStableBufferDuration: Double = 2
    private static let localGatewayLowBitrateMinimumBufferedDuration: Double = 3
    private static let localGatewayHighBitrateMinimumBufferedDuration: Double = 6
    private static let localGatewayPrimedMinimumBufferedDuration: Double = 0.5
    private static let localGatewayPrimingPulseProgress: Double = 0.5
    private static let localGatewayLowBitratePrimingCacheDuration: Double = 75
    private static let localGatewayHighBitratePrimingCacheDuration: Double = 45
    private static let localGatewayLowBitratePrimedProgress: Double = 5
    private static let localGatewayHighBitratePrimedProgress: Double = 8
    private static let localGatewayActivePlaybackMinimumOffset: Int64 = 16 * 1_024 * 1_024

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
        transcodeStartOffset: Double,
        isPlaybackActive: Bool = false,
        allowPausedDirectPlayFirstFrame: Bool = false
    ) -> Bool {
        guard hasMarkedFirstFrame else { return false }
        guard itemStatus == .readyToPlay else { return false }
        if case .directPlay = route {
            guard isPlaybackActive || allowPausedDirectPlayFirstFrame else { return false }
        }
        return !shouldDelayFirstFrameUntilResumePosition(
            route: route,
            pendingResumeSeconds: pendingResumeSeconds,
            currentTime: currentTime,
            transcodeStartOffset: transcodeStartOffset
        )
    }

    static func shouldReleasePausedStartupAfterFirstFrame(
        route: PlaybackRoute,
        source: MediaSource?,
        resumeSeconds: Double?,
        preheatResult: PlaybackStartupPreheater.Result?,
        serverBaselineResult: PlaybackServerNetworkBaseline.Result?,
        isTVOS: Bool
    ) -> Bool {
        guard !isTVOS else { return false }
        guard (resumeSeconds ?? 0) <= 0 else { return false }
        guard isIPhoneNoStallGuardedDirectPlay(route: route, source: source) else { return false }
        guard let sourceBitrate = source?.bitrate, sourceBitrate > 0 else { return false }

        if let preheatResult,
           let rangeStart = preheatResult.rangeStart,
           rangeStart > 0,
           preheatResult.observedBitrate.isFinite,
           preheatResult.observedBitrate >= Double(sourceBitrate) * 1.5 {
            return true
        }

        if let serverBaselineResult,
           serverBaselineResult.observedBitrate.isFinite,
           serverBaselineResult.observedBitrate >= Double(sourceBitrate) * 3.0 {
            return true
        }

        return false
    }

    static func shouldReleaseSparseResumedDirectPlayStartup(
        route: PlaybackRoute,
        source: MediaSource?,
        resumeSeconds: Double,
        hasMarkedFirstFrame: Bool,
        currentTime: Double,
        itemStatus: AVPlayerItem.Status,
        transcodeStartOffset: Double,
        likelyToKeepUp: Bool,
        bufferedDuration: Double,
        bufferStableDuration: Double,
        preheatResult: PlaybackStartupPreheater.Result?,
        accessObservedBitrate: Double?,
        accessStallCount: Int?,
        selectedAudioTrackID: String?,
        isTVOS: Bool
    ) -> Bool {
        guard !isTVOS else { return false }
        guard resumeSeconds > 0 else { return false }
        guard isStallResistantDirectPlay(route: route, source: source) else { return false }
        guard let source, let sourceBitrate = source.bitrate, sourceBitrate > 0 else { return false }
        guard hasSelectedAudio(source: source, selectedAudioTrackID: selectedAudioTrackID) else { return false }
        if let accessStallCount, accessStallCount > 0 { return false }

        guard shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
            route: route,
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            pendingResumeSeconds: resumeSeconds,
            currentTime: currentTime,
            itemStatus: itemStatus,
            transcodeStartOffset: transcodeStartOffset,
            allowPausedDirectPlayFirstFrame: true
        ) else { return false }

        if hasHealthyNonZeroPreheat(preheatResult, sourceBitrate: sourceBitrate),
           hasHealthySparseAVPlayerBuffer(
               likelyToKeepUp: likelyToKeepUp,
               bufferedDuration: bufferedDuration,
               bufferStableDuration: bufferStableDuration
           ) {
            return true
        }

        return hasHealthySparseAccessLog(
            observedBitrate: accessObservedBitrate,
            sourceBitrate: sourceBitrate,
            likelyToKeepUp: likelyToKeepUp,
            bufferedDuration: bufferedDuration,
            bufferStableDuration: bufferStableDuration
        )
    }

    static func shouldReleaseLocalGatewayResumedDirectPlayStartup(
        route: PlaybackRoute,
        source: MediaSource?,
        resumeSeconds: Double,
        hasMarkedFirstFrame: Bool,
        currentTime: Double,
        itemStatus: AVPlayerItem.Status,
        transcodeStartOffset: Double,
        preheatResult: PlaybackStartupPreheater.Result?,
        likelyToKeepUp: Bool,
        bufferedDuration: Double,
        bufferStableDuration: Double,
        accessObservedBitrate: Double?,
        accessStallCount: Int?,
        selectedAudioTrackID: String?,
        gatewayDiagnostics: LocalMediaGatewayDiagnostics?,
        requirement: PlaybackStartupReadinessPolicy.Requirement,
        isTVOS: Bool
    ) -> Bool {
        guard !isTVOS else { return false }
        guard resumeSeconds > 0 else { return false }
        guard isStallResistantDirectPlay(route: route, source: source) else { return false }
        guard let source, let sourceBitrate = source.bitrate, sourceBitrate > 0 else { return false }
        guard let gatewayDiagnostics else { return false }
        guard hasSelectedAudio(source: source, selectedAudioTrackID: selectedAudioTrackID) else { return false }
        if let accessStallCount, accessStallCount > 0 { return false }

        guard shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
            route: route,
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            pendingResumeSeconds: resumeSeconds,
            currentTime: currentTime,
            itemStatus: itemStatus,
            transcodeStartOffset: transcodeStartOffset,
            allowPausedDirectPlayFirstFrame: true
        ) else { return false }
        guard hasHealthyNonZeroPreheat(preheatResult, sourceBitrate: sourceBitrate) else { return false }
        _ = bufferStableDuration
        guard likelyToKeepUp else { return false }
        guard hasMaterializedLocalGatewayPlaybackBuffer(
            sourceBitrate: sourceBitrate,
            likelyToKeepUp: likelyToKeepUp,
            bufferedDuration: bufferedDuration
        ) else { return false }

        let gatewayObservedBitrate = gatewayDiagnostics.observedBitrate ?? 0
        let accessBitrate = Int(accessObservedBitrate ?? 0)
        guard max(gatewayObservedBitrate, accessBitrate) >= Int(Double(sourceBitrate) * 1.5) else {
            return false
        }
        let minimumBufferDuration = max(requirement.minimumBufferDuration, resumedSparseMinimumBufferedDuration)
        guard !hasUncoveredActiveStreamingPlaybackWindow(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: minimumBufferDuration
        ) else { return false }
        if hasRequiredLocalGatewayCacheWindow(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: minimumBufferDuration,
            preheatResult: preheatResult
        ) {
            return true
        }
        return hasNearbyLocalGatewayPlaybackWindow(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: minimumBufferDuration,
            preheatResult: preheatResult
        )
    }

    static func shouldPrimeLocalGatewayResumedDirectPlayStartup(
        route: PlaybackRoute,
        source: MediaSource?,
        resumeSeconds: Double,
        hasMarkedFirstFrame: Bool,
        currentTime: Double,
        itemStatus: AVPlayerItem.Status,
        transcodeStartOffset: Double,
        preheatResult: PlaybackStartupPreheater.Result?,
        bufferedDuration: Double,
        accessStallCount: Int?,
        selectedAudioTrackID: String?,
        gatewayDiagnostics: LocalMediaGatewayDiagnostics?,
        requirement: PlaybackStartupReadinessPolicy.Requirement,
        isTVOS: Bool
    ) -> Bool {
        guard !isTVOS else { return false }
        guard resumeSeconds > 0 else { return false }
        guard isStallResistantDirectPlay(route: route, source: source) else { return false }
        guard let source, let sourceBitrate = source.bitrate, sourceBitrate > 0 else { return false }
        guard let gatewayDiagnostics else { return false }
        guard hasSelectedAudio(source: source, selectedAudioTrackID: selectedAudioTrackID) else { return false }
        if let accessStallCount, accessStallCount > 0 { return false }
        guard hasHealthyNonZeroPreheat(preheatResult, sourceBitrate: sourceBitrate) else { return false }
        guard shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
            route: route,
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            pendingResumeSeconds: resumeSeconds,
            currentTime: currentTime,
            itemStatus: itemStatus,
            transcodeStartOffset: transcodeStartOffset,
            allowPausedDirectPlayFirstFrame: true
        ) else { return false }
        guard hasLocalGatewayPrimingCacheWindow(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate,
            preheatResult: preheatResult,
            requirement: requirement
        ) || hasLocalGatewayAggregatePrimingMomentum(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: requirement.minimumBufferDuration
        ) || hasActiveStreamingPlaybackEvidence(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate
        ) else { return false }
        return bufferedDuration < localGatewayMinimumMaterializedBufferDuration(sourceBitrate: sourceBitrate)
    }

    static func shouldReleasePrimedLocalGatewayResumedDirectPlayStartup(
        route: PlaybackRoute,
        source: MediaSource?,
        resumeSeconds: Double,
        primingStartTime: Double,
        hasMarkedFirstFrame: Bool,
        currentTime: Double,
        itemStatus: AVPlayerItem.Status,
        transcodeStartOffset: Double,
        preheatResult: PlaybackStartupPreheater.Result?,
        likelyToKeepUp: Bool,
        bufferedDuration: Double,
        accessObservedBitrate: Double?,
        accessStallCount: Int?,
        selectedAudioTrackID: String?,
        gatewayDiagnostics: LocalMediaGatewayDiagnostics?,
        requirement: PlaybackStartupReadinessPolicy.Requirement,
        isTVOS: Bool
    ) -> Bool {
        guard !isTVOS else { return false }
        guard resumeSeconds > 0 else { return false }
        guard isStallResistantDirectPlay(route: route, source: source) else { return false }
        guard let source, let sourceBitrate = source.bitrate, sourceBitrate > 0 else { return false }
        guard let gatewayDiagnostics else { return false }
        guard hasSelectedAudio(source: source, selectedAudioTrackID: selectedAudioTrackID) else { return false }
        if let accessStallCount, accessStallCount > 0 { return false }
        guard likelyToKeepUp, bufferedDuration >= localGatewayPrimedMinimumBufferedDuration else { return false }
        guard hasHealthyNonZeroPreheat(preheatResult, sourceBitrate: sourceBitrate) else { return false }
        guard hasObservedPrimedPlaybackProgress(
            primingStartTime: primingStartTime,
            currentTime: currentTime,
            sourceBitrate: sourceBitrate
        ) else { return false }
        guard shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
            route: route,
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            pendingResumeSeconds: resumeSeconds,
            currentTime: primingStartTime,
            itemStatus: itemStatus,
            transcodeStartOffset: transcodeStartOffset,
            isPlaybackActive: true,
            allowPausedDirectPlayFirstFrame: true
        ) else { return false }

        let gatewayObservedBitrate = gatewayDiagnostics.observedBitrate ?? 0
        let accessBitrate = Int(accessObservedBitrate ?? 0)
        guard max(gatewayObservedBitrate, accessBitrate) >= Int(Double(sourceBitrate) * 1.5) else {
            return false
        }
        let minimumBufferDuration = max(requirement.minimumBufferDuration, resumedSparseMinimumBufferedDuration)
        if hasRequiredLocalGatewayCacheWindow(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: minimumBufferDuration,
            preheatResult: preheatResult
        ) {
            return true
        }
        if hasNearbyLocalGatewayPlaybackWindow(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: minimumBufferDuration,
            preheatResult: preheatResult
        ) {
            return true
        }
        if hasActiveStreamingPlaybackEvidence(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate
        ) {
            return true
        }
        return hasLocalGatewayAggregatePrimingMomentum(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: requirement.minimumBufferDuration
        )
    }

    static func shouldPauseLocalGatewayPrimingPlayback(
        route: PlaybackRoute,
        source: MediaSource?,
        primingStartTime: Double,
        currentTime: Double,
        bufferedDuration: Double,
        gatewayDiagnostics: LocalMediaGatewayDiagnostics? = nil,
        isTVOS: Bool
    ) -> Bool {
        guard !isTVOS else { return false }
        guard isStallResistantDirectPlay(route: route, source: source) else { return false }
        guard let sourceBitrate = source?.bitrate, sourceBitrate > 0 else { return false }
        guard primingStartTime.isFinite, currentTime.isFinite else { return false }
        guard currentTime - primingStartTime >= localGatewayPrimingPulseProgress else { return false }
        if let gatewayDiagnostics,
           hasActiveStreamingPlaybackEvidence(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate
           ) {
            return false
        }
        return bufferedDuration < localGatewayMinimumMaterializedBufferDuration(sourceBitrate: sourceBitrate)
    }

    static func shouldResumeLocalGatewayPrimingPlayback(
        route: PlaybackRoute,
        source: MediaSource?,
        resumeSeconds: Double,
        currentTime: Double,
        preheatResult: PlaybackStartupPreheater.Result?,
        accessStallCount: Int?,
        selectedAudioTrackID: String?,
        gatewayDiagnostics: LocalMediaGatewayDiagnostics?,
        requirement: PlaybackStartupReadinessPolicy.Requirement,
        isTVOS: Bool
    ) -> Bool {
        guard !isTVOS else { return false }
        guard resumeSeconds > 0 else { return false }
        guard isStallResistantDirectPlay(route: route, source: source) else { return false }
        guard let source, let sourceBitrate = source.bitrate, sourceBitrate > 0 else { return false }
        guard let gatewayDiagnostics else { return false }
        guard hasSelectedAudio(source: source, selectedAudioTrackID: selectedAudioTrackID) else { return false }
        if let accessStallCount, accessStallCount > 0 { return false }
        guard isResumePositionSatisfied(currentTime: currentTime, resumeSeconds: resumeSeconds, toleranceSeconds: 12) else {
            return false
        }
        guard hasHealthyNonZeroPreheat(preheatResult, sourceBitrate: sourceBitrate) else { return false }

        let minimumBufferDuration = localGatewayPrimingCacheDuration(
            sourceBitrate: sourceBitrate,
            requirement: requirement
        )
        let hasActivePlaybackEvidence = hasActiveStreamingPlaybackEvidence(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate
        )
        guard hasActivePlaybackEvidence || !hasUncoveredActiveStreamingPlaybackWindow(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: max(requirement.minimumBufferDuration, resumedSparseMinimumBufferedDuration)
        ) else { return false }
        if hasRequiredLocalGatewayCacheWindow(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: minimumBufferDuration,
            preheatResult: preheatResult
        ) {
            return true
        }
        if hasActivePlaybackEvidence {
            return true
        }
        if hasLocalGatewayAggregatePrimingMomentum(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: requirement.minimumBufferDuration
        ) {
            return true
        }
        return hasNearbyLocalGatewayPlaybackWindow(
            diagnostics: gatewayDiagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: minimumBufferDuration,
            preheatResult: preheatResult
        )
    }

    static func requiresStableStartupBuffer(
        route: PlaybackRoute,
        source: MediaSource?,
        requirement: PlaybackStartupReadinessPolicy.Requirement,
        isTVOS: Bool
    ) -> Bool {
        guard !isTVOS else { return false }
        guard !requirement.allowsTimeoutStart else { return false }
        return isStallResistantDirectPlay(route: route, source: source)
    }

    static func hasStableStartupBuffer(
        bufferedDuration: Double,
        likelyToKeepUp: Bool,
        stableDuration: Double
    ) -> Bool {
        hasHealthySparseAVPlayerBuffer(
            likelyToKeepUp: likelyToKeepUp,
            bufferedDuration: bufferedDuration,
            bufferStableDuration: stableDuration
        )
    }

    static func shouldWaitForMaterializedResumePositionBeforeStartupSeek(
        route: PlaybackRoute,
        pendingResumeSeconds: Double?,
        currentTime: Double,
        itemStatus: AVPlayerItem.Status,
        transcodeStartOffset: Double,
        directPlayAutoplayStartupGateActive: Bool
    ) -> Bool {
        guard directPlayAutoplayStartupGateActive else { return false }
        guard itemStatus == .readyToPlay else { return false }
        guard case .directPlay = route else { return false }
        guard transcodeStartOffset <= 0 else { return false }
        guard let pendingResumeSeconds, pendingResumeSeconds > 0 else { return false }
        return !isResumePositionSatisfied(
            currentTime: currentTime,
            resumeSeconds: pendingResumeSeconds
        )
    }

    static func shouldAcceptMaterializedResumeSeek(
        currentTime: Double,
        resumeSeconds: Double,
        itemStatus: AVPlayerItem.Status,
        hasMarkedFirstFrame: Bool
    ) -> Bool {
        guard hasMarkedFirstFrame else { return false }
        guard itemStatus == .readyToPlay else { return false }
        return isResumePositionSatisfied(
            currentTime: currentTime,
            resumeSeconds: resumeSeconds
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

    /// A stall this soon after the first frame means direct play couldn't sustain even the opening
    /// seconds — the connection can't carry the source bitrate right now (device: stall at 6 s on a
    /// 17 Mbps link vs a 26 Mbps source). Escalate to the watchable SDR transcode immediately rather
    /// than re-buffering DV that will just re-stall. Stalls AFTER this window are far more likely a
    /// transient blip on an otherwise-good link and are ridden out instead.
    static let earlyStallEscalationSeconds: Double = 12

    static func shouldMarkRouteFragileAfterPostStartStall(
        route: PlaybackRoute,
        source: MediaSource?,
        recentStallCount: Int,
        elapsedSecondsSinceFirstFrame: Double?
    ) -> Bool {
        guard let elapsed = elapsedSecondsSinceFirstFrame else { return false }
        guard isStallResistantDirectPlay(route: route, source: source) else { return false }
        // EARLY stall (couldn't sustain even the opening ~12 s) → the connection can't carry the
        // source bitrate → escalate to watchable SDR on the FIRST stall (no point re-buffering DV
        // that will re-stall). LATER stall → likely a transient blip on a good link → ride it out
        // (require repeated stalls in the 12 s window; the time-based sustained-stall watchdog also
        // backstops a single stall that stays stuck). This split keeps full DV through brief blips
        // while dropping a genuinely-too-slow connection to watchable HD fast (minimal cut).
        if elapsed < earlyStallEscalationSeconds { return recentStallCount >= 1 }
        return recentStallCount >= 3
    }

    /// How long a post-start direct-play stall may persist (no playback progress) before the
    /// adaptive never-freeze backstop escalates to the watchable transcode. A transient network
    /// blip on a fast link re-buffers well within this window and keeps full-quality Dolby Vision;
    /// only a stall still stuck after this long indicates the connection genuinely can't carry the
    /// original bitrate right now, at which point dropping to a sustainable SDR transcode beats
    /// freezing. Tuned to comfortably outlast ordinary re-buffers while bounding the worst-case
    /// visible pause before the switch.
    static let sustainedStallEscalationGraceSeconds: Double = 8

    struct SteadyStateBuffering: Equatable {
        let forwardBufferDuration: Double
        let waitsToMinimizeStalling: Bool
    }

    /// Forward buffer (seconds) ReelFin keeps once a direct-play stream is actually
    /// rendering. Independent of bitrate because it is a duration of media, not bytes.
    ///
    /// Per Apple's `AVPlayerItem.preferredForwardBufferDuration` doc, a low value increases the
    /// chance of stall/re-buffer and a high value trades system resources for resilience. With a
    /// fast start (small initial buffer), a deep ongoing cushion is what absorbs a transient
    /// network/QUIC blip mid-playback (observed: a single ~28 s stall on a 100 Mbps link). 60 s of
    /// a 26 Mbps original ≈ 195 MB held — well within budget on a modern device — and lets AVPlayer
    /// ride out multi-second connection gaps without ever surfacing a rebuffer to the user.
    static let steadyStateForwardBufferSeconds: Double = 60
    /// tvOS can afford the same (or more) cushion given its larger cache budget; the tvOS
    /// adaptive-caching ramp grows it further on healthy networks (cooperative via max()).
    static let tvOSSteadyStateForwardBufferSeconds: Double = 60

    /// Steady-state buffering applied right after the first decoded frame.
    ///
    /// Startup is intentionally latency-biased (tiny forward buffer, `waits == false`)
    /// to get the first frame fast. That same config is fatal *during* playback: a
    /// 0.75–2 s buffer with `automaticallyWaitsToMinimizeStalling == false` drains on
    /// the first network dip below real-time bitrate and AVPlayer freezes to rebuffer
    /// — the user-visible "it cuts to reload after ~1 min". Once we have a frame we no
    /// longer need the latency bias, so we switch direct play to a stability-biased
    /// buffer that lets AVPlayer maintain a real cushion and manage rebuffering itself.
    ///
    /// Shared by iOS and tvOS (same algorithm, platform-tuned floor). On tvOS the existing
    /// adaptive-caching ramp keeps cooperating via `max()`. Returns `nil` only for routes
    /// that manage their own buffering (HLS / transcode).
    static func steadyStateBuffering(
        route: PlaybackRoute,
        source: MediaSource?,
        currentForwardBufferDuration: Double,
        isTVOS: Bool
    ) -> SteadyStateBuffering? {
        _ = source
        guard case let .directPlay(url) = route else { return nil }
        guard url.pathExtension.lowercased() != "m3u8" else { return nil }
        let floor = isTVOS ? tvOSSteadyStateForwardBufferSeconds : steadyStateForwardBufferSeconds
        return SteadyStateBuffering(
            forwardBufferDuration: max(currentForwardBufferDuration, floor),
            waitsToMinimizeStalling: true
        )
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
        true
    }

    static func shouldPauseForPostStartStallRebuffer(isTVOS: Bool) -> Bool {
        false
    }

    static func postStartStallRebufferTimeout(
        recentStallCount: Int,
        isTVOS: Bool
    ) -> Double {
        guard !isTVOS else { return 0 }
        return recentStallCount >= 3 ? 45 : 30
    }

    static func isIPhoneNoStallGuardedDirectPlay(route: PlaybackRoute, source: MediaSource?) -> Bool {
        guard case let .directPlay(url) = route else { return false }
        guard url.pathExtension.lowercased() != "m3u8" else { return false }
        guard let source else { return false }
        return source.isPremiumVideoSource || (source.bitrate ?? 0) >= 18_000_000
    }

    static func isStallResistantDirectPlay(route: PlaybackRoute, source: MediaSource?) -> Bool {
        guard case let .directPlay(url) = route else { return false }
        guard url.pathExtension.lowercased() != "m3u8" else { return false }
        guard let source else { return false }
        return source.isPremiumVideoSource || (source.bitrate ?? 0) >= 12_000_000
    }

    private static func hasSelectedAudio(source: MediaSource, selectedAudioTrackID: String?) -> Bool {
        let expectsAudio = !source.audioTracks.isEmpty || !(source.audioCodec ?? "").isEmpty
        guard expectsAudio else { return true }
        guard let selectedAudioTrackID, !selectedAudioTrackID.isEmpty else { return false }
        guard !source.audioTracks.isEmpty else { return true }
        return source.audioTracks.contains { $0.id == selectedAudioTrackID }
    }

    private static func hasHealthyNonZeroPreheat(
        _ preheatResult: PlaybackStartupPreheater.Result?,
        sourceBitrate: Int
    ) -> Bool {
        guard let preheatResult else { return false }
        guard let rangeStart = preheatResult.rangeStart, rangeStart > 0 else { return false }
        guard preheatResult.observedBitrate.isFinite else { return false }
        return preheatResult.observedBitrate >= Double(sourceBitrate) * 1.5
    }

    private static func hasHealthySparseAccessLog(
        observedBitrate: Double?,
        sourceBitrate: Int,
        likelyToKeepUp: Bool,
        bufferedDuration: Double,
        bufferStableDuration: Double
    ) -> Bool {
        guard hasHealthySparseAVPlayerBuffer(
            likelyToKeepUp: likelyToKeepUp,
            bufferedDuration: bufferedDuration,
            bufferStableDuration: bufferStableDuration
        ) else { return false }
        guard let observedBitrate, observedBitrate.isFinite else { return false }
        return observedBitrate >= Double(sourceBitrate) * 1.5
    }

    private static func hasHealthySparseAVPlayerBuffer(
        likelyToKeepUp: Bool,
        bufferedDuration: Double,
        bufferStableDuration: Double
    ) -> Bool {
        guard likelyToKeepUp else { return false }
        guard bufferStableDuration.isFinite, bufferStableDuration >= resumedSparseMinimumStableBufferDuration else {
            return false
        }
        return bufferedDuration.isFinite && bufferedDuration >= resumedSparseMinimumBufferedDuration
    }

    private static func hasMaterializedLocalGatewayPlaybackBuffer(
        sourceBitrate: Int,
        likelyToKeepUp: Bool,
        bufferedDuration: Double
    ) -> Bool {
        guard likelyToKeepUp else { return false }
        guard bufferedDuration.isFinite else { return false }
        return bufferedDuration >= localGatewayMinimumMaterializedBufferDuration(sourceBitrate: sourceBitrate)
    }

    private static func localGatewayMinimumMaterializedBufferDuration(sourceBitrate: Int) -> Double {
        sourceBitrate >= 18_000_000
            ? localGatewayHighBitrateMinimumBufferedDuration
            : localGatewayLowBitrateMinimumBufferedDuration
    }

    private static func localGatewayPrimingCacheDuration(
        sourceBitrate: Int,
        requirement: PlaybackStartupReadinessPolicy.Requirement
    ) -> Double {
        let floor = sourceBitrate >= 18_000_000
            ? localGatewayHighBitratePrimingCacheDuration
            : localGatewayLowBitratePrimingCacheDuration
        return max(requirement.preferredBufferDuration, resumedSparseMinimumBufferedDuration, floor)
    }

    private static func hasLocalGatewayPrimingCacheWindow(
        diagnostics: LocalMediaGatewayDiagnostics,
        sourceBitrate: Int,
        preheatResult: PlaybackStartupPreheater.Result?,
        requirement: PlaybackStartupReadinessPolicy.Requirement
    ) -> Bool {
        let minimumBufferDuration = localGatewayPrimingCacheDuration(
            sourceBitrate: sourceBitrate,
            requirement: requirement
        )
        if hasRequiredLocalGatewayCacheWindow(
            diagnostics: diagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: minimumBufferDuration,
            preheatResult: preheatResult
        ) {
            return true
        }
        return hasNearbyLocalGatewayPlaybackWindow(
            diagnostics: diagnostics,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: minimumBufferDuration,
            preheatResult: preheatResult
        )
    }

    private static func hasLocalGatewayAggregatePrimingMomentum(
        diagnostics: LocalMediaGatewayDiagnostics,
        sourceBitrate: Int,
        minimumBufferDuration: Double
    ) -> Bool {
        let observedBitrate = diagnostics.observedBitrate ?? 0
        guard observedBitrate >= Int(Double(sourceBitrate) * 1.5) else { return false }
        let requiredBytes = Int64(Double(sourceBitrate) * max(1, minimumBufferDuration) / 8)
        let minimumBytes = max(Int64(24 * 1_024 * 1_024), requiredBytes)
        return (diagnostics.cachedBytes ?? 0) >= minimumBytes
    }

    private static func hasActiveStreamingPlaybackEvidence(
        diagnostics: LocalMediaGatewayDiagnostics,
        sourceBitrate: Int
    ) -> Bool {
        guard diagnostics.activePrefetchIsStreamingPlayback else { return false }
        guard let activeStartOffset = diagnostics.activePrefetchStartOffset,
              activeStartOffset >= localGatewayActivePlaybackMinimumOffset else {
            return false
        }
        if let activeEndOffset = diagnostics.activePrefetchEndOffset,
           activeEndOffset <= activeStartOffset {
            return false
        }
        let observedBitrate = diagnostics.observedBitrate ?? 0
        return observedBitrate >= Int(Double(sourceBitrate) * 1.5)
    }

    private static func hasUncoveredActiveStreamingPlaybackWindow(
        diagnostics: LocalMediaGatewayDiagnostics,
        sourceBitrate: Int,
        minimumBufferDuration: Double
    ) -> Bool {
        guard diagnostics.activePrefetchIsStreamingPlayback else { return false }
        guard let activeStartOffset = diagnostics.activePrefetchStartOffset,
              activeStartOffset >= localGatewayActivePlaybackMinimumOffset else {
            return false
        }
        let requiredBytes = Int64(Double(sourceBitrate) * minimumBufferDuration / 8)
        guard requiredBytes > 0 else { return false }
        return !diagnostics.nonZeroCachedRanges.contains { range in
            guard range.offset <= activeStartOffset else { return false }
            let rangeEnd = range.offset + range.length
            guard activeStartOffset < rangeEnd else { return false }
            return rangeEnd - activeStartOffset >= requiredBytes
        }
    }

    private static func hasObservedPrimedPlaybackProgress(
        primingStartTime: Double,
        currentTime: Double,
        sourceBitrate: Int
    ) -> Bool {
        guard primingStartTime.isFinite, currentTime.isFinite else { return false }
        let minimumProgress = sourceBitrate >= 18_000_000
            ? localGatewayHighBitratePrimedProgress
            : localGatewayLowBitratePrimedProgress
        return currentTime - primingStartTime >= minimumProgress
    }

    private static func hasRequiredLocalGatewayCacheWindow(
        diagnostics: LocalMediaGatewayDiagnostics,
        sourceBitrate: Int,
        minimumBufferDuration: Double,
        preheatResult: PlaybackStartupPreheater.Result?
    ) -> Bool {
        let requiredBytes = Int64(Double(sourceBitrate) * minimumBufferDuration / 8)
        if let rangeStart = preheatResult?.rangeStart, rangeStart > 0 {
            return diagnostics.nonZeroCachedRanges.contains {
                hasRequiredLocalGatewayStartupWindow(
                    range: $0,
                    startupOffset: rangeStart,
                    totalLength: diagnostics.totalLength,
                    requiredBytes: requiredBytes
                )
            }
        }

        let minimumCacheOffset = minimumLocalGatewayPlaybackCacheOffset(
            preheatResult: preheatResult,
            sourceBitrate: sourceBitrate,
            minimumBufferDuration: minimumBufferDuration
        )
        let candidates = [
            (diagnostics.latestNonZeroCachedOffset, diagnostics.latestNonZeroCachedRangeLength),
            (diagnostics.largestNonZeroCachedOffset, diagnostics.largestNonZeroCachedRangeLength)
        ]
        return candidates.contains { offset, length in
            hasRequiredLocalGatewayCandidateWindow(
                offset: offset,
                length: length,
                totalLength: diagnostics.totalLength,
                requiredBytes: requiredBytes,
                minimumCacheOffset: minimumCacheOffset
            )
        }
    }

    private static func hasNearbyLocalGatewayPlaybackWindow(
        diagnostics: LocalMediaGatewayDiagnostics,
        sourceBitrate: Int,
        minimumBufferDuration: Double,
        preheatResult: PlaybackStartupPreheater.Result?
    ) -> Bool {
        guard let rangeStart = preheatResult?.rangeStart, rangeStart > 0 else { return false }
        let requiredBytes = Int64(Double(sourceBitrate) * minimumBufferDuration / 8)
        let tolerance = localGatewayPlaybackWindowToleranceBytes(
            requiredBytes: requiredBytes
        )
        return diagnostics.nonZeroCachedRanges.contains {
            isNearbyLocalGatewayPlaybackWindow(
                range: $0,
                startupOffset: rangeStart,
                totalLength: diagnostics.totalLength,
                requiredBytes: requiredBytes,
                tolerance: tolerance
            )
        }
    }

    private static func hasRequiredLocalGatewayCandidateWindow(
        offset: Int64?,
        length: Int64?,
        totalLength: Int64?,
        requiredBytes: Int64,
        minimumCacheOffset: Int64?
    ) -> Bool {
        guard let offset, offset > 0 else { return false }
        guard let length, length > 0 else { return false }
        if let minimumCacheOffset, offset < minimumCacheOffset {
            return false
        }

        let availableBytes: Int64
        if let totalLength, totalLength > offset {
            availableBytes = max(1, min(requiredBytes, totalLength - offset))
        } else {
            availableBytes = requiredBytes
        }
        return length >= availableBytes
    }

    private static func hasRequiredLocalGatewayStartupWindow(
        range: LocalMediaGatewayCachedRange,
        startupOffset: Int64,
        totalLength: Int64?,
        requiredBytes: Int64
    ) -> Bool {
        guard range.offset > 0, range.length > 0 else { return false }
        guard startupOffset >= range.offset else { return false }
        let rangeEnd = range.offset + range.length
        guard startupOffset < rangeEnd else { return false }

        let requiredWindow: Int64
        if let totalLength, totalLength > startupOffset {
            requiredWindow = max(1, min(requiredBytes, totalLength - startupOffset))
        } else {
            requiredWindow = requiredBytes
        }
        return rangeEnd - startupOffset >= requiredWindow
    }

    private static func isNearbyLocalGatewayPlaybackWindow(
        range: LocalMediaGatewayCachedRange,
        startupOffset: Int64,
        totalLength: Int64?,
        requiredBytes: Int64,
        tolerance: Int64
    ) -> Bool {
        guard range.offset > 0, range.length > 0 else { return false }
        let rangeEnd = range.offset + range.length
        guard startupOffset >= range.offset - tolerance else { return false }
        guard startupOffset <= rangeEnd + tolerance else { return false }

        let availableBytes: Int64
        if let totalLength, totalLength > range.offset {
            availableBytes = max(1, min(requiredBytes, totalLength - range.offset))
        } else {
            availableBytes = requiredBytes
        }
        return range.length >= availableBytes
    }

    private static func minimumLocalGatewayPlaybackCacheOffset(
        preheatResult: PlaybackStartupPreheater.Result?,
        sourceBitrate: Int,
        minimumBufferDuration: Double
    ) -> Int64? {
        guard let rangeStart = preheatResult?.rangeStart, rangeStart > 0 else { return nil }
        let requiredBytes = Int64(Double(sourceBitrate) * minimumBufferDuration / 8)
        let tolerance = localGatewayPlaybackWindowToleranceBytes(requiredBytes: requiredBytes)
        return max(1, Int64(rangeStart) - tolerance)
    }

    private static func localGatewayPlaybackWindowToleranceBytes(requiredBytes: Int64) -> Int64 {
        let safeRequiredBytes = min(requiredBytes, Int64.max / 4)
        return max(Int64(128 * 1_024 * 1_024), safeRequiredBytes * 4)
    }
}
