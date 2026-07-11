import AVFoundation
import Foundation
import NativeMediaCore
import Observation
import Shared

/// Decides which playback signals are strong enough to remove the launch cover.
///
/// A progressing `AVPlayerItem` proves that the media clock is alive, not that pixels reached the
/// screen. iOS gets its proof from `AVPlayerViewController.isReadyForDisplay`; local tvOS playback
/// gets it from the attached pixel-buffer probe. AirPlay is the sole timeline exception because
/// the frames are rendered on the receiver and therefore cannot be sampled locally.
enum CustomPlayerFirstFrameProofPolicy {
    static func acceptsLocalPixelProbe(isTVOS: Bool, videoFramesObserved: Bool) -> Bool {
        // The probe is a decoder/liveness heartbeat, not presentation evidence. On tvOS it can
        // yield a frame before AVPlayerViewController has attached a visible render surface,
        // which removed the launch cover into a black screen.
        _ = isTVOS
        _ = videoFramesObserved
        return false
    }

    static func acceptsTimelineProgress(
        isTVOS: Bool,
        isExternalPlaybackActive: Bool,
        itemReady: Bool,
        previousSeconds: Double?,
        currentSeconds: Double
    ) -> Bool {
        guard isTVOS, isExternalPlaybackActive, itemReady, let previousSeconds else { return false }
        return currentSeconds > previousSeconds + 0.2
    }
}

/// AVFoundation policy for a progressive item served by ReelFin's localhost disk reservoir.
///
/// The disk cache, not AVPlayer's in-memory CRABS cache, owns deep read-ahead. Forcing a 30-second
/// `preferredForwardBufferDuration` on a 4K remux made CoreMedia issue 124–130 MB reads until CRABS
/// logged `no more cache space`, cancelled the HTTP tasks, and permanently parked the player at
/// `AVPlayerWaitingToMinimizeStallsReason` even though gigabytes were available locally.
enum CustomLocalCachePlaybackPolicy {
    enum RecoveryAction: Equatable {
        case none
        case waitForBytes
        case forceImmediatePlayback
        case rebuildWarmItem
    }

    static let minimumTrustedReservoirSeconds = 3.0
    static let forceImmediatePlaybackAfterSeconds = 2.0
    static let rebuildWarmItemAfterSeconds = 6.0

    @MainActor
    static func configure(player: AVPlayer, item: AVPlayerItem) {
        // Zero means AVFoundation's natural, device-sized buffer. The multi-minute cushion already
        // lives on disk and is served at localhost speed; duplicating it in CoreMedia is harmful.
        item.preferredForwardBufferDuration = 0
        // A localhost miss should be visible to our bounded recovery ladder immediately. Letting
        // AVPlayer minimize stalls hid a poisoned read pipeline behind an infinite wait.
        player.automaticallyWaitsToMinimizeStalling = false
    }

    /// With `automaticallyWaitsToMinimizeStalling == false`, CoreMedia reports a real underflow by
    /// posting `playbackStalledNotification` and changing the player to `.paused` (`NoStallWait`).
    /// That paused state is transport failure, while an ordinary paused state is user intent.
    static func transportNeedsRecovery(isWaiting: Bool, observedPlaybackStall: Bool) -> Bool {
        isWaiting || observedPlaybackStall
    }

    static func recoveryAction(
        isWaiting: Bool,
        observedPlaybackStall: Bool,
        reservoirSeconds: Double,
        stagnantSeconds: TimeInterval,
        alreadyForcedImmediatePlayback: Bool
    ) -> RecoveryAction {
        guard isWaiting || observedPlaybackStall else { return .none }
        guard reservoirSeconds >= minimumTrustedReservoirSeconds else { return .waitForBytes }
        if alreadyForcedImmediatePlayback, stagnantSeconds >= rebuildWarmItemAfterSeconds {
            return .rebuildWarmItem
        }
        if observedPlaybackStall, !alreadyForcedImmediatePlayback {
            return .forceImmediatePlayback
        }
        if !alreadyForcedImmediatePlayback, stagnantSeconds >= forceImmediatePlaybackAfterSeconds {
            return .forceImmediatePlayback
        }
        return .none
    }

    /// CoreMedia can coast a fraction of a second after posting `PlaybackStalled`, then leave the
    /// player parked at rate zero. That residual timestamp movement is not recovery: the explicit
    /// stall must remain latched until decoded playback is genuinely running again.
    static func hasRecoveredFromObservedStall(positionAdvanced: Bool, playbackRate: Float) -> Bool {
        positionAdvanced && playbackRate > 0
    }
}

/// UI/transport state for server HLS. A video-copy remux is still original quality; only a real
/// video transcode is the orange last-resort lane.
enum CustomAdaptivePlaybackPolicy {
    static func phase(
        isStarving: Bool,
        preservesOriginalVideo: Bool
    ) -> PlaybackBufferingState.Phase {
        if isStarving { return .buffering }
        return preservesOriginalVideo ? .playing : .degradedSDR
    }
}

/// Keeps audio-session recovery separate from transport intent. A route repair may reactivate the
/// output device, but it must never turn a deliberate user pause into playback.
enum CustomPlayerAudioRecoveryPolicy {
    enum Event: Equatable {
        case interruptionEnded(systemShouldResume: Bool)
        case routeChanged
    }

    struct Decision: Equatable {
        let reactivateSession: Bool
        let resumePlayback: Bool
    }

    static func decision(for event: Event, wasPlaying: Bool) -> Decision {
        switch event {
        case let .interruptionEnded(systemShouldResume):
            return Decision(
                reactivateSession: true,
                resumePlayback: systemShouldResume && wasPlaying
            )
        case .routeChanged:
            return Decision(reactivateSession: true, resumePlayback: wasPlaying)
        }
    }

#if os(iOS) || os(tvOS)
    static func shouldRecoverRouteChange(_ reason: AVAudioSession.RouteChangeReason) -> Bool {
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .override, .wakeFromSleep,
             .noSuitableRouteForCategory, .routeConfigurationChange:
            return true
        case .unknown, .categoryChange:
            // `setCategory` itself emits categoryChange. Reacting to it would create a recovery
            // notification loop, so only genuine output-route events are actionable.
            return false
        @unknown default:
            return true
        }
    }
#endif
}

/// The original source for a title, resolved from Jellyfin — the minimal input the custom engine
/// needs to play it through the local cache. (A thin adapter over `PlaybackCoordinator` provides
/// this in the app; tests provide a mock, so the engine is offline-testable.)
public struct ResolvedOriginalSource: Sendable {
    public let originURL: URL
    public let headers: [String: String]
    /// Original bitrate in bits/s (drives every dynamic, per-file decision). nil ⇒ assume high.
    public let sourceBitrate: Int?
    public let overrideMIMEType: String?
    public let cacheKey: MediaGatewayCacheKey
    public let isDolbyVision: Bool
    /// True for DirectStream/remux routes that only repackage the original video bitstream.
    public let preservesOriginalVideo: Bool
    /// True when this is a server ADAPTIVE stream (HLS transcode/remux) rather than the raw
    /// original: the engine then plays the URL directly (AVPlayer's own HLS stack — segments are
    /// their own dropout recovery) and skips the byte-range cache session entirely.
    public let isAdaptiveStream: Bool
    /// True when the original is a compatible Matroska stream that must be decoded by ReelFin's
    /// packet-demuxed native surface. Jellyfin's HEVC fMP4 remux can report a ready audio track
    /// while exposing no video track to AVPlayer, so this route is a handoff, never an adaptive
    /// quality fallback.
    public let requiresNativePlayback: Bool
    /// Text sidecar subtitle tracks the player renders itself (AVFoundation can't inject external
    /// text tracks into a progressive asset).
    public let externalSubtitles: [ExternalSubtitleTrack]

    public init(
        originURL: URL,
        headers: [String: String],
        sourceBitrate: Int?,
        overrideMIMEType: String?,
        cacheKey: MediaGatewayCacheKey,
        isDolbyVision: Bool,
        preservesOriginalVideo: Bool = false,
        isAdaptiveStream: Bool = false,
        requiresNativePlayback: Bool = false,
        externalSubtitles: [ExternalSubtitleTrack] = []
    ) {
        self.originURL = originURL
        self.headers = headers
        self.sourceBitrate = sourceBitrate
        self.overrideMIMEType = overrideMIMEType
        self.cacheKey = cacheKey
        self.isDolbyVision = isDolbyVision
        self.preservesOriginalVideo = preservesOriginalVideo
        self.isAdaptiveStream = isAdaptiveStream
        self.requiresNativePlayback = requiresNativePlayback
        self.externalSubtitles = externalSubtitles
    }
}

public protocol CustomPlaybackSourceResolving: Sendable {
    func resolveOriginal(itemID: String, startTimeTicks: Int64?) async throws -> ResolvedOriginalSource
}

