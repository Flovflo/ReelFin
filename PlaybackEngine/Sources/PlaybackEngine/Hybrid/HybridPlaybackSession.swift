import AVFoundation
import Foundation
import Observation
import Shared
import UIKit

// MARK: - Hybrid Playback Session

/// Unified playback session that transparently delegates to either AVPlayer (native)
/// or VLCKit based on deterministic capability analysis.
///
/// The UI layer talks exclusively to this class. It never knows which engine is active.
/// Fallback from native to VLC is bounded, deterministic, and fully logged.
@Observable
@MainActor
public final class HybridPlaybackSession {

    // MARK: - Public Observable State

    public private(set) var isPlaying = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var availableAudioTracks: [MediaTrack] = []
    public private(set) var availableSubtitleTracks: [MediaTrack] = []
    public private(set) var selectedAudioTrackID: String?
    public private(set) var selectedSubtitleTrackID: String?
    public private(set) var playbackErrorMessage: String?
    public private(set) var isBuffering = false
    public private(set) var playbackState: UnifiedPlaybackState = .idle
    public private(set) var startupMetrics = PlaybackStartupMetrics()
    public private(set) var activeEngineType: PlaybackEngineType?
    public private(set) var engineDecision: EngineCapabilityDecision?

    // MARK: - Legacy Compatibility

    /// Expose debug info compatible with existing PlaybackDebugInfo consumers.
    public private(set) var debugInfo: PlaybackDebugInfo?
    public private(set) var runtimeHDRMode: HDRPlaybackMode = .unknown
    public private(set) var metrics = PlaybackPerformanceMetrics()
    public private(set) var isExternalPlaybackActive = false
    public private(set) var playbackProof = PlaybackProofSnapshot()
    public private(set) var currentPlaybackPlan: PlaybackPlan?
    public private(set) var routeDescription: String = ""

    /// The native AVPlayer, if the native engine is active.
    /// Used by NativePlayerViewController to render video.
    public var nativePlayer: AVPlayer? {
        (activeEngine as? NativeAVPlayerEngine)?.avPlayer
            ?? nativeSessionController?.player
    }

    /// The VLC video view, if the VLC engine is active.
    public var vlcVideoView: UIView? {
        vlcEngine?.videoView
    }

    /// Whether the current engine is native AVPlayer.
    public var isNativeEngine: Bool {
        activeEngineType == .native || nativeSessionController != nil
    }

    // MARK: - Dependencies

    private let apiClient: any JellyfinAPIClientProtocol & Sendable
    private let repository: MetadataRepositoryProtocol
    private let warmupManager: (any PlaybackWarmupManaging)?
    private let capabilityEngine = HybridCapabilityEngine()
    private let sourceSelector = HybridSourceSelector()
    private let vlcURLResolver = HybridVLCURLResolver()
    private let diagnosticsLogger = PlaybackDiagnosticsLogger()
    private let metricsCollector = StartupMetricsCollector()
    private let playbackCoordinator: PlaybackCoordinator

    // MARK: - Engine State

    /// The native PlaybackSessionController, used for the primary native path.
    /// This preserves ALL existing native behavior (watchdog, recovery, HLS, NativeBridge, etc.)
    private var nativeSessionController: PlaybackSessionController?

    /// Standalone native engine adapter (for future use when decoupled from PSC).
    private var nativeEngine: NativeAVPlayerEngine?

    /// VLC engine adapter.
    private var vlcEngine: VLCPlaybackEngine?

    /// The currently active engine adapter.
    private var activeEngine: (any PlaybackEngineAdapter)?

    /// Fallback tracking
    private var fallbackAttempted = false
    private var currentItemID: String?
    private var currentItem: MediaItem?
    private var currentSource: MediaSource?
    private var currentMediaCharacteristics: MediaCharacteristics?
    private var startupWatchdogTask: Task<Void, Never>?
    private var hasRecordedFirstFrame = false
    private var hasLoggedStartupMetrics = false
    private var startupBufferingObserved = false

