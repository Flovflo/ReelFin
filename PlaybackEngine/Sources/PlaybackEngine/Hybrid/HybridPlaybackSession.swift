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
    private let diagnosticsLogger = PlaybackDiagnosticsLogger()
    private let metricsCollector = StartupMetricsCollector()

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
    private var currentMediaCharacteristics: MediaCharacteristics?
    private var startupWatchdogTask: Task<Void, Never>?

    /// Maximum native startup time before falling back to VLC (seconds).
    private let nativeStartupTimeoutSeconds: TimeInterval = 15

    /// Maximum fallback attempts.
    private let maxFallbackAttempts = 1

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
    }

    // MARK: - Public API

    /// Load and start playback for a media item.
    /// This is the main entry point, equivalent to PlaybackSessionController.load().
    public func load(item: MediaItem, autoPlay: Bool = true) async throws {
        // Reset state
        currentItemID = item.id
        currentItem = item
        fallbackAttempted = false
        playbackErrorMessage = nil
        playbackState = .preparing
        startupWatchdogTask?.cancel()
        metricsCollector.reset()
        metricsCollector.markTap()

        // Step 1: Fetch playback sources and analyze capabilities
        let sources: [MediaSource]
        do {
            sources = try await apiClient.fetchPlaybackSources(itemID: item.id)
        } catch {
            playbackErrorMessage = error.localizedDescription
            playbackState = .failed
            throw error
        }

        guard let bestSource = sources.first else {
            let msg = "No playback source available."
            playbackErrorMessage = msg
            playbackState = .failed
            throw AppError.network(msg)
        }

        // Step 2: Capability analysis
        let media = MediaCharacteristics.from(source: bestSource)
        currentMediaCharacteristics = media
        let decision = capabilityEngine.evaluate(media)
        engineDecision = decision

        // Step 3: Determine engine to use
        let engineToUse = resolveEngine(from: decision)
        metricsCollector.markDecision(
            engine: engineToUse,
            reason: decision.recommendation.rawValue
        )

        diagnosticsLogger.logDecision(
            itemID: item.id,
            decision: decision,
            media: media,
            selectedEngine: engineToUse
        )

        // Log HDR decision
        if decision.hdrExpectation != .sdr {
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

        // Step 4: Start playback with the chosen engine
        do {
            switch engineToUse {
            case .native:
                try await startNativePlayback(item: item, autoPlay: autoPlay)
            case .vlc:
                try await startVLCPlayback(item: item, source: bestSource, autoPlay: autoPlay)
            }
        } catch {
            // If native failed and fallback is allowed, try VLC
            if engineToUse == .native && !fallbackAttempted && shouldAttemptFallback(decision: decision) {
                fallbackAttempted = true
                metricsCollector.markFallback(reason: error.localizedDescription)
                diagnosticsLogger.logFallback(
                    from: .native,
                    to: .vlc,
                    reason: error.localizedDescription,
                    itemID: item.id
                )

                do {
                    try await startVLCPlayback(item: item, source: bestSource, autoPlay: autoPlay)
                    return
                } catch {
                    playbackErrorMessage = error.localizedDescription
                    playbackState = .failed
                    throw error
                }
            }

            playbackErrorMessage = error.localizedDescription
            playbackState = .failed
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
    }

    public func pause() {
        if let controller = nativeSessionController {
            controller.pause()
        } else {
            activeEngine?.pause()
        }
        isPlaying = false
    }

    public func seek(to seconds: TimeInterval) async {
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
        playbackState = .idle
        isPlaying = false
    }

    public func selectAudioTrack(id: String) {
        if let controller = nativeSessionController {
            controller.selectAudioTrack(id: id)
        } else {
            activeEngine?.selectAudioTrack(id: id)
        }
        selectedAudioTrackID = id
    }

    public func selectSubtitleTrack(id: String?) {
        if let controller = nativeSessionController {
            controller.selectSubtitleTrack(id: id)
        } else {
            activeEngine?.selectSubtitleTrack(id: id)
        }
        selectedSubtitleTrackID = id
    }

    // MARK: - Convenience Accessors

    /// The AVPlayer for native playback (backward compatible with existing PlayerView).
    public var player: AVPlayer {
        nativePlayer ?? AVPlayer() // Return empty player as safety fallback
    }

    // MARK: - Engine Resolution

    private func resolveEngine(from decision: EngineCapabilityDecision) -> PlaybackEngineType {
        switch decision.recommendation {
        case .nativePreferred:
            return .native
        case .nativeAllowedButRisky:
            return .native
        case .nativeThenFallbackIfStartupFails:
            return .native
        case .vlcRequired:
            return isVLCAvailable ? .vlc : .native // Graceful degradation if VLC not linked
        case .serverTranscodePreferred:
            return .native // Server transcode produces Apple-friendly output
        case .unsupported:
            return .native // Let it fail with a clear error
        }
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

        switch decision.recommendation {
        case .nativeThenFallbackIfStartupFails, .nativeAllowedButRisky:
            return true
        case .nativePreferred:
            // Even for nativePreferred, allow fallback if startup actually fails
            return true
        default:
            return false
        }
    }

    // MARK: - Native Playback

    private func startNativePlayback(item: MediaItem, autoPlay: Bool) async throws {
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

        diagnosticsLogger.logEngineStartup(engine: .native, url: item.id, itemID: item.id)

        try await controller.load(item: item, autoPlay: autoPlay)

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

    private func startVLCPlayback(item: MediaItem, source: MediaSource, autoPlay: Bool) async throws {
        guard let url = source.directPlayURL ?? source.directStreamURL ?? source.transcodeURL else {
            throw AppError.network("No playable URL for VLC engine.")
        }

        let engine = VLCPlaybackEngine()
        self.vlcEngine = engine
        self.activeEngine = engine
        self.activeEngineType = .vlc
        self.nativeSessionController = nil
        metricsCollector.markPlayerSetup()

        // Wire callbacks
        engine.onStateChange = { [weak self] state in
            self?.playbackState = state
        }
        engine.onTimeUpdate = { [weak self] time in
            self?.currentTime = time
        }
        engine.onPlaybackEnded = { [weak self] in
            self?.isPlaying = false
            self?.playbackState = .ended
        }
        engine.onError = { [weak self] message in
            self?.playbackErrorMessage = message
        }

        diagnosticsLogger.logEngineStartup(engine: .vlc, url: url.absoluteString, itemID: item.id)

        try await engine.prepare(url: url, headers: source.requiredHTTPHeaders)

        // Map Jellyfin tracks (richer metadata) + engine tracks
        syncVLCState()

        if autoPlay {
            engine.play()
            isPlaying = true
            playbackState = .playing
        }

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
        }

        // Map native controller's effective state
        if controller.isPlaying {
            playbackState = .playing
        }
    }

    private func syncVLCState() {
        guard let engine = vlcEngine, let item = currentItem else { return }

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
}