/// Narrow reporting seam so the engine can keep the server's resume position / watched state up to
/// date (the app's "Continue watching" experience) without depending on the whole API client.
public protocol CustomPlaybackProgressReporting: Sendable {
    func reportProgress(_ update: PlaybackProgressUpdate) async
    func reportStopped(_ update: PlaybackProgressUpdate) async
}

/// Optional capability of a source resolver: produce the clean SDR fallback stream (Jellyfin H.264
/// HLS transcode, tone-mapped server-side) STARTING at a position. Resolved lazily, only when the
/// last-resort lane actually fires — never at startup (the global-transcode black-screen lesson).
public protocol CustomPlaybackAdaptiveFallbackResolving: Sendable {
    func resolveAdaptiveFallback(itemID: String, startSeconds: Double) async -> URL?
}

/// The clean custom player (blueprint §2). ONE `AVPlayer`, fed the original bytes from the local
/// disk cache over `http://127.0.0.1` (DV-safe), with the ORIGINAL-FIRST dynamic brain driving a
/// loading bar instead of cuts or quality drops. The cache's own fill rate is the connection probe
/// (no separate preheat). Composes the four offline-tested cores; no legacy coordinator/guard/
/// sample-buffer/NativeBridge cruft.
///
/// Never-freeze contract (blueprint §4 Layer 3, the reload-averse recovery ladder):
/// 1. A stall is absorbed by design — AVPlayer drains the disk reservoir; the UI shows a loading
///    bar, the item is NEVER rebuilt on a stall.
/// 2. A FAILED item (AVPlayer never self-recovers from `.failed`) is rebuilt at the last known
///    position on the SAME warm cache session — bytes are on disk, so the rebuild is instant.
/// 3. Repeated failures inside a rolling window end in an HONEST error state with a Retry action —
///    never a silent frozen frame.
@MainActor
@Observable
public final class CustomPlaybackEngine {
    public let player: AVPlayer
    public private(set) var bufferingState: PlaybackBufferingState = .idle
    public private(set) var errorMessage: String?
    /// Quality badge for the HUD ("HDR/DV" originals) — proof the original bitstream is playing.
    public private(set) var sourceQualityLabel: String?
    public var hasLocalCacheReservoir: Bool { session != nil }
    /// Fired once when the title plays to its end (dismiss / up-next hook for the UI).
    public var onPlaybackEnded: (() -> Void)?
    /// Requests a presentation-level handoff to `PlaybackSessionController` for an original MKV.
    /// The callback deliberately lives above this engine: only the UI owns player presentation,
    /// while PlaybackEngine remains independent of ReelFinUI.
    public var onRequiresNativePlayback: (() -> Void)?
    /// External subtitles rendered by the player itself (AVFoundation can't inject sidecar text
    /// tracks into a progressive asset). The view binds the picker + the cue overlay.
    public let subtitles = SubtitleOverlayModel()
    /// Skip intro/credits suggestion (same resolver as everywhere in the app) — nil when none.
    public private(set) var activeSkipSuggestion: PlaybackSkipSuggestion?
    /// Item metadata + binge queue, provided by the host (drives episode skip/next semantics).
    public var currentMediaItem: MediaItem?
    public var nextEpisodeQueue: [MediaItem] = []
    /// Fired to chain into the next episode (host reloads the engine with it + remaining queue).
    public var onPlayNext: ((MediaItem, [MediaItem]) -> Void)?

    /// Default deep-cache budget (4 GB iOS / 10 GB tvOS). Public so the app can size the store it
    /// passes in to match the engine's read-ahead budget.
    public static var defaultCacheBudgetBytes: Int64 { CacheProxySession.defaultCacheBudgetBytes }

    /// ONE store for the whole app. The store keeps its coverage map in memory (loaded from disk
    /// once per key), so all plays must share the instance — it is an actor, safe everywhere.
    private static var _sharedStore: MediaGatewayStore?
    public static func sharedStore() throws -> MediaGatewayStore {
        if let _sharedStore { return _sharedStore }
        let store = try MediaGatewayStore(
            configuration: MediaGatewayStore.Configuration(maxBytes: Int(defaultCacheBudgetBytes)))
        _sharedStore = store
        return store
    }

    private let resolver: CustomPlaybackSourceResolving
    private let store: MediaGatewayStore
    private let reporter: CustomPlaybackProgressReporting?
    private let prewarmer: CustomPlayerPrewarmer?
    private let markers: CustomPlaybackMarkersProviding?
    private var mediaSegments: [MediaSegment] = []
    private var markersTask: Task<Void, Never>?
    private var timeObserverToken: Any?

    private var session: CacheProxySession?
    private var monitor: ConnectionMonitor?
    private var sourceBitrateMbps: Double = 30
    private var resolvedMIMEType: String?
    private var loadTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var rebuildTask: Task<Void, Never>?
    private var stalledObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var didEndObserver: NSObjectProtocol?
    private var audioInterruptionObserver: NSObjectProtocol?
    private var audioRouteChangeObserver: NSObjectProtocol?
    private var audioRecoveryTask: Task<Void, Never>?
    private var wasPlayingBeforeAudioInterruption = false
    private var itemStatusObservation: NSKeyValueObservation?

    // Recovery ladder state.
    private var currentItemID: String?
    private var lastKnownTimeSeconds: Double = 0
    private var rebuildTimestamps: [Date] = []
    private let rebuildWindowSeconds: TimeInterval = 90
    private let maxRebuildsInWindow = 3
    var rebuildBackoffSeconds: [Double] = [0.5, 2.0, 5.0] // internal: tests shrink the waits

    // Connection measurement (fed from the cache's own fill rate — no separate preheat).
    private var lastTickSnapshot: (date: Date, position: Double, reservoir: Double)?

    // Last-resort lane (SDR fallback with automatic DV return). The SDR stream's timeline is
    // 0-based at the drop position (Jellyfin transcodes from StartTimeTicks), so every position
    // the engine tracks/reports while in SDR adds this offset.
    private var laneState = AdaptiveLanePolicy.State()
    private var sdrTimelineOffsetSeconds: Double = 0

    // External playback (AirPlay): while active, the item plays the ORIGIN URL (a receiver cannot
    // reach 127.0.0.1); back on the localhost cache when it ends.
    private var externalPlaybackObservation: NSKeyValueObservation?
    private var isExternalPlaybackItemActive = false
    private var originSource: (url: URL, headers: [String: String])?
    /// Set when playing the adaptive-only lane (non-direct-playable source, no cache session).
    private var adaptiveStreamURL: URL?
    private var adaptivePreservesOriginalVideo = false

    // Video liveness (tvOS): the localhost-cache transport was never render-validated on tvOS —
    // a stream can consume bytes with a black picture. A pixel-buffer probe detects real decoded
    // frames (the legacy tvOS decoded-frame watchdog pattern; NEVER attached on iOS where a probe
    // once doubled the DV render load); no frame by the deadline → swap to the DIRECT origin URL
    // (the legacy tvOS path, byte-identical quality), then the honest ladder if even that is black.
#if os(tvOS)
    private var videoOutputProbe: AVPlayerItemVideoOutput?
    /// Continuous render heartbeat: when the probe last yielded a FRESH decoded frame, and the
    /// title position at that moment. The timeline advancing while no fresh frame arrives is the
    /// frozen-picture signature (audio runs, image stuck — device 2026-07-03 and 2026-07-08).
    private var lastFreshFrameAt: Date?
    private var positionAtLastFreshFrame: Double = 0
#endif
    private var videoFramesObserved = false
    private var videoLivenessDeadline: Date?
    private var didFallBackToDirectOrigin = false
    /// True once the picture is PROVEN on screen (tvOS: a decoded frame witnessed by the probe;
    /// iOS/AirPlay: the timeline actually advancing while ready). The launch overlay keys off this:
    /// keying it off the phase flip alone left a black screen between gate-exit and first frame.
    public private(set) var hasRenderedFirstFrame = false
    /// Bumped on every load()/retry() so the UI can reset per-attempt state (slow-launch panel).
    public private(set) var loadGeneration = 0
    private var firstFrameWatchdogTask: Task<Void, Never>?
    private var lastRenderCheckSeconds: Double?
    private var lastTransportLogAt: Date = .distantPast
    private var wasStarving = false
    /// Watch the media clock, not `player.rate`: AVPlayer keeps its requested rate at 1 while its
    /// effective clock is halted in WaitingToMinimizeStalls. This bounds a cached-byte freeze.
    private var lastTransportAdvanceAt: Date = .distantPast
    private var lastTransportPositionSeconds: Double = 0
    private var didForceImmediatePlaybackForCurrentStall = false
    private var didRequestWarmRebuildForCurrentStall = false
    /// `NoStallWait` changes a genuinely stalled player to `.paused`, so timeControlStatus alone
    /// cannot distinguish it from a user pause. Set only by AVPlayerItem.playbackStalledNotification.
    private var observedPlaybackStall = false
    /// Set by the UI host while Picture in Picture runs, so a disappearing view doesn't stop it.
    public var isPictureInPictureActive = false
    /// The custom cover is being replaced in place by the native Matroska surface. Its disappear
    /// callback must not restore portrait because the player presentation is still active.
    public private(set) var isHandingOffToNativePlayback = false