    /// Maximum native startup time before falling back to VLC (seconds).
    private let nativeStartupTimeoutSeconds: TimeInterval = 15

    // MARK: - Init

    public init(
        apiClient: any JellyfinAPIClientProtocol & Sendable,
        repository: MetadataRepositoryProtocol,
        warmupManager: (any PlaybackWarmupManaging)? = nil,
        decisionEngine: PlaybackDecisionEngine = PlaybackDecisionEngine()
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.warmupManager = warmupManager
        self.playbackCoordinator = PlaybackCoordinator(apiClient: apiClient, decisionEngine: decisionEngine)
    }

    // MARK: - Public API

    /// Load and start playback for a media item.
    /// This is the main entry point, equivalent to PlaybackSessionController.load().
    public func load(item: MediaItem, autoPlay: Bool = true) async throws {
        // Reset state
        currentItemID = item.id
        currentItem = item
        currentSource = nil
        fallbackAttempted = false
        playbackErrorMessage = nil
        hasRecordedFirstFrame = false
        hasLoggedStartupMetrics = false
        startupBufferingObserved = false
        updatePlaybackState(.preparing)
        startupWatchdogTask?.cancel()
        metricsCollector.reset()
        metricsCollector.markTap()

        // Step 1: Fetch playback sources and analyze capabilities
        let sources: [MediaSource]
        do {
            sources = try await apiClient.fetchPlaybackSources(itemID: item.id)
        } catch {
            playbackErrorMessage = error.localizedDescription
            updatePlaybackState(.failed)
            finalizeStartupMetricsIfNeeded()
            throw error
        }

        guard let analysisSource = sourceSelector.analysisSource(from: sources) else {
            let msg = "No playback source available."
            playbackErrorMessage = msg
            updatePlaybackState(.failed)
            finalizeStartupMetricsIfNeeded()
            throw AppError.network(msg)
        }

        // Step 2: Capability analysis
        let media = MediaCharacteristics.from(source: analysisSource)
        currentSource = analysisSource
        currentMediaCharacteristics = media
        let rawDecision = capabilityEngine.evaluate(media)
        let vlcAvailable = isVLCAvailable
        let decision = if vlcAvailable {
            rawDecision
        } else {
            HybridEngineRuntimePolicy.normalize(rawDecision, vlcAvailable: false)
        }
        engineDecision = decision

        // Step 3: Determine engine to use
        let engineToUse = resolveEngine(from: decision)
        metricsCollector.markDecision(
            engine: engineToUse,
            reason: decision.recommendation.rawValue
        )
        refreshStartupMetrics()

        if !vlcAvailable, rawDecision.recommendation == .vlcRequired {
            diagnosticsLogger.logEngineAvailability(
                itemID: item.id,
                vlcAvailable: false,
                reason: "VLCKit is not linked in this build; VLC-required media is being normalized to the Apple-native server pipeline."
            )
        }
        let requestedEngine = HybridEngineRuntimePolicy.resolveEngine(for: rawDecision, vlcAvailable: true)
        if !vlcAvailable, requestedEngine != engineToUse {
            diagnosticsLogger.logEngineOverride(
                itemID: item.id,
                requestedEngine: requestedEngine,
                selectedEngine: engineToUse,
                reason: "VLCKit is not linked in this build; falling back to Apple-native playback coordination."
            )
        }

        diagnosticsLogger.logDecision(
            itemID: item.id,
            decision: decision,
            media: media,
            selectedEngine: engineToUse
        )

        // Log HDR decision
        if decision.hdrExpectation != HDRExpectation.sdr {
            let preserved = engineToUse == .native
            diagnosticsLogger.logHDRDecision(
                itemID: item.id,
                engine: engineToUse,
                hdrExpectation: decision.hdrExpectation,
                preservationFactor: preserved,
                reason: preserved
                    ? "Native path preserves premium HDR/DV rendering"
                    : "VLC fallback may degrade HDR/DV quality for compatibility"
            )
        }

        let playbackSource = sourceSelector.playbackSource(
            for: engineToUse,
            from: sources,
            preferred: analysisSource
        ) ?? analysisSource

        // Step 4: Start playback with the chosen engine
        do {
            switch engineToUse {
            case .native:
                let selection = try await resolveNativeSelection(itemID: item.id)
                try await startNativePlayback(item: item, selection: selection, autoPlay: autoPlay)
            case .vlc:
                try await startVLCPlayback(item: item, source: playbackSource, autoPlay: autoPlay)
            }
        } catch {
            // If native failed and fallback is allowed, try VLC
            if engineToUse == .native && !fallbackAttempted && shouldAttemptFallback(decision: decision) {
                try await performFallbackToVLC(reason: error.localizedDescription, item: item, source: playbackSource, autoPlay: autoPlay)
                return
            }

            playbackErrorMessage = error.localizedDescription
            updatePlaybackState(.failed)
            finalizeStartupMetricsIfNeeded()
            throw error
        }
    }

