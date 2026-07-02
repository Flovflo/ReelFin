import AVFoundation
import Foundation
import NativeMediaCore
import Observation
import Shared

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
    /// True when this is a server ADAPTIVE stream (HLS transcode/remux) rather than the raw
    /// original: the engine then plays the URL directly (AVPlayer's own HLS stack — segments are
    /// their own dropout recovery) and skips the byte-range cache session entirely.
    public let isAdaptiveStream: Bool
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
        isAdaptiveStream: Bool = false,
        externalSubtitles: [ExternalSubtitleTrack] = []
    ) {
        self.originURL = originURL
        self.headers = headers
        self.sourceBitrate = sourceBitrate
        self.overrideMIMEType = overrideMIMEType
        self.cacheKey = cacheKey
        self.isDolbyVision = isDolbyVision
        self.isAdaptiveStream = isAdaptiveStream
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
    /// Fired once when the title plays to its end (dismiss / up-next hook for the UI).
    public var onPlaybackEnded: (() -> Void)?
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
    /// Set by the UI host while Picture in Picture runs, so a disappearing view doesn't stop it.
    public var isPictureInPictureActive = false

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
    private static func configureAudioSessionForPlayback() {
#if os(iOS) || os(tvOS)
        DispatchQueue.global(qos: .userInitiated).async {
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
            } catch {
                do {
                    try session.setCategory(.playback)
                    try session.setActive(true)
                } catch {
                    AppLog.playback.warning("customplayer.audioSession.failed — \(error.localizedDescription, privacy: .public)")
                }
            }
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
        mediaSegments = []
        activeSkipSuggestion = nil
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

    public func play() { player.play() }
    public func pause() { player.pause() }

    public func seek(toSeconds seconds: Double) {
        lastKnownTimeSeconds = max(0, seconds)
        lastTickSnapshot = nil // a jump invalidates the fill-rate delta
        session?.setPlayheadOffset(session?.byteOffset(forSeconds: seconds) ?? 0)
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
    }

    /// Last playback position the engine observed (drives resume reporting and retry).
    public var lastObservedSeconds: Double { lastKnownTimeSeconds }

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

        if let warm = prewarmer?.consume(itemID: itemID) {
            // Perceived-instant start: the detail view already resolved the source, started the
            // localhost session, and built (part of) the cushion — adopt the ready pipeline.
            AppLog.playback.notice("customplayer.load.adopts_prewarm — item=\(itemID.prefix(8), privacy: .public)")
            resolved = warm.resolved
            session = warm.session
            localURL = warm.localURL
        } else {
            do {
                resolved = try await resolver.resolveOriginal(itemID: itemID, startTimeTicks: startTimeTicks)
            } catch {
                enterFailedState(message: "Impossible de résoudre la source : \(error.localizedDescription)")
                return
            }
            guard !Task.isCancelled else { return }
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
        observeAudioInterruptions()
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

    /// Non-direct-playable source (container/codec AVFoundation can't open raw): play the server's
    /// adaptive HLS stream directly. The item lifecycle ladder still applies (rebuild on failure →
    /// honest error); the reservoir HUD stays hidden (no cache session — segments self-recover).
    private func startAdaptivePlayback(resolved: ResolvedOriginalSource, startTimeTicks: Int64?, autoPlay: Bool) {
        AppLog.playback.notice(
            "customplayer.load.adaptive_lane — item=\(self.currentItemID?.prefix(8) ?? "-", privacy: .public)"
        )
        Self.configureAudioSessionForPlayback()
        observeAudioInterruptions()
        sourceBitrateMbps = Double(resolved.sourceBitrate ?? 30_000_000) / 1_000_000
        sourceQualityLabel = nil
        adaptiveStreamURL = resolved.originURL
        subtitles.configure(tracks: resolved.externalSubtitles)
        installTimeObserver()
        sdrTimelineOffsetSeconds = Double(startTimeTicks ?? 0) / 10_000_000 // HLS timeline is 0-based at the resume point
        let item = AVPlayerItem(url: resolved.originURL)
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
        item.preferredForwardBufferDuration = 0 // fast first frame; reservoir lives on disk
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
        let deadline = Date().addingTimeInterval(40) // hard safety: never gate the start forever
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
                    measuredMbps = max(0, (depth - first.depth) / span) * sourceBitrateMbps
                    if let measuredMbps { monitor?.record(mbps: measuredMbps, at: now) }
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
        if autoPlay { player.play() }
        // Phase B (blueprint §6): once playback is rolling, step the in-RAM forward buffer up so
        // AVPlayer keeps ~30s decoded ahead ON TOP of the disk reservoir (fed at disk speed from
        // localhost — no network cost). The startup gate already ran with 0 for the fast first frame.
        player.currentItem?.preferredForwardBufferDuration = 30
    }

    // MARK: - Steady monitor (loading bar + connection measurement + position tracking)

    private func startMonitorLoop(startSeconds: Double) {
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
        guard let session else {
            // Adaptive-only lane (no cache session): position + honest transport + server progress.
            let isStarving = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            bufferingState = PlaybackBufferingState(
                phase: isStarving ? .buffering : .degradedSDR,
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

        // Drive the loading bar from AVPlayer's REAL transport state, not the byte estimate. Only a
        // genuine stall (AVPlayer has run dry and is waiting for data) shows the bar.
        let isStarving = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        switch (laneState.lane, isStarving) {
        case (.sdrFallback, _):
            bufferingState = PlaybackBufferingState(phase: .degradedSDR, reservoirSeconds: reservoir)
        case (.original, true):
            bufferingState = PlaybackBufferingState(
                phase: .buffering, reservoirSeconds: reservoir, targetSeconds: PlaybackLanePolicy.bufferResumeSeconds)
        case (.original, false):
            bufferingState = PlaybackBufferingState(phase: .playing, reservoirSeconds: reservoir)
        }

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

        updateSkipSuggestion()
        reportProgressIfDue(now: now)
        await session.maintainDiskBudget(currentSeconds: nowSeconds)
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
            }
        }
    }

    // MARK: - Item lifecycle observation (the never-freeze ladder inputs)

    private func observeItemLifecycle(_ item: AVPlayerItem) {
        removeItemObservers()
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard observedItem.status == .failed else { return }
            let reason = observedItem.error?.localizedDescription ?? "unknown"
            Task { @MainActor [weak self] in
                self?.handleItemFailure(reason: "item_failed: \(reason)")
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
            // Reload-averse by design: a stall only updates the loading bar; the reservoir keeps
            // filling underneath and AVPlayer resumes on its own.
            Task { @MainActor in await self?.monitorTick() }
        }
    }

    private func removeItemObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
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

    // MARK: - Audio session interruptions

    /// If the audio session gets interrupted (a call, Siri, another app), reactivate it and resume
    /// so sound comes back — otherwise the picture keeps playing silently (the "lost sound" symptom).
    private func observeAudioInterruptions() {
#if os(iOS)
        if let observer = audioInterruptionObserver { NotificationCenter.default.removeObserver(observer) }
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let info = note.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended
            else { return }
            Self.configureAudioSessionForPlayback()
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:))
            if options?.contains(.shouldResume) ?? true { self.player.play() }
        }
#endif
    }

    // MARK: - Teardown

    private func teardown() {
        loadTask?.cancel(); loadTask = nil
        monitorTask?.cancel(); monitorTask = nil
        rebuildTask?.cancel(); rebuildTask = nil
        markersTask?.cancel(); markersTask = nil
        if let timeObserverToken { player.removeTimeObserver(timeObserverToken) }
        timeObserverToken = nil
        subtitles.configure(tracks: [])
        activeSkipSuggestion = nil
        removeItemObservers()
        if let observer = audioInterruptionObserver { NotificationCenter.default.removeObserver(observer) }
        audioInterruptionObserver = nil
        session?.stop(); session = nil
        monitor = nil
        lastTickSnapshot = nil
        player.replaceCurrentItem(with: nil)
    }
}