    // Server progress reporting (resume position / watched state).
    private var durationSeconds: Double = 0
    private var lastProgressReportAt: Date = .distantPast
    private let progressReportInterval: TimeInterval = 10
    /// stop() is reachable twice (view disappear + host dismissal) — report the stop only once.
    private var didReportStop = false

    private let monitorInterval: UInt64 = 1_000_000_000 // 1s

    public init(
        resolver: CustomPlaybackSourceResolving,
        store: MediaGatewayStore,
        reporter: CustomPlaybackProgressReporting? = nil,
        prewarmer: CustomPlayerPrewarmer? = nil,
        markers: CustomPlaybackMarkersProviding? = nil
    ) {
        self.resolver = resolver
        self.store = store
        self.reporter = reporter
        self.prewarmer = prewarmer
        self.markers = markers
        self.player = AVPlayer()
        self.player.automaticallyWaitsToMinimizeStalling = true
        // AirPlay is allowed — but the localhost cache URL is unreachable from a receiver, so the
        // engine swaps to the ORIGIN URL while external playback is active (see
        // `handleExternalPlaybackChange`), and back to the cache when it ends.
        self.player.allowsExternalPlayback = true
        externalPlaybackObservation = player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] observedPlayer, _ in
            let active = observedPlayer.isExternalPlaybackActive
            Task { @MainActor [weak self] in
                self?.handleExternalPlaybackChange(active: active)
            }
        }
    }

    /// Route audio to playback (movie) so there IS sound — and it ignores the silent switch, like a
    /// video player should. Run off the main thread (AVAudioSession.setActive is synchronous/blocking).
    private nonisolated static func activateAudioSessionForPlayback() -> Bool {
#if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        do {
#if targetEnvironment(simulator)
            try session.setCategory(.playback)
#elseif os(iOS)
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
#else
            try session.setCategory(.playback, mode: .moviePlayback)
#endif
            try session.setActive(true)
            return true
        } catch {
            do {
                try session.setCategory(.playback)
                try session.setActive(true)
                return true
            } catch {
                AppLog.playback.warning("customplayer.audioSession.failed — \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
#else
        return true
#endif
    }

    private static func configureAudioSessionForPlayback() {
#if os(iOS) || os(tvOS)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = activateAudioSessionForPlayback()
        }
#endif
    }

    // MARK: - Public control

    public func load(itemID: String, startTimeTicks: Int64? = nil, autoPlay: Bool = true) {
        teardown()
        currentItemID = itemID
        lastKnownTimeSeconds = Double(startTimeTicks ?? 0) / 10_000_000
        rebuildTimestamps = []
        didReportStop = false
        durationSeconds = 0
        laneState = AdaptiveLanePolicy.State()
        sdrTimelineOffsetSeconds = 0
        adaptiveStreamURL = nil
        adaptivePreservesOriginalVideo = false
        mediaSegments = []
        activeSkipSuggestion = nil
        videoFramesObserved = false
        videoLivenessDeadline = nil
        didFallBackToDirectOrigin = false
        hasRenderedFirstFrame = false
        lastRenderCheckSeconds = nil
        lastTransportAdvanceAt = .distantPast
        lastTransportPositionSeconds = lastKnownTimeSeconds
        didForceImmediatePlaybackForCurrentStall = false
        didRequestWarmRebuildForCurrentStall = false
        observedPlaybackStall = false
        isHandingOffToNativePlayback = false
        loadGeneration += 1
        loadMarkers(itemID: itemID)
        bufferingState = PlaybackBufferingState(phase: .prebuffering)
        errorMessage = nil
        loadTask = Task { [weak self] in
            await self?.runLoad(itemID: itemID, startTimeTicks: startTimeTicks, autoPlay: autoPlay)
        }
    }

    /// Retry after the honest error state: reload the same title from the last known position.
    /// The disk cache is intact, so everything already downloaded replays instantly.
    public func retry() {
        guard let itemID = currentItemID else { return }
        let resumeTicks = Int64(max(0, lastKnownTimeSeconds) * 10_000_000)
        load(itemID: itemID, startTimeTicks: resumeTicks > 0 ? resumeTicks : nil, autoPlay: true)
    }

    public func play() {
        wasPlayingBeforeAudioInterruption = true
        player.play()
    }
    public func pause() {
        wasPlayingBeforeAudioInterruption = false
        observedPlaybackStall = false
        player.pause()
    }

    /// Explicit tvOS remote fallback. A SwiftUI overlay above `AVPlayerViewController` can own the
    /// focus responder, so relying solely on AVKit to receive the Play/Pause press is unreliable.
    public func togglePlayPause() {
        if player.timeControlStatus == .paused || player.rate == 0 {
            wasPlayingBeforeAudioInterruption = true
            AppLog.playback.notice(
                "customplayer.remote.play_pause — action=play status=\(self.player.timeControlStatus.rawValue, privacy: .public) rate=\(self.player.rate, format: .fixed(precision: 2))"
            )
            player.playImmediately(atRate: 1)
        } else {
            wasPlayingBeforeAudioInterruption = false
            AppLog.playback.notice(
                "customplayer.remote.play_pause — action=pause status=\(self.player.timeControlStatus.rawValue, privacy: .public) rate=\(self.player.rate, format: .fixed(precision: 2))"
            )
            observedPlaybackStall = false
            player.pause()
        }
    }

    public func seek(toSeconds seconds: Double) {
        lastKnownTimeSeconds = max(0, seconds)
        lastTickSnapshot = nil // a jump invalidates the fill-rate delta
        session?.setPlayheadOffset(session?.byteOffset(forSeconds: seconds) ?? 0)
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
    }

    /// Last playback position the engine observed (drives resume reporting and retry).
    public var lastObservedSeconds: Double { lastKnownTimeSeconds }

    /// Normalized title duration discovered from the active AVPlayerItem. Exposed for ReelFin's
    /// own tvOS timeline because AVKit's inline controls are deliberately disabled there.
    public var observedDurationSeconds: Double? {
        durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : nil
    }

    /// Stops playback, reports the final position to the server, and returns it so the UI can
    /// update its local state (resume badge) immediately.
    @discardableResult
    public func stop() -> PlaybackProgress? {
        let progress = currentProgress()
        if let progress, let reporter, !didReportStop {
            didReportStop = true
            let update = progressUpdate(positionTicks: progress.positionTicks, isPaused: true, isPlaying: false, didFinish: false)
            Task { await reporter.reportStopped(update) }
        }
        teardown()
        bufferingState = .idle
        return progress
    }

    // MARK: - Server progress reporting

    private func currentProgress() -> PlaybackProgress? {
        guard let itemID = currentItemID, lastKnownTimeSeconds > 0 else { return nil }
        return PlaybackProgress(
            itemID: itemID,
            positionTicks: Int64(lastKnownTimeSeconds * 10_000_000),
            totalTicks: Int64(max(0, durationSeconds) * 10_000_000),
            updatedAt: Date()
        )
    }

    private func progressUpdate(positionTicks: Int64, isPaused: Bool, isPlaying: Bool, didFinish: Bool) -> PlaybackProgressUpdate {
        PlaybackProgressUpdate(
            itemID: currentItemID ?? "",
            positionTicks: positionTicks,
            totalTicks: Int64(max(0, durationSeconds) * 10_000_000),
            isPaused: isPaused,
            isPlaying: isPlaying,
            didFinish: didFinish,
            playMethod: "DirectPlay"
        )
    }

    private func reportProgressIfDue(now: Date) {
        guard let reporter, currentItemID != nil, lastKnownTimeSeconds > 0 else { return }
        guard now.timeIntervalSince(lastProgressReportAt) >= progressReportInterval else { return }
        lastProgressReportAt = now
        let update = progressUpdate(
            positionTicks: Int64(lastKnownTimeSeconds * 10_000_000),
            isPaused: player.timeControlStatus == .paused,
            isPlaying: player.timeControlStatus != .paused,
            didFinish: false
        )
        Task { await reporter.reportProgress(update) }
    }

    // MARK: - Load flow

    private func runLoad(itemID: String, startTimeTicks: Int64?, autoPlay: Bool) async {
        let resolved: ResolvedOriginalSource
        let session: CacheProxySession
        let localURL: URL

        if let warm = await prewarmer?.consume(itemID: itemID) {
            // Perceived-instant start: the detail view already resolved the source, started the
            // localhost session, and built (part of) the cushion — adopt the ready pipeline.
            AppLog.playback.notice("customplayer.load.adopts_prewarm — item=\(itemID.prefix(8), privacy: .public)")
            resolved = warm.resolved
            if resolved.requiresNativePlayback {
                requestNativePlaybackHandoff(itemID: itemID)
                return
            }
            if resolved.isAdaptiveStream {
                startAdaptivePlayback(resolved: resolved, startTimeTicks: startTimeTicks, autoPlay: autoPlay)
                return
            }
            guard let warmSession = warm.session, let warmLocalURL = warm.localURL else {
                enterFailedState(message: "Le préchargement local est incomplet. Réessayez la lecture.")
                return
            }
            session = warmSession
            localURL = warmLocalURL
        } else {
            do {
                if let warmResolved = prewarmer?.consumeResolvedOnly(itemID: itemID) {
                    // Focus-dwell resolution (tvOS): the PlaybackInfo round trip already happened
                    // while the user was hovering the card — the press pays only the session start.
                    AppLog.playback.notice("customplayer.load.adopts_resolved_only — item=\(itemID.prefix(8), privacy: .public)")
                    resolved = warmResolved
                } else {
                    resolved = try await resolver.resolveOriginal(itemID: itemID, startTimeTicks: startTimeTicks)
                }
            } catch {
                enterFailedState(message: "Impossible de résoudre la source : \(error.localizedDescription)")
                return
            }
            guard !Task.isCancelled else { return }
            if resolved.requiresNativePlayback {
                requestNativePlaybackHandoff(itemID: itemID)
                return
            }
            if resolved.isAdaptiveStream {
                // Not directly playable as a raw original — play the server's adaptive stream
                // straight (AVPlayer's HLS stack). No cache session, no startup gate: segments
                // start fast and carry their own recovery.
                startAdaptivePlayback(resolved: resolved, startTimeTicks: startTimeTicks, autoPlay: autoPlay)
                return
            }
            let fresh = CacheProxySession(
                originURL: resolved.originURL, headers: resolved.headers, key: resolved.cacheKey,
                store: store, sourceBitrate: resolved.sourceBitrate, overrideMIMEType: resolved.overrideMIMEType)
            do {
                // The localhost listener start blocks its thread briefly — keep it off the MainActor.
                localURL = try await Task.detached(priority: .userInitiated) { try fresh.start() }.value
            } catch {
                enterFailedState(message: "Cache local indisponible : \(error.localizedDescription)")
                return
            }
            session = fresh
        }
        guard !Task.isCancelled else {
            session.stop()
            return
        }

        Self.configureAudioSessionForPlayback()
        observeAudioSessionChanges()
        sourceBitrateMbps = Double(resolved.sourceBitrate ?? 30_000_000) / 1_000_000
        resolvedMIMEType = resolved.overrideMIMEType
        monitor = ConnectionMonitor(sourceBitrateMbps: sourceBitrateMbps)
        originSource = (resolved.originURL, resolved.headers)
        isExternalPlaybackItemActive = false
        sourceQualityLabel = resolved.isDolbyVision ? "HDR/DV" : nil
        subtitles.configure(tracks: resolved.externalSubtitles)
        installTimeObserver()
        self.session = session

        let startSeconds = Double(startTimeTicks ?? 0) / 10_000_000
        installItem(localURL: localURL, seekTo: startSeconds > 0 ? startSeconds : nil)

        await runStartup(startSeconds: startSeconds, autoPlay: autoPlay)
        startMonitorLoop(startSeconds: startSeconds)
    }

    private func requestNativePlaybackHandoff(itemID: String) {
        AppLog.playback.notice(
            "customplayer.load.native_handoff — item=\(itemID.prefix(8), privacy: .public) quality=original"
        )
        loadTask = nil
        bufferingState = .idle
        errorMessage = nil
        sourceQualityLabel = nil
        isHandingOffToNativePlayback = true
        player.pause()
        player.replaceCurrentItem(with: nil)
        onRequiresNativePlayback?()
    }

    /// Non-direct-playable source (container/codec AVFoundation can't open raw): play the server's
    /// adaptive HLS stream directly. The item lifecycle ladder still applies (rebuild on failure →
    /// honest error); the reservoir HUD stays hidden (no cache session — segments self-recover).
    private func startAdaptivePlayback(resolved: ResolvedOriginalSource, startTimeTicks: Int64?, autoPlay: Bool) {
        AppLog.playback.notice(
            "customplayer.load.adaptive_lane — item=\(self.currentItemID?.prefix(8) ?? "-", privacy: .public)"
        )
        Self.configureAudioSessionForPlayback()
        observeAudioSessionChanges()
        sourceBitrateMbps = Double(resolved.sourceBitrate ?? 30_000_000) / 1_000_000
        adaptivePreservesOriginalVideo = resolved.preservesOriginalVideo
        sourceQualityLabel = resolved.isDolbyVision ? "HDR/DV" : (resolved.preservesOriginalVideo ? "Original" : nil)
        adaptiveStreamURL = resolved.originURL
        subtitles.configure(tracks: resolved.externalSubtitles)
        installTimeObserver()
        sdrTimelineOffsetSeconds = Double(startTimeTicks ?? 0) / 10_000_000 // HLS timeline is 0-based at the resume point
        let item = AVPlayerItem(url: resolved.originURL)
        player.automaticallyWaitsToMinimizeStalling = true
        player.replaceCurrentItem(with: item)
        observeItemLifecycle(item)
        bufferingState = PlaybackBufferingState(phase: .playing)
        if autoPlay { player.play() }
        startMonitorLoop(startSeconds: sdrTimelineOffsetSeconds)
    }

    /// Builds and installs an `AVPlayerItem` over the localhost cache URL, wiring the full
    /// lifecycle observation set. Used at load AND by the recovery rebuild.
    private func installItem(localURL: URL, seekTo seconds: Double?) {
        var options: [String: Any] = [:]
        if let mime = resolvedMIMEType { options[AVURLAssetOverrideMIMETypeKey] = mime }
        let asset = AVURLAsset(url: localURL, options: options)
        let item = AVPlayerItem(asset: asset)
        CustomLocalCachePlaybackPolicy.configure(player: player, item: item)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player.replaceCurrentItem(with: item)
        if let seconds, seconds > 0 {
            session?.setPlayheadOffset(session?.byteOffset(forSeconds: seconds) ?? 0)
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
        }
        observeItemLifecycle(item)
    }

    /// The cache's own fill rate is the connection probe — measured WHILE the prime fetch runs, so
    /// no dead probe wait. The startup gate is fully dynamic (blueprint R2/R4): the target cushion
    /// is re-decided every 250ms from the freshest measurement — a fast link collapses the target
    /// to ~6s (Infuse-class fast start), a weak one deepens it behind an honest loading bar, and a
    /// region already cached to the file's end stops waiting immediately (nothing left to build).
    private func runStartup(startSeconds: Double, autoPlay: Bool) async {
        guard let session else { return }
        // Hard cap on the pre-play wait: a press must START within seconds — the reservoir keeps
        // building WHILE playing, and a genuinely starved transport shows the honest loading bar.
        // The old 40s window read as "the app froze" on a TV whenever the link was slow.
        let deadline = Date().addingTimeInterval(12)
        var samples: [(at: Date, depth: Double)] = []

        while !Task.isCancelled {
            let depth = await session.reservoirSecondsAhead(atSeconds: startSeconds)
            let now = Date()
            samples.append((now, depth))
            samples.removeAll { now.timeIntervalSince($0.at) > 2.0 } // sliding measurement window

            var measuredMbps: Double?
            if let first = samples.first, samples.count >= 2 {
                let span = now.timeIntervalSince(first.at)
                if span >= 0.6 {
                    let mbps = max(0, (depth - first.depth) / span) * sourceBitrateMbps
                    // Zero reservoir growth at startup usually means the PRIME (tail/moov fetch) is
                    // spending the bandwidth — not a dead link. Reading it as ~0 Mbps escalated the
                    // cushion target to its 90s deepest tier and held the gate to its deadline.
                    // Treat it as "link not revealed yet" so the target stays at the middle ground.
                    if mbps > 0.05 * sourceBitrateMbps {
                        measuredMbps = mbps
                        monitor?.record(mbps: mbps, at: now)
                    }
                }
            }

            let action = PlaybackLanePolicy.startupAction(
                measuredMbps: measuredMbps,
                sourceBitrateMbps: sourceBitrateMbps,
                reservoirSecondsAlready: depth)
            if case .playOriginalNow = action { break }
            if case let .prebufferOriginal(target) = action {
                bufferingState = PlaybackBufferingState(phase: .prebuffering, reservoirSeconds: depth, targetSeconds: target)
            }
            if await session.isCachedToEnd(fromSeconds: startSeconds) { break }
            if now >= deadline { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard !Task.isCancelled else { return }
        let depth = await session.reservoirSecondsAhead(atSeconds: startSeconds)
        bufferingState = PlaybackBufferingState(phase: .playing, reservoirSeconds: depth)
        if autoPlay {
            player.play()
            startFirstFrameWatchdog()
        }
        // Keep the CoreMedia buffer device-sized. The deep, outage-resistant reservoir is already
        // on disk; forcing 30s here produced 130MB reads and exhausted CRABS on real 4K playback.
        if let item = player.currentItem {
            CustomLocalCachePlaybackPolicy.configure(player: player, item: item)
        }
    }

    // MARK: - First-frame liveness (launch overlay + black-start escape)

    private func markFirstFrameRendered() {
        guard !hasRenderedFirstFrame else { return }
        hasRenderedFirstFrame = true
        firstFrameWatchdogTask?.cancel()
        firstFrameWatchdogTask = nil
    }

    /// The AVKit host owns the only trustworthy iOS render signal. Audio time can advance while
    /// PlayerRemoteXPC failed to attach the video surface, so the engine must not treat timeline
    /// movement alone as a visible first frame. `CustomPlayerSurface` calls this only after its
    /// AVPlayerViewController reports `isReadyForDisplay` for a ready item.
    public func reportRenderSurfaceReady() {
        markFirstFrameRendered()
    }

    /// Evaluate render evidence without ever confusing an advancing media clock with visible video.
    /// iOS is acknowledged only by `reportRenderSurfaceReady()`. Local tvOS uses the pixel probe;
    /// AirPlay accepts a ready advancing timeline because rendering happens on the receiver.
    private func observeRenderProgress(item: AVPlayerItem, rawSeconds: Double) {
        guard !hasRenderedFirstFrame else { return }
#if os(tvOS)
        if CustomPlayerFirstFrameProofPolicy.acceptsLocalPixelProbe(
            isTVOS: true,
            videoFramesObserved: videoFramesObserved
        ) {
            markFirstFrameRendered()
            return
        }
        let isTVOS = true
#else
        let isTVOS = false
#endif
        if CustomPlayerFirstFrameProofPolicy.acceptsTimelineProgress(
            isTVOS: isTVOS,
            isExternalPlaybackActive: isExternalPlaybackItemActive,
            itemReady: item.status == .readyToPlay,
            previousSeconds: lastRenderCheckSeconds,
            currentSeconds: rawSeconds
        ) {
            markFirstFrameRendered()
        }
        lastRenderCheckSeconds = rawSeconds
    }

    /// Escape hatch for a start that never shows a picture: after the gate exits, the transport can
    /// sit "playing"/waiting with zero decoded frames — invisible to the stall path, and the old
    /// liveness check required t>2s so it could never fire on a start wedged at t=0. While data is
    /// genuinely still arriving the overlay keeps waiting; once bytes are there and nothing renders,
    /// tvOS swaps to the direct origin once (the always-proven render path), then the honest ladder.
    private func startFirstFrameWatchdog() {
        firstFrameWatchdogTask?.cancel()
        firstFrameWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.hasRenderedFirstFrame || self.bufferingState.phase == .failed
                    || self.bufferingState.phase == .ended || self.currentItemID == nil {
                    self.firstFrameWatchdogTask = nil
                    return
                }
                // Starving with a shallow reservoir is a DATA problem (the loading path owns it).
                let starving = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                let reservoir = await self.session?.reservoirSecondsAhead(atSeconds: self.lastKnownTimeSeconds) ?? 0
                if starving, self.session != nil, reservoir < 12 { continue }
                self.firstFrameWatchdogTask = nil
                self.handleFirstFrameTimeout()
                return
            }
        }
    }

    private func handleFirstFrameTimeout() {
#if os(tvOS)
        if laneState.lane == .original, !didFallBackToDirectOrigin, originSource != nil, !isExternalPlaybackItemActive {
            didFallBackToDirectOrigin = true
            AppLog.playback.error(
                "customplayer.first_frame.timeout — no picture at t=\(self.lastKnownTimeSeconds, format: .fixed(precision: 1)); swapping to direct origin"
            )
            installOriginDirectItem(atSeconds: max(0, lastKnownTimeSeconds))
            startFirstFrameWatchdog() // one more chance on the origin path, then the honest ladder
            return
        }
#endif
        AppLog.playback.error("customplayer.first_frame.timeout — no picture; entering the recovery ladder")
        handleItemFailure(reason: "no_first_frame")
    }

    // MARK: - Steady monitor (loading bar + connection measurement + position tracking)

    private func startMonitorLoop(startSeconds: Double) {
        lastTransportPositionSeconds = startSeconds
        lastTransportAdvanceAt = Date()
        didForceImmediatePlaybackForCurrentStall = false
        didRequestWarmRebuildForCurrentStall = false
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.monitorInterval ?? 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.monitorTick()
            }
        }
    }

    private func monitorTick() async {
        guard let item = player.currentItem else { return }
        guard bufferingState.phase != .failed, bufferingState.phase != .ended else { return }
        let rawSeconds = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
        // Adaptive/SDR stream timelines are 0-based at their start position — track the TITLE
        // position everywhere (resume reporting, reservoir aim, the return swap).
        let nowSeconds = sdrTimelineOffsetSeconds + rawSeconds
        if item.status == .readyToPlay, nowSeconds > 0 {
            lastKnownTimeSeconds = nowSeconds
        }
        if durationSeconds <= 0 {
            let duration = item.duration.seconds
            if duration.isFinite, duration > 0 { durationSeconds = sdrTimelineOffsetSeconds + duration }
        }
        observeRenderProgress(item: item, rawSeconds: rawSeconds)
        guard let session else {
            // Adaptive-only lane (no cache session): position + honest transport + server progress.
            let isStarving = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            bufferingState = PlaybackBufferingState(
                phase: CustomAdaptivePlaybackPolicy.phase(
                    isStarving: isStarving,
                    preservesOriginalVideo: adaptivePreservesOriginalVideo
                ),
                reservoirSeconds: 0,
                targetSeconds: isStarving ? PlaybackLanePolicy.bufferResumeSeconds : 0)
            updateSkipSuggestion()
            reportProgressIfDue(now: Date())
            return
        }
        // Cache depth for the HUD only — this is a CBR byte↔seconds estimate, fine to *display* but
        // NOT to gate buffering on (it oscillates on a VBR file). In the SDR lane this is the DV
        // reservoir rebuilding underneath for the return.
        let reservoir = await session.reservoirSecondsAhead(atSeconds: nowSeconds)
        if laneState.lane == .sdrFallback {
            // No serve requests reach the localhost server in SDR — keep the DV fill following the
            // (title) playhead ourselves so the return swap lands on a warm region.
            session.setPlayheadOffset(session.byteOffset(forSeconds: nowSeconds))
        }

        // Feed the connection monitor from the cache's own fill rate: content gained (reservoir
        // growth + playhead progress) per wall-second, scaled by the file's bitrate. This keeps
        // `sustainedBelowBitrateSeconds` honest for the last-resort lane and diagnostics.
        let now = Date()
        if let last = lastTickSnapshot {
            let dt = now.timeIntervalSince(last.date)
            if dt >= 0.5 {
                let contentGained = (reservoir - last.reservoir) + max(0, nowSeconds - last.position)
                monitor?.record(mbps: max(0, contentGained / dt) * sourceBitrateMbps, at: now)
                lastTickSnapshot = (now, nowSeconds, reservoir)
            }
        } else {
            lastTickSnapshot = (now, nowSeconds, reservoir)
        }

        // Drive the loading bar from AVPlayer's REAL transport state, not the byte estimate.
        // NoStallWait reports an underflow as `.paused`, so retain the explicit stall notification
        // as part of the transport state; an ordinary user pause never sets that signal.
        let isStarving = CustomLocalCachePlaybackPolicy.transportNeedsRecovery(
            isWaiting: player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
            observedPlaybackStall: observedPlaybackStall
        )
        if isStarving != wasStarving {
            wasStarving = isStarving
            if isStarving {
                // The one-line forensic for any future hiccup: a TRANSPORT stall carries the
                // reservoir depth + AVPlayer's own reason; a render hiccup never prints this line.
                let reason = player.reasonForWaitingToPlay?.rawValue ?? "-"
                AppLog.playback.warning(
                    "customplayer.stall — t=\(nowSeconds, format: .fixed(precision: 1)) reservoir=\(reservoir, format: .fixed(precision: 0)) reason=\(reason, privacy: .public)"
                )
            } else {
                AppLog.playback.notice("customplayer.stall.recovered — t=\(nowSeconds, format: .fixed(precision: 1))")
            }
        }
        switch (laneState.lane, isStarving) {
        case (.sdrFallback, _):
            bufferingState = PlaybackBufferingState(phase: .degradedSDR, reservoirSeconds: reservoir)
        case (.original, true):
            bufferingState = PlaybackBufferingState(
                phase: .buffering, reservoirSeconds: reservoir, targetSeconds: PlaybackLanePolicy.bufferResumeSeconds)
        case (.original, false):
            bufferingState = PlaybackBufferingState(phase: .playing, reservoirSeconds: reservoir)
        }

        recoverCachedTransportIfNeeded(
            isWaiting: isStarving,
            reservoirSeconds: reservoir,
            positionSeconds: nowSeconds,
            now: now
        )

        // Last-resort lane brain: drop only on PROVEN sustained inability + real starvation;
        // return on held headroom + a rebuilt DV reservoir (anti-flap inside the policy).
        if let monitor {
            let change = AdaptiveLanePolicy.decision(
                now: now,
                isBuffering: isStarving,
                sustainedBelowBitrateSeconds: monitor.sustainedBelowBitrateSeconds(now: now),
                headroom: monitor.headroom(now: now),
                dvReservoirSeconds: reservoir,
                state: &laneState)
            if let change { await applyLaneChange(change) }
        }

        checkVideoLiveness(item: item, positionSeconds: nowSeconds, now: now)
        logTransportIfDue(item: item, positionSeconds: nowSeconds, reservoir: reservoir, now: now)
        updateSkipSuggestion()
        reportProgressIfDue(now: now)
        await session.maintainDiskBudget(currentSeconds: nowSeconds)
    }

    /// A local-cache item can have plenty of bytes and still lose its CoreMedia read pipeline.
    /// First clear AVPlayer's wait policy; if the media clock is still frozen, rebuild the item at
    /// the same timestamp over the SAME warm cache. Both steps are bounded and reset on progress.
    private func recoverCachedTransportIfNeeded(
        isWaiting: Bool,
        reservoirSeconds: Double,
        positionSeconds: Double,
        now: Date
    ) {
        let positionAdvanced = positionSeconds > lastTransportPositionSeconds + 0.15
        if lastTransportAdvanceAt == .distantPast {
            lastTransportAdvanceAt = now
            lastTransportPositionSeconds = positionSeconds
        } else if positionAdvanced {
            lastTransportAdvanceAt = now
            lastTransportPositionSeconds = positionSeconds
            if !observedPlaybackStall || CustomLocalCachePlaybackPolicy.hasRecoveredFromObservedStall(
                positionAdvanced: true,
                playbackRate: player.rate
            ) {
                didForceImmediatePlaybackForCurrentStall = false
                didRequestWarmRebuildForCurrentStall = false
                observedPlaybackStall = false
            }
        }

        let stagnantSeconds = now.timeIntervalSince(lastTransportAdvanceAt)
        switch CustomLocalCachePlaybackPolicy.recoveryAction(
            isWaiting: isWaiting,
            observedPlaybackStall: observedPlaybackStall,
            reservoirSeconds: reservoirSeconds,
            stagnantSeconds: stagnantSeconds,
            alreadyForcedImmediatePlayback: didForceImmediatePlaybackForCurrentStall
        ) {
        case .none, .waitForBytes:
            break
        case .forceImmediatePlayback:
            didForceImmediatePlaybackForCurrentStall = true
            player.automaticallyWaitsToMinimizeStalling = false
            AppLog.playback.warning(
                "customplayer.stall.cached_bypass — t=\(positionSeconds, format: .fixed(precision: 1)) reservoir=\(reservoirSeconds, format: .fixed(precision: 0)) stagnant=\(stagnantSeconds, format: .fixed(precision: 1))"
            )
            player.playImmediately(atRate: 1)
        case .rebuildWarmItem:
            guard !didRequestWarmRebuildForCurrentStall else { return }
            didRequestWarmRebuildForCurrentStall = true
            AppLog.playback.error(
                "customplayer.stall.cached_rebuild — t=\(positionSeconds, format: .fixed(precision: 1)) reservoir=\(reservoirSeconds, format: .fixed(precision: 0)) stagnant=\(stagnantSeconds, format: .fixed(precision: 1))"
            )
            handleItemFailure(reason: "cached_bytes_but_clock_stagnant")
        }
    }

    /// Transport heartbeat (5s cadence) — the diagnostic line a device log needs to tell "black
    /// screen" apart from "not playing": status, rate, position, decoded frames, presentation size.
    private func logTransportIfDue(item: AVPlayerItem, positionSeconds: Double, reservoir: Double, now: Date) {
        guard now.timeIntervalSince(lastTransportLogAt) >= 5 else { return }
        lastTransportLogAt = now
        let size = item.presentationSize
        AppLog.playback.notice(
            "customplayer.transport — status=\(item.status.rawValue, privacy: .public) rate=\(self.player.rate, format: .fixed(precision: 2)) t=\(positionSeconds, format: .fixed(precision: 1)) framesSeen=\(self.videoFramesObserved, privacy: .public) size=\(Int(size.width), privacy: .public)x\(Int(size.height), privacy: .public) reservoir=\(reservoir, format: .fixed(precision: 0)) lane=\(self.laneState.lane == .original ? "original" : "sdr", privacy: .public) directOrigin=\(self.didFallBackToDirectOrigin, privacy: .public)"
        )
    }

    /// tvOS black/frozen-picture self-healing, BOTH phases:
    /// - No frame EVER decoded past the deadline → swap to the DIRECT origin URL (the render path
    ///   tvOS has always used — byte-identical quality); still black → the honest ladder.
    /// - Picture FROZEN after the first frame (timeline advances, probe sees no fresh frame —
    ///   audio keeps playing over a stuck image; device 2026-07-03 and 2026-07-08) → same remedy.
    private func checkVideoLiveness(item: AVPlayerItem, positionSeconds: Double, now: Date) {
#if os(tvOS)
        guard laneState.lane == .original, !isExternalPlaybackItemActive else { return }
        guard item.status == .readyToPlay, player.rate > 0 else { return }
        drainVideoProbe()
        if videoFramesObserved {
            videoLivenessDeadline = nil
            // Post-first-frame watch: the transport actively PLAYING (not starving) and the
            // position well past the last fresh frame means the picture is stuck. Generous
            // thresholds so an HDR display-mode switch or a seek can never false-positive.
            if player.timeControlStatus == .playing,
               let freshAt = lastFreshFrameAt,
               now.timeIntervalSince(freshAt) > 8,
               positionSeconds > positionAtLastFreshFrame + 4 {
                lastFreshFrameAt = now // re-arm: give the remedy its own full window
                positionAtLastFreshFrame = positionSeconds
                escalateDeadPicture(reason: "render_frozen", positionSeconds: positionSeconds)
            }
            return
        }
        guard positionSeconds > 2 else { return }
        guard let deadline = videoLivenessDeadline else {
            videoLivenessDeadline = now.addingTimeInterval(12)
            return
        }
        guard now >= deadline else { return }
        videoLivenessDeadline = nil
        escalateDeadPicture(reason: "no_decoded_frame", positionSeconds: positionSeconds)
#endif
    }