    public func play() {
        if let controller = nativeSessionController {
            controller.play()
        } else {
            activeEngine?.play()
        }
        isPlaying = true
        updatePlaybackState(.playing)
    }

    public func pause() {
        if let controller = nativeSessionController {
            controller.pause()
        } else {
            activeEngine?.pause()
        }
        isPlaying = false
        updatePlaybackState(.paused)
    }

    public func seek(to seconds: TimeInterval) async {
        updatePlaybackState(.seeking)
        if nativeSessionController != nil {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
            _ = await nativeSessionController?.player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
        } else {
            await activeEngine?.seek(to: seconds)
        }
    }

    public func stop() {
        startupWatchdogTask?.cancel()
        nativeSessionController?.pause()
        activeEngine?.stop()
        nativeSessionController = nil
        nativeEngine = nil
        vlcEngine = nil
        activeEngine = nil
        activeEngineType = nil
        nativeSyncTimer?.invalidate()
        nativeSyncTimer = nil
        updatePlaybackState(.idle)
        isPlaying = false
    }

    public func selectAudioTrack(id: String) {
        if let controller = nativeSessionController {
            controller.selectAudioTrack(id: id)
        } else {
            activeEngine?.selectAudioTrack(id: id)
        }
        selectedAudioTrackID = id
        logSelectedAudioTrack()
    }

    public func selectSubtitleTrack(id: String?) {
        if let controller = nativeSessionController {
            controller.selectSubtitleTrack(id: id)
        } else {
            activeEngine?.selectSubtitleTrack(id: id)
        }
        selectedSubtitleTrackID = id
        logSelectedSubtitleTrack()
    }

    // MARK: - Convenience Accessors

    /// The AVPlayer for native playback (backward compatible with existing PlayerView).
    public var player: AVPlayer {
        nativePlayer ?? AVPlayer() // Return empty player as safety fallback
    }

    // MARK: - Engine Resolution

    private func resolveEngine(from decision: EngineCapabilityDecision) -> PlaybackEngineType {
        HybridEngineRuntimePolicy.resolveEngine(for: decision, vlcAvailable: isVLCAvailable)
    }

    private var isVLCAvailable: Bool {
        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        return true
        #else
        return false
        #endif
    }

    private func shouldAttemptFallback(decision: EngineCapabilityDecision) -> Bool {
        guard isVLCAvailable else { return false }
        return decision.recommendation != .unsupported
    }

    // MARK: - Native Playback