#if os(tvOS)
    private func escalateDeadPicture(reason: String, positionSeconds: Double) {
        if !didFallBackToDirectOrigin {
            didFallBackToDirectOrigin = true
            AppLog.playback.error(
                "customplayer.video_liveness.origin_fallback — reason=\(reason, privacy: .public) t=\(positionSeconds, format: .fixed(precision: 1)); swapping to direct origin"
            )
            installOriginDirectItem(atSeconds: max(0, lastKnownTimeSeconds))
        } else {
            AppLog.playback.error("customplayer.video_liveness.exhausted — reason=\(reason, privacy: .public); direct origin also dead")
            handleItemFailure(reason: "video_liveness_\(reason)")
        }
    }
#endif

#if os(tvOS)
    /// Continuous render heartbeat, called from the 0.25s time observer. The probe stays ATTACHED
    /// for the whole item and every queued buffer is COPIED (a reference hand-off, not a memcpy)
    /// and discarded — draining is what keeps the decoder pool healthy. (2026-07-03 device freeze:
    /// an output whose frames are NEVER copied retains pool buffers on 4K HDR. The old fix
    /// detached the probe after the first frame — which also blinded us: the picture froze AFTER
    /// frame one while audio/timeline kept running, and nothing could see it. Device 2026-07-08.)
    private func drainVideoProbe() {
        guard let probe = videoOutputProbe, let item = player.currentItem,
              item.status == .readyToPlay else { return }
        let itemTime = item.currentTime()
        guard probe.hasNewPixelBuffer(forItemTime: itemTime) else { return }
        _ = probe.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        lastFreshFrameAt = Date()
        let raw = itemTime.seconds.isFinite ? itemTime.seconds : 0
        positionAtLastFreshFrame = sdrTimelineOffsetSeconds + raw
        if !videoFramesObserved {
            videoFramesObserved = true
            markFirstFrameRendered()
            AppLog.playback.notice(
                "customplayer.video.first_frame — t=\(itemTime.seconds, format: .fixed(precision: 1)) (probe kept, draining)"
            )
        }
    }
#endif

    /// Plays the origin URL directly (no localhost) at the given position. The cache session stays
    /// alive (fill continues; a later rebuild can return to it), but AVPlayer streams natively.
    private func installOriginDirectItem(atSeconds seconds: Double) {
        guard let originSource else { return }
        var options: [String: Any] = [:]
        if let mime = resolvedMIMEType { options[AVURLAssetOverrideMIMETypeKey] = mime }
        if !originSource.headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = originSource.headers
        }
        let asset = AVURLAsset(url: originSource.url, options: options)
        let item = AVPlayerItem(asset: asset)
        player.automaticallyWaitsToMinimizeStalling = true
        player.replaceCurrentItem(with: item)
        if seconds > 0 {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
        }
        observeItemLifecycle(item)
        player.play()
    }

    // MARK: - External playback (AirPlay)

    /// While AirPlay is active the receiver must fetch the stream itself — swap the item to the
    /// ORIGIN URL at the current position (127.0.0.1 is unreachable from the receiver); swap back
    /// to the localhost cache when external playback ends. The DV session keeps filling underneath
    /// either way. SDR lane is already a remote URL — no swap needed there.
    func handleExternalPlaybackChange(active: Bool) {
        guard laneState.lane == .original else { return }
        if active {
            guard !isExternalPlaybackItemActive, let originSource else { return }
            isExternalPlaybackItemActive = true
            AppLog.playback.notice("customplayer.airplay.origin_swap — at=\(self.lastKnownTimeSeconds, format: .fixed(precision: 1))")
            var options: [String: Any] = [:]
            if let mime = resolvedMIMEType { options[AVURLAssetOverrideMIMETypeKey] = mime }
            if !originSource.headers.isEmpty {
                options["AVURLAssetHTTPHeaderFieldsKey"] = originSource.headers
            }
            let asset = AVURLAsset(url: originSource.url, options: options)
            let item = AVPlayerItem(asset: asset)
            player.automaticallyWaitsToMinimizeStalling = true
            player.replaceCurrentItem(with: item)
            if lastKnownTimeSeconds > 0 {
                player.seek(to: CMTime(seconds: lastKnownTimeSeconds, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
            }
            observeItemLifecycle(item)
            player.play()
        } else {
            guard isExternalPlaybackItemActive, let session, let localURL = session.localURL else { return }
            isExternalPlaybackItemActive = false
            AppLog.playback.notice("customplayer.airplay.back_to_cache — at=\(self.lastKnownTimeSeconds, format: .fixed(precision: 1))")
            installItem(localURL: localURL, seekTo: lastKnownTimeSeconds > 0 ? lastKnownTimeSeconds : nil)
            player.play()
        }
    }

    // MARK: - Last-resort SDR lane (drop + automatic DV return)

#if DEBUG
    /// Test hook: force a lane change with the same state mutation the policy performs, so the
    /// swap mechanics (item replacement, timeline offset, phase) are testable without waiting the
    /// policy's 90s sustained window.
    func debugForceLaneChange(_ change: AdaptiveLanePolicy.LaneChange) async {
        switch change {
        case .dropToSDR: laneState.lane = .sdrFallback
        case .returnToOriginal: laneState.lane = .original
        }
        await applyLaneChange(change)
    }
#endif

    func applyLaneChange(_ change: AdaptiveLanePolicy.LaneChange) async {
        switch change {
        case .dropToSDR:
            guard let adaptive = resolver as? CustomPlaybackAdaptiveFallbackResolving,
                  let itemID = currentItemID else {
                laneState.lane = .original // no fallback capability — stay honest on the original
                return
            }
            let at = max(0, lastKnownTimeSeconds)
            guard let url = await adaptive.resolveAdaptiveFallback(itemID: itemID, startSeconds: at) else {
                AppLog.playback.warning("customplayer.lane.sdr_unavailable — item=\(itemID.prefix(8), privacy: .public)")
                laneState.lane = .original
                return
            }
            AppLog.playback.warning(
                "customplayer.lane.drop_to_sdr — item=\(itemID.prefix(8), privacy: .public) at=\(at, format: .fixed(precision: 1))"
            )
            sdrTimelineOffsetSeconds = at
            lastTickSnapshot = nil
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 0
            player.automaticallyWaitsToMinimizeStalling = true
            player.replaceCurrentItem(with: item)
            observeItemLifecycle(item)
            player.play()
            bufferingState = PlaybackBufferingState(phase: .degradedSDR, reservoirSeconds: 0)

        case .returnToOriginal:
            guard let session, let localURL = session.localURL else { return }
            let at = max(0, lastKnownTimeSeconds)
            AppLog.playback.notice(
                "customplayer.lane.return_to_original — at=\(at, format: .fixed(precision: 1))"
            )
            sdrTimelineOffsetSeconds = 0
            lastTickSnapshot = nil
            installItem(localURL: localURL, seekTo: at > 0 ? at : nil)
            player.play()
            bufferingState = PlaybackBufferingState(phase: .playing, reservoirSeconds: 0)
        }
    }

    // MARK: - Markers (skip intro/credits) + external subtitles + binge chaining

    private func loadMarkers(itemID: String) {
        markersTask?.cancel()
        guard let markers else { return }
        markersTask = Task { [weak self] in
            let segments = await markers.mediaSegments(itemID: itemID)
            guard let self, !Task.isCancelled, self.currentItemID == itemID else { return }
            self.mediaSegments = segments
        }
    }

    /// Applies the current skip suggestion (seek past the segment, or chain to the next episode).
    public func skipCurrentSegment() {
        guard let suggestion = activeSkipSuggestion else { return }
        switch suggestion.target {
        case let .seek(to: targetSeconds):
            AppLog.playback.notice(
                "customplayer.skip.request — from=\(self.lastKnownTimeSeconds, format: .fixed(precision: 1)) target=\(targetSeconds, format: .fixed(precision: 1)) title=\(suggestion.title, privacy: .public)"
            )
            seek(toSeconds: targetSeconds)
            activeSkipSuggestion = nil
        case .nextEpisode:
            playNextEpisodeIfAvailable()
        }
    }

    private func playNextEpisodeIfAvailable() {
        guard let next = nextEpisodeQueue.first else { return }
        let remaining = Array(nextEpisodeQueue.dropFirst())
        onPlayNext?(next, remaining)
    }

    private func updateSkipSuggestion() {
        let suggestion = PlaybackSkipSuggestionResolver.suggestion(
            segments: mediaSegments,
            currentTime: lastKnownTimeSeconds,
            duration: durationSeconds,
            currentItem: currentMediaItem,
            nextEpisodeQueue: nextEpisodeQueue
        )
        if activeSkipSuggestion != suggestion { activeSkipSuggestion = suggestion }
    }

    /// Fine-grained (0.25s) title-position feed for the subtitle overlay — the 1s monitor tick is
    /// too coarse for cue timing.
    private func installTimeObserver() {
        if let timeObserverToken { player.removeTimeObserver(timeObserverToken) }
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let raw = time.seconds.isFinite ? time.seconds : 0
                self.subtitles.updateTime(self.sdrTimelineOffsetSeconds + raw)
#if os(tvOS)
                self.drainVideoProbe()
#endif
            }
        }
    }

    // MARK: - Item lifecycle observation (the never-freeze ladder inputs)

    private func observeItemLifecycle(_ item: AVPlayerItem) {
        removeItemObservers()
#if os(tvOS)
        // Native-format probe (nil attributes → zero conversion cost), kept attached and DRAINED
        // for the item's whole life — the render heartbeat. tvOS only — see `videoOutputProbe` doc.
        let probe = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        item.add(probe)
        videoOutputProbe = probe
        // Fresh item, fresh render clock: grace period before the frozen-picture watch can fire.
        lastFreshFrameAt = Date()
        positionAtLastFreshFrame = lastKnownTimeSeconds
#endif
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            let reason = observedItem.error?.localizedDescription ?? "-"
            Task { @MainActor [weak self] in
                guard let self else { return }
                AppLog.playback.notice(
                    "customplayer.item.status — status=\(status.rawValue, privacy: .public) error=\(reason, privacy: .public)"
                )
                if status == .failed {
                    self.handleItemFailure(reason: "item_failed: \(reason)")
                }
            }
        }
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            let reason = error?.localizedDescription ?? "unknown"
            Task { @MainActor [weak self] in
                self?.handleItemFailure(reason: "failed_to_play_to_end: \(reason)")
            }
        }
        didEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePlaybackEnded()
            }
        }
        if let stalledObserver { NotificationCenter.default.removeObserver(stalledObserver) }
        stalledObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main
        ) { [weak self] _ in
            // In NoStallWait mode CoreMedia changes to `.paused` after this notification and never
            // self-resumes, even when the local reservoir is deep. Preserve that distinction from
            // a user pause and let the bounded bypass/rebuild ladder recover it.
            Task { @MainActor in
                self?.observedPlaybackStall = true
                await self?.monitorTick()
            }
        }
    }

    private func removeItemObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