    private func startNativePlayback(
        item: MediaItem,
        selection: PlaybackAssetSelection,
        autoPlay: Bool
    ) async throws {
        // Use the full PlaybackSessionController for native path.
        // This preserves all existing behavior: watchdog, recovery, HLS, NativeBridge, etc.
        let controller = PlaybackSessionController(
            apiClient: apiClient,
            repository: repository,
            warmupManager: warmupManager
        )
        self.nativeSessionController = controller
        self.activeEngineType = .native
        metricsCollector.markPlayerSetup()
        refreshStartupMetrics()

        diagnosticsLogger.logEngineStartup(engine: .native, url: item.id, itemID: item.id)

        try await controller.load(item: item, preparedSelection: selection, autoPlay: autoPlay)

        // Sync state from native controller
        syncNativeState()
        scheduleNativeStateSync()

        diagnosticsLogger.logEngineReady(
            engine: .native,
            setupMs: metricsCollector.snapshot().decisionToPlayerSetupMs ?? 0,
            itemID: item.id
        )
    }

    // MARK: - VLC Playback

    private func resolveNativeSelection(itemID: String) async throws -> PlaybackAssetSelection {
        let selection = try await playbackCoordinator.resolvePlayback(
            itemID: itemID,
            mode: .performance,
            allowTranscodingFallbackInPerformance: false,
            transcodeProfile: .serverDefault
        )
        guard case .directPlay = selection.decision.route else {
            throw AppError.network("Native playback requires Apple direct play; falling back to VLC.")
        }
        return selection
    }

    private func startVLCPlayback(item: MediaItem, source: MediaSource, autoPlay: Bool) async throws {
        guard
            let configuration = await apiClient.currentConfiguration(),
            let session = await apiClient.currentSession(),
            let endpoint = vlcURLResolver.resolve(source: source, configuration: configuration, session: session)
        else {
            throw AppError.network("No playable URL for VLC engine.")
        }
        let url = endpoint.url

        let engine = VLCPlaybackEngine()
        self.vlcEngine = engine
        self.activeEngine = engine
        self.activeEngineType = .vlc
        self.nativeSessionController = nil
        metricsCollector.markPlayerSetup()
        refreshStartupMetrics()

        // Wire callbacks
        engine.onStateChange = { [weak self] state in
            self?.updatePlaybackState(state)
            if state == .buffering && self?.hasRecordedFirstFrame == false {
                self?.metricsCollector.markBufferingEvent()
                self?.refreshStartupMetrics()
            }
        }
        engine.onTimeUpdate = { [weak self] time in
            self?.currentTime = time
            self?.markFirstFrameIfNeeded(trigger: "vlc_time_update")
        }
        engine.onPlaybackEnded = { [weak self] in
            self?.isPlaying = false
            self?.updatePlaybackState(.ended)
        }
        engine.onError = { [weak self] message in
            self?.playbackErrorMessage = message
            self?.diagnosticsLogger.logEngineError(engine: .vlc, error: message, itemID: item.id)
            self?.updatePlaybackState(.failed)
            self?.finalizeStartupMetricsIfNeeded()
        }

        diagnosticsLogger.logEngineStartup(engine: .vlc, url: url.absoluteString, itemID: item.id)

        try await engine.prepare(url: url, headers: endpoint.headers)

        // Map Jellyfin tracks (richer metadata) + engine tracks
        syncVLCState()

        if autoPlay {
            engine.play()
            isPlaying = true
            updatePlaybackState(.playing)
        }

        markFirstFrameIfNeeded(trigger: "vlc_ready")
        diagnosticsLogger.logEngineReady(
            engine: .vlc,
            setupMs: metricsCollector.snapshot().decisionToPlayerSetupMs ?? 0,
            itemID: item.id
        )
    }

    // MARK: - State Sync

    private var nativeSyncTimer: Timer?