#if os(tvOS)
        videoOutputProbe = nil // the outgoing item keeps its output; the next observe adds a fresh one
#endif
        if let failedToEndObserver { NotificationCenter.default.removeObserver(failedToEndObserver) }
        failedToEndObserver = nil
        if let didEndObserver { NotificationCenter.default.removeObserver(didEndObserver) }
        didEndObserver = nil
        if let stalledObserver { NotificationCenter.default.removeObserver(stalledObserver) }
        stalledObserver = nil
    }

    // MARK: - Recovery ladder (rung 2: rebuild on warm cache; rung 3: honest error)

    /// AVPlayer never self-recovers from a `.failed` item, so a failure used to be a silent
    /// permanent freeze. Rebuild the item at the last known position over the SAME warm cache —
    /// bounded by a rolling window so a genuinely-dead source ends in an honest, retryable error.
    func handleItemFailure(reason: String) {
        guard session != nil else { return } // already torn down
        guard rebuildTask == nil else { return } // a rebuild is already scheduled
        guard bufferingState.phase != .failed else { return }

        let now = Date()
        rebuildTimestamps = rebuildTimestamps.filter { now.timeIntervalSince($0) <= rebuildWindowSeconds }
        guard rebuildTimestamps.count < maxRebuildsInWindow else {
            AppLog.playback.error("customplayer.recovery.exhausted — reason=\(reason, privacy: .public)")
            enterFailedState(message: "La lecture a échoué de façon répétée. Vérifiez la connexion au serveur, puis réessayez.")
            return
        }
        let attempt = rebuildTimestamps.count
        rebuildTimestamps.append(now)
        let backoff = rebuildBackoffSeconds[min(attempt, rebuildBackoffSeconds.count - 1)]
        AppLog.playback.warning(
            "customplayer.recovery.rebuild — attempt=\(attempt + 1, privacy: .public) backoff=\(backoff, format: .fixed(precision: 1)) at=\(self.lastKnownTimeSeconds, format: .fixed(precision: 1)) reason=\(reason, privacy: .public)"
        )
        bufferingState = PlaybackBufferingState(
            phase: .buffering, reservoirSeconds: 0, targetSeconds: PlaybackLanePolicy.bufferResumeSeconds)
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.rebuildTask = nil
            self.rebuildCurrentItem()
        }
    }

    private func rebuildCurrentItem() {
        lastTransportAdvanceAt = Date()
        lastTransportPositionSeconds = lastKnownTimeSeconds
        didForceImmediatePlaybackForCurrentStall = false
        didRequestWarmRebuildForCurrentStall = false
        observedPlaybackStall = false
        // A rebuild that never showed a picture must stay under first-frame surveillance, so a
        // still-black rebuilt item escalates instead of parking silently.
        if !hasRenderedFirstFrame { startFirstFrameWatchdog() }
        // While AirPlaying, a rebuild must land on the ORIGIN URL again (localhost is unreachable
        // from the receiver).
        if isExternalPlaybackItemActive {
            isExternalPlaybackItemActive = false
            handleExternalPlaybackChange(active: true)
            return
        }
        // Adaptive-only lane (no cache session): reinstall the stream and seek back within it.
        if session == nil, let adaptiveStreamURL {
            let item = AVPlayerItem(url: adaptiveStreamURL)
            player.automaticallyWaitsToMinimizeStalling = true
            player.replaceCurrentItem(with: item)
            let rawResume = max(0, lastKnownTimeSeconds - sdrTimelineOffsetSeconds)
            if rawResume > 0 {
                player.seek(to: CMTime(seconds: rawResume, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
            }
            observeItemLifecycle(item)
            player.play()
            return
        }
        guard let session, let localURL = session.localURL else { return }
        // A failed SDR item rebuilds onto the ORIGINAL (warm cache) — the lane brain can re-drop
        // later if the inability persists.
        laneState.lane = .original
        sdrTimelineOffsetSeconds = 0
        let resume = max(0, lastKnownTimeSeconds)
        installItem(localURL: localURL, seekTo: resume > 0 ? resume : nil)
        player.play()
    }

    private func enterFailedState(message: String) {
        errorMessage = message
        bufferingState = PlaybackBufferingState(phase: .failed)
        player.pause()
    }

    private func handlePlaybackEnded() {
        bufferingState = PlaybackBufferingState(phase: .ended, reservoirSeconds: 0)
        if let reporter, !didReportStop {
            didReportStop = true
            let ticks = Int64(max(lastKnownTimeSeconds, durationSeconds) * 10_000_000)
            let update = progressUpdate(positionTicks: ticks, isPaused: false, isPlaying: false, didFinish: true)
            Task { await reporter.reportStopped(update) }
        }
        // Binge chaining: an episode with a queued follower rolls straight into it.
        if currentMediaItem?.mediaType == .episode, !nextEpisodeQueue.isEmpty {
            playNextEpisodeIfAvailable()
            return
        }
        onPlaybackEnded?()
    }

    // MARK: - Audio session recovery

    /// If the audio session gets interrupted (a call, Siri, another app), reactivate it and resume
    /// so sound comes back — otherwise the picture keeps playing silently (the "lost sound" symptom).
    private func observeAudioSessionChanges() {
#if os(iOS) || os(tvOS)
        if let observer = audioInterruptionObserver { NotificationCenter.default.removeObserver(observer) }
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let info = note.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }

            switch type {
            case .began:
                self.wasPlayingBeforeAudioInterruption =
                    self.player.rate > 0 || self.player.timeControlStatus == .playing
            case .ended:
                let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map(AVAudioSession.InterruptionOptions.init(rawValue:))
                let decision = CustomPlayerAudioRecoveryPolicy.decision(
                    for: .interruptionEnded(systemShouldResume: options?.contains(.shouldResume) ?? true),
                    wasPlaying: self.wasPlayingBeforeAudioInterruption
                )
                self.wasPlayingBeforeAudioInterruption = false
                self.scheduleAudioOutputRecovery(decision, reason: "interruption-ended")
            @unknown default:
                break
            }
        }

        if let observer = audioRouteChangeObserver { NotificationCenter.default.removeObserver(observer) }
        audioRouteChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  CustomPlayerAudioRecoveryPolicy.shouldRecoverRouteChange(reason)
            else { return }
            let wasPlaying = self.player.rate > 0 || self.player.timeControlStatus == .playing
            let decision = CustomPlayerAudioRecoveryPolicy.decision(
                for: .routeChanged,
                wasPlaying: wasPlaying
            )
            self.scheduleAudioOutputRecovery(decision, reason: "route-\(raw)")
        }
#endif
    }

    /// Route notifications often arrive in a burst. Coalesce them, activate AVAudioSession away
    /// from the main thread, then restore transport only when playback was already intended.
    private func scheduleAudioOutputRecovery(
        _ decision: CustomPlayerAudioRecoveryPolicy.Decision,
        reason: String
    ) {
        guard decision.reactivateSession else { return }
        audioRecoveryTask?.cancel()
        audioRecoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let activated = await Task.detached(priority: .userInitiated) {
                Self.activateAudioSessionForPlayback()
            }.value
            guard let self, !Task.isCancelled else { return }
            AppLog.playback.notice(
                "customplayer.audio.recovered — reason=\(reason, privacy: .public) active=\(activated, privacy: .public) resume=\(decision.resumePlayback, privacy: .public)"
            )
            if decision.resumePlayback {
                self.player.playImmediately(atRate: 1)
            }
            self.audioRecoveryTask = nil
        }
    }

    // MARK: - Teardown

    private func teardown() {
        loadTask?.cancel(); loadTask = nil
        monitorTask?.cancel(); monitorTask = nil
        rebuildTask?.cancel(); rebuildTask = nil
        markersTask?.cancel(); markersTask = nil
        firstFrameWatchdogTask?.cancel(); firstFrameWatchdogTask = nil
        audioRecoveryTask?.cancel(); audioRecoveryTask = nil
        if let timeObserverToken { player.removeTimeObserver(timeObserverToken) }
        timeObserverToken = nil
        subtitles.configure(tracks: [])
        activeSkipSuggestion = nil
        removeItemObservers()
        if let observer = audioInterruptionObserver { NotificationCenter.default.removeObserver(observer) }
        audioInterruptionObserver = nil
        if let observer = audioRouteChangeObserver { NotificationCenter.default.removeObserver(observer) }
        audioRouteChangeObserver = nil
        wasPlayingBeforeAudioInterruption = false
        session?.stop(); session = nil
        monitor = nil
        lastTickSnapshot = nil
        lastTransportAdvanceAt = .distantPast
        lastTransportPositionSeconds = 0
        didForceImmediatePlaybackForCurrentStall = false
        didRequestWarmRebuildForCurrentStall = false
        observedPlaybackStall = false
        player.replaceCurrentItem(with: nil)
    }
}