    private func scheduleNativeStateSync() {
        nativeSyncTimer?.invalidate()
        nativeSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncNativeState()
            }
        }
    }

    private func syncNativeState() {
        guard let controller = nativeSessionController else { return }

        isPlaying = controller.isPlaying
        currentTime = controller.currentTime
        duration = controller.duration
        availableAudioTracks = controller.availableAudioTracks
        availableSubtitleTracks = controller.availableSubtitleTracks
        selectedAudioTrackID = controller.selectedAudioTrackID
        selectedSubtitleTrackID = controller.selectedSubtitleTrackID
        debugInfo = controller.debugInfo
        runtimeHDRMode = controller.runtimeHDRMode
        metrics = controller.metrics
        isExternalPlaybackActive = controller.isExternalPlaybackActive
        playbackProof = controller.playbackProof
        currentPlaybackPlan = controller.currentPlaybackPlan
        routeDescription = controller.routeDescription

        if let error = controller.playbackErrorMessage {
            playbackErrorMessage = error
            if shouldEscalateNativeFailure(error) {
                diagnosticsLogger.logEngineError(engine: .native, error: error, itemID: currentItemID ?? "unknown")
                Task { @MainActor [weak self] in
                    await self?.handleNativeStartupFailure(reason: error)
                }
            }
        }

        // Map native controller's effective state
        if !hasRecordedFirstFrame, controller.player.timeControlStatus == .waitingToPlayAtSpecifiedRate, !startupBufferingObserved {
            startupBufferingObserved = true
            metricsCollector.markBufferingEvent()
            refreshStartupMetrics()
        } else if controller.player.timeControlStatus != .waitingToPlayAtSpecifiedRate {
            startupBufferingObserved = false
        }

        if controller.metrics.timeToFirstFrameMs != nil || controller.currentTime > 0 {
            markFirstFrameIfNeeded(trigger: "native_first_frame")
        }

        if controller.isPlaying {
            updatePlaybackState(.playing)
        } else if controller.player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            updatePlaybackState(.buffering)
        }
    }

    private func syncVLCState() {
        guard let engine = vlcEngine else { return }

        // Prefer Jellyfin metadata for track info (richer than VLC track names)
        // Fall back to engine-provided tracks
        if !engine.audioTracks.isEmpty {
            availableAudioTracks = engine.audioTracks.map { track in
                MediaTrack(
                    id: track.id,
                    title: track.title,
                    language: track.language,
                    codec: track.codec,
                    isDefault: track.isDefault,
                    index: track.index
                )
            }
        }

        if !engine.subtitleTracks.isEmpty {
            availableSubtitleTracks = engine.subtitleTracks.map { track in
                MediaTrack(
                    id: track.id,
                    title: track.title,
                    language: track.language,
                    codec: track.codec,
                    isDefault: track.isDefault,
                    index: track.index
                )
            }
        }

        duration = engine.duration
    }

    // MARK: - Diagnostics + Startup Handling

    private func updatePlaybackState(_ newState: UnifiedPlaybackState) {
        guard playbackState != newState else { return }
        let oldState = playbackState
        playbackState = newState
        if let itemID = currentItemID, let engine = activeEngineType {
            diagnosticsLogger.logStateTransition(from: oldState, to: newState, engine: engine, itemID: itemID)
        }
        if newState == .failed || newState == .ended {
            finalizeStartupMetricsIfNeeded()
        }
    }

    private func refreshStartupMetrics() {
        startupMetrics = metricsCollector.snapshot()
    }

    private func markFirstFrameIfNeeded(trigger: String) {
        guard !hasRecordedFirstFrame, let itemID = currentItemID else { return }
        hasRecordedFirstFrame = true
        metricsCollector.markFirstFrame()
        refreshStartupMetrics()
        diagnosticsLogger.logStartupMetrics(startupMetrics, itemID: itemID)
        hasLoggedStartupMetrics = true
        startupWatchdogTask?.cancel()
        AppLog.playback.notice("[PLAYBACK-STARTUP] item=\(itemID, privacy: .public) event=first_frame trigger=\(trigger, privacy: .public)")
    }

    private func finalizeStartupMetricsIfNeeded() {
        guard !hasLoggedStartupMetrics, let itemID = currentItemID else { return }
        refreshStartupMetrics()
        diagnosticsLogger.logStartupMetrics(startupMetrics, itemID: itemID)
        hasLoggedStartupMetrics = true
    }

    private func shouldEscalateNativeFailure(_ message: String) -> Bool {
        guard !hasRecordedFirstFrame else { return false }
        guard activeEngineType == .native else { return false }
        return !message.isEmpty
    }

    private func scheduleStartupWatchdogIfNeeded(decision: EngineCapabilityDecision?) {
        guard let decision, activeEngineType == .native else { return }
        startupWatchdogTask?.cancel()
        let timeout = startupTimeout(for: decision)
        startupWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                guard !self.hasRecordedFirstFrame else { return }
                guard self.activeEngineType == .native else { return }
                Task { @MainActor [weak self] in
                    await self?.handleNativeStartupFailure(reason: "hybrid_startup_watchdog_\(Int(timeout))s")
                }
            }
        }
    }

    private func startupTimeout(for decision: EngineCapabilityDecision) -> TimeInterval {
        switch decision.startupRisk {
        case .none:
            return nativeStartupTimeoutSeconds
        case .low:
            return min(nativeStartupTimeoutSeconds, 12)
        case .medium:
            return min(nativeStartupTimeoutSeconds, 10)
        case .high, .critical:
            return min(nativeStartupTimeoutSeconds, 8)
        }
    }

    private func handleNativeStartupFailure(reason: String) async {
        guard let item = currentItem, let source = currentSource else { return }
        guard activeEngineType == .native else { return }
        guard !hasRecordedFirstFrame else { return }
        if shouldAttemptFallback(decision: engineDecision ?? EngineCapabilityDecision(recommendation: .nativePreferred, reasons: [])) {
            do {
                try await performFallbackToVLC(reason: reason, item: item, source: source, autoPlay: true)
            } catch {
                playbackErrorMessage = error.localizedDescription
                updatePlaybackState(.failed)
                finalizeStartupMetricsIfNeeded()
            }
        } else {
            playbackErrorMessage = reason
            updatePlaybackState(.failed)
            finalizeStartupMetricsIfNeeded()
        }
    }

    private func performFallbackToVLC(
        reason: String,
        item: MediaItem,
        source: MediaSource,
        autoPlay: Bool
    ) async throws {
        guard !fallbackAttempted else { return }
        fallbackAttempted = true
        metricsCollector.markRetry()
        metricsCollector.markFallback(reason: reason)
        refreshStartupMetrics()
        diagnosticsLogger.logFallback(from: .native, to: .vlc, reason: reason, itemID: item.id)
        startupWatchdogTask?.cancel()
        nativeSyncTimer?.invalidate()
        nativeSyncTimer = nil
        nativeSessionController?.pause()
        nativeSessionController = nil
        activeEngine = nil
        activeEngineType = nil
        updatePlaybackState(.retrying)
        try await startVLCPlayback(item: item, source: source, autoPlay: autoPlay)
    }

    private func logSelectedAudioTrack() {
        guard let itemID = currentItemID, let engine = activeEngineType else { return }
        let codec = availableAudioTracks.first(where: { $0.id == selectedAudioTrackID })?.codec
        diagnosticsLogger.logAudioSelection(itemID: itemID, engine: engine, trackID: selectedAudioTrackID, codec: codec)
    }

    private func logSelectedSubtitleTrack() {
        guard let itemID = currentItemID, let engine = activeEngineType else { return }
        let codec = availableSubtitleTracks.first(where: { $0.id == selectedSubtitleTrackID })?.codec
        diagnosticsLogger.logSubtitleSelection(itemID: itemID, engine: engine, trackID: selectedSubtitleTrackID, codec: codec)
    }
}
