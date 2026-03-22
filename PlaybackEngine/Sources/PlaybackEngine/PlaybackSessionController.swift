import AVFoundation
import CoreMedia
import Foundation
import Observation
import Shared
import UIKit
import CoreVideo

public struct PlaybackPerformanceMetrics: Sendable {
    public var timeToFirstFrameMs: Double?
    public var stallCount: Int
    public var droppedFrames: Int

    public init(timeToFirstFrameMs: Double? = nil, stallCount: Int = 0, droppedFrames: Int = 0) {
        self.timeToFirstFrameMs = timeToFirstFrameMs
        self.stallCount = stallCount
        self.droppedFrames = droppedFrames
    }
}

public struct PlaybackProofSnapshot: Sendable, Equatable {
    public var decodedResolution: String
    public var codecFourCC: String
    public var bitDepth: Int?
    public var hdrTransfer: String
    public var dolbyVisionActive: Bool
    public var playbackMethod: String
    public var variantResolution: String?
    public var variantBandwidth: Int?
    public var variantCodecs: String?
    // Rich debug info
    public var transcodeProfile: String?
    public var sourceBitrate: Int?
    public var sourceContainer: String?
    public var sourceVideoCodec: String?
    public var sourceAudioCodec: String?
    public var dvProfile: Int?
    public var dvLevel: Int?
    public var videoRangeType: String?
    public var observedBitrate: Int?
    public var sourceHDRFlag: Bool
    public var sourceDolbyVisionProfile: Int?
    public var sourceColorPrimaries: String?
    public var sourceColorTransfer: String?
    public var sourceAudioTrackSelected: String?
    public var deviceHDRCapable: Bool
    public var deviceDolbyVisionCapable: Bool
    public var nativePlayerPathActive: Bool
    public var strictQualityModeEnabled: Bool
    public var selectedMasterPlaylistURL: String?
    public var selectedVariantURL: String?
    public var selectedVideoRange: String?
    public var selectedSupplementalCodecs: String?
    public var selectedAudioCodec: String?
    public var selectedTransport: String?
    public var initHasHvcC: Bool
    public var initHasDvcC: Bool
    public var initHasDvvC: Bool
    public var inferredEffectiveVideoMode: String
    public var playerItemStatus: String
    public var fallbackOccurred: Bool
    public var fallbackReason: String?
    public var failureDomain: String?
    public var failureCode: Int?
    public var failureReason: String?
    public var recoverySuggestion: String?

    public init(
        decodedResolution: String = "unknown",
        codecFourCC: String = "unknown",
        bitDepth: Int? = nil,
        hdrTransfer: String = "Unknown",
        dolbyVisionActive: Bool = false,
        playbackMethod: String = "Unknown",
        variantResolution: String? = nil,
        variantBandwidth: Int? = nil,
        variantCodecs: String? = nil,
        transcodeProfile: String? = nil,
        sourceBitrate: Int? = nil,
        sourceContainer: String? = nil,
        sourceVideoCodec: String? = nil,
        sourceAudioCodec: String? = nil,
        dvProfile: Int? = nil,
        dvLevel: Int? = nil,
        videoRangeType: String? = nil,
        observedBitrate: Int? = nil,
        sourceHDRFlag: Bool = false,
        sourceDolbyVisionProfile: Int? = nil,
        sourceColorPrimaries: String? = nil,
        sourceColorTransfer: String? = nil,
        sourceAudioTrackSelected: String? = nil,
        deviceHDRCapable: Bool = false,
        deviceDolbyVisionCapable: Bool = false,
        nativePlayerPathActive: Bool = false,
        strictQualityModeEnabled: Bool = false,
        selectedMasterPlaylistURL: String? = nil,
        selectedVariantURL: String? = nil,
        selectedVideoRange: String? = nil,
        selectedSupplementalCodecs: String? = nil,
        selectedAudioCodec: String? = nil,
        selectedTransport: String? = nil,
        initHasHvcC: Bool = false,
        initHasDvcC: Bool = false,
        initHasDvvC: Bool = false,
        inferredEffectiveVideoMode: String = EffectivePlaybackVideoMode.unknown.rawValue,
        playerItemStatus: String = "unknown",
        fallbackOccurred: Bool = false,
        fallbackReason: String? = nil,
        failureDomain: String? = nil,
        failureCode: Int? = nil,
        failureReason: String? = nil,
        recoverySuggestion: String? = nil
    ) {
        self.decodedResolution = decodedResolution
        self.codecFourCC = codecFourCC
        self.bitDepth = bitDepth
        self.hdrTransfer = hdrTransfer
        self.dolbyVisionActive = dolbyVisionActive
        self.playbackMethod = playbackMethod
        self.variantResolution = variantResolution
        self.variantBandwidth = variantBandwidth
        self.variantCodecs = variantCodecs
        self.transcodeProfile = transcodeProfile
        self.sourceBitrate = sourceBitrate
        self.sourceContainer = sourceContainer
        self.sourceVideoCodec = sourceVideoCodec
        self.sourceAudioCodec = sourceAudioCodec
        self.dvProfile = dvProfile
        self.dvLevel = dvLevel
        self.videoRangeType = videoRangeType
        self.observedBitrate = observedBitrate
        self.sourceHDRFlag = sourceHDRFlag
        self.sourceDolbyVisionProfile = sourceDolbyVisionProfile
        self.sourceColorPrimaries = sourceColorPrimaries
        self.sourceColorTransfer = sourceColorTransfer
        self.sourceAudioTrackSelected = sourceAudioTrackSelected
        self.deviceHDRCapable = deviceHDRCapable
        self.deviceDolbyVisionCapable = deviceDolbyVisionCapable
        self.nativePlayerPathActive = nativePlayerPathActive
        self.strictQualityModeEnabled = strictQualityModeEnabled
        self.selectedMasterPlaylistURL = selectedMasterPlaylistURL
        self.selectedVariantURL = selectedVariantURL
        self.selectedVideoRange = selectedVideoRange
        self.selectedSupplementalCodecs = selectedSupplementalCodecs
        self.selectedAudioCodec = selectedAudioCodec
        self.selectedTransport = selectedTransport
        self.initHasHvcC = initHasHvcC
        self.initHasDvcC = initHasDvcC
        self.initHasDvvC = initHasDvvC
        self.inferredEffectiveVideoMode = inferredEffectiveVideoMode
        self.playerItemStatus = playerItemStatus
        self.fallbackOccurred = fallbackOccurred
        self.fallbackReason = fallbackReason
        self.failureDomain = failureDomain
        self.failureCode = failureCode
        self.failureReason = failureReason
        self.recoverySuggestion = recoverySuggestion
    }
}

@Observable
@MainActor
public final class PlaybackSessionController {
    public private(set) var isPlaying = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var availableAudioTracks: [MediaTrack] = []
    public private(set) var availableSubtitleTracks: [MediaTrack] = []
    public private(set) var selectedAudioTrackID: String?
    public private(set) var selectedSubtitleTrackID: String?
    public private(set) var routeDescription: String = ""
    public private(set) var debugInfo: PlaybackDebugInfo?
    public private(set) var currentPlaybackPlan: PlaybackPlan?
    public private(set) var runtimeHDRMode: HDRPlaybackMode = .unknown
    public private(set) var metrics = PlaybackPerformanceMetrics()
    public private(set) var isExternalPlaybackActive = false
    public private(set) var playbackErrorMessage: String?
    public private(set) var playbackProof = PlaybackProofSnapshot()

    public let player = AVPlayer()

    private let apiClient: any JellyfinAPIClientProtocol & Sendable
    private let repository: MetadataRepositoryProtocol
    private let coordinator: PlaybackCoordinator
    private let warmupManager: (any PlaybackWarmupManaging)?
    private let playbackDiagnostics = PlaybackDiagnostics()
    private let fallbackPlanner = FallbackPlanner()

    private var periodicObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var accessLogObserver: NSObjectProtocol?

    private var playerItemStatusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var externalPlaybackObserver: NSKeyValueObservation?
    private var lifecycleObservers: [NSObjectProtocol] = []

    private var currentItemID: String?
    private var currentItemHasDolbyVision = false
    private var currentSource: MediaSource?
    private var playMethodForReporting = "Transcode"
    private var didResumeAfterForeground = false
    private var hasMarkedFirstFrame = false
    private var hasDecodedVideoFrame = false
    private var pendingResumeSeconds: Double?
    private var playbackStrategy: PlaybackStrategy = .bestQualityFastest
    private var playbackPolicy: PlaybackPolicy = .auto
    private var allowSDRFallback = true
    private var preferAudioTranscodeOnly = true
    /// Mirrors ServerConfiguration.preferredAudioLanguage for the current session.
    private var preferredAudioLanguage: String?
    /// Mirrors ServerConfiguration.preferredSubtitleLanguage for the current session.
    private var preferredSubtitleLanguage: String?
    private var playbackQualityMode: PlaybackQualityMode = .compatibility
    private var activeTranscodeProfile: TranscodeURLProfile = .serverDefault
    private var nativeBridgeSession: NativeBridgeSession?
    private var syntheticHLSSession: SyntheticHLSSession?
    private var localHLSServer: LocalHLSServer?
    private var recoveryAttemptCount = 0
    private var isRecoveryInProgress = false
    private var attemptedPlaybackTriples = Set<String>()
    private var selectedVariantInfo: HLSVariantInfo?
    private var selectedMasterPlaylistURL: URL?
    private var selectedVariantPlaylistInspection: VariantPlaylistInspection?
    private var selectedInitSegmentInspection: InitSegmentInspection?
    private var fallbackOccurred = false
    private var fallbackReason: String?
    private var lastPlayerItemStatus = "unknown"
    private var lastFailureDomain: String?
    private var lastFailureCode: Int?
    private var lastFailureReason: String?
    private var lastRecoverySuggestion: String?
    private let audioSelector = AudioCompatibilitySelector()
    private let subtitlePolicy = SubtitleCompatibilityPolicy()
    private let assetURLValidator = AssetURLValidator()
    private var startDate = Date()
    private var preferredProfilesByItemID: [String: TranscodeURLProfile] = [:]
    private var lastPreparedSelection: PlaybackAssetSelection?

    private var readyInterval: SignpostInterval?
    private var firstFrameInterval: SignpostInterval?
    private var activeStallInterval: SignpostInterval?
    private var ttffPipelineInterval: SignpostInterval?
    private var ttffInfoInterval: SignpostInterval?
    private var ttffResolveInterval: SignpostInterval?
    private var ttffFirstBytesInterval: SignpostInterval?
    private var startupWatchdogTask: Task<Void, Never>?
    private var decodedFrameWatchdogTask: Task<Void, Never>?
    private var videoOutputPollTask: Task<Void, Never>?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var ttffTuning: TTFFTuningConfiguration = .default
    private var ttffInfoMs: Double = 0
    private var ttffResolveMs: Double = 0
    private var ttffFirstBytesMs: Double = 0
    private var ttffReadyMs: Double = 0
    private static let preferredProfileStorageKey = "reelfin.playback.preferredTranscodeProfileByItemID.v2"
    private static let localhostHLSMaxStartupAttempts = 2

    private struct LocalHLSPreflightResult: Sendable {
        let masterStatus: Int
        let masterBytes: Int
        let mediaStatus: Int
        let mediaBytes: Int
        let initStatus: Int
        let initBytes: Int
        let firstSegmentStatus: Int
        let firstSegmentBytes: Int
        let firstSegmentDurationSeconds: Double
    }

    private struct LocalHLSStartupSummary: Sendable {
        let host: String
        let port: Int
        let masterURL: URL
        let initBytes: Int
        let firstSegmentBytes: Int
        let firstSegmentDurationSeconds: Double
        let keyframePresent: Bool?
    }

    private var maxRecoveryAttempts: Int {
        switch playbackPolicy {
        case .auto:
            return 2 // total attempts: 3 (initial + 2 recoveries)
        case .originalFirst, .originalLockHDRDV:
            return 1 // total attempts: 2 (initial + 1 recovery)
        }
    }

    private var strictQualityIsActive: Bool {
        playbackQualityMode == .strictQuality
    }

    private var localHLSStartupSummary: LocalHLSStartupSummary?

    public init(
        apiClient: any JellyfinAPIClientProtocol & Sendable,
        repository: MetadataRepositoryProtocol,
        warmupManager: (any PlaybackWarmupManaging)? = nil,
        decisionEngine: PlaybackDecisionEngine = PlaybackDecisionEngine()
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.coordinator = PlaybackCoordinator(apiClient: apiClient, decisionEngine: decisionEngine)
        self.warmupManager = warmupManager
        self.preferredProfilesByItemID = Self.loadStoredPreferredProfiles()
        configurePlayerBase()
        setupLifecycleObservers()
    }

    @MainActor
    deinit {
        tearDownCurrentItemObservers()

        lifecycleObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        startupWatchdogTask?.cancel()
        decodedFrameWatchdogTask?.cancel()
        videoOutputPollTask?.cancel()
        localHLSServer?.stop(reason: "controller_deinit")
    }

    public func load(item: MediaItem, autoPlay: Bool = true) async throws {
        currentItemID = item.id
        currentItemHasDolbyVision = item.hasDolbyVision
        startDate = Date()
        hasMarkedFirstFrame = false
        hasDecodedVideoFrame = false
        pendingResumeSeconds = nil
        recoveryAttemptCount = 0
        metrics = PlaybackPerformanceMetrics()
        playbackErrorMessage = nil
        currentPlaybackPlan = nil
        startupWatchdogTask?.cancel()
        decodedFrameWatchdogTask?.cancel()
        videoOutputPollTask?.cancel()
        attemptedPlaybackTriples.removeAll()
        selectedVariantInfo = nil
        selectedMasterPlaylistURL = nil
        selectedVariantPlaylistInspection = nil
        selectedInitSegmentInspection = nil
        fallbackOccurred = false
        fallbackReason = nil
        lastPlayerItemStatus = "unknown"
        lastFailureDomain = nil
        lastFailureCode = nil
        lastFailureReason = nil
        lastRecoverySuggestion = nil
        localHLSStartupSummary = nil
        let playbackConfig = await currentPlaybackConfiguration()
        playbackPolicy = playbackConfig.playbackPolicy
        allowSDRFallback = playbackConfig.allowSDRFallback
        preferAudioTranscodeOnly = playbackConfig.preferAudioTranscodeOnly
        preferredAudioLanguage = playbackConfig.preferredAudioLanguage
        preferredSubtitleLanguage = playbackConfig.preferredSubtitleLanguage
        if playbackPolicy == .originalLockHDRDV {
            playbackQualityMode = .strictQuality
            allowSDRFallback = false
        } else {
            playbackQualityMode = allowSDRFallback ? .compatibility : .strictQuality
        }
        activeTranscodeProfile = initialProfileForItem(itemID: item.id, itemHasDolbyVision: item.hasDolbyVision)
        playbackStrategy = await currentPlaybackStrategy()
        // Enable strict DV packaging only when user explicitly locks playback to HDR/DV.
        // In auto mode we keep safer HDR10 fallback behavior for Profile 8 sources.
        let shouldForceStrictDV =
            item.hasDolbyVision &&
            playbackQualityMode == .strictQuality
        DolbyVisionGate.setRuntimeDVPackagingEnabled(shouldForceStrictDV ? true : nil)

        // For DV titles, always retry NativeBridge first instead of staying pinned
        // in the temporary failure cache from a previous attempt.
        if item.hasDolbyVision {
            NativeBridgeFailureCache.clearFailure(itemID: item.id)
        }

        // Start the overall TTFF pipeline signpost
        ttffPipelineInterval = SignpostInterval(signposter: Signpost.ttffPipeline, name: "ttff_total")
        ttffInfoInterval = SignpostInterval(signposter: Signpost.ttffPipeline, name: "ttff_playback_info")
        let infoStartDate = Date()

        do {
            let warmedSelection = await warmupManager?.selection(for: item.id)
            let warmedSelectionStart = Date()
            var selection: PlaybackAssetSelection

            if let warmedSelection {
                selection = warmedSelection
                ttffInfoInterval?.end(name: "ttff_playback_info", message: "warm_cache_hit")
                ttffInfoInterval = nil
                ttffInfoMs = Date().timeIntervalSince(warmedSelectionStart) * 1000
            } else {
                // Always resolve with balanced mode so DirectStreamUrl is available for NativeBridge.
                // Performance mode disables transcoding — the coordinator handles the fallback internally.
                selection = try await coordinator.resolvePlayback(
                    itemID: item.id,
                    mode: .balanced,
                    allowTranscodingFallbackInPerformance: !usesDirectRemuxOnly,
                    transcodeProfile: activeTranscodeProfile
                )

                // Mark PlaybackInfo phase complete
                ttffInfoInterval?.end(name: "ttff_playback_info", message: "info_received")
                ttffInfoInterval = nil
                ttffInfoMs = Date().timeIntervalSince(infoStartDate) * 1000
            }

            ttffResolveInterval = SignpostInterval(signposter: Signpost.ttffPipeline, name: "ttff_url_resolution")
            let resolveStartDate = Date()

            selection = try await pinPreferredVariantIfNeeded(
                selection: selection,
                itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                    itemPrefersDolbyVision: item.hasDolbyVision,
                    source: selection.source
                )
            )
            selection = try await stabilizeInitialSelectionIfNeeded(
                itemID: item.id,
                selection: selection,
                itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                    itemPrefersDolbyVision: item.hasDolbyVision,
                    source: selection.source
                )
            )
            selection = try await upgradeRiskyInitialSelectionIfNeeded(
                itemID: item.id,
                selection: selection,
                itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                    itemPrefersDolbyVision: item.hasDolbyVision,
                    source: selection.source
                )
            )
            activeTranscodeProfile = inferredTranscodeProfile(from: selection.assetURL, fallback: activeTranscodeProfile)
            if !registerAttempt(selection: selection, profile: activeTranscodeProfile) {
                throw AppError.network("Playback attempt already tried with the same profile and URL.")
            }

            if case let .nativeBridge(plan) = selection.decision.route {
                do {
                    if Self.prefersLocalSyntheticHLS {
                        let localURL = try await prepareSyntheticLocalHLS(plan: plan)
                        selection.assetURL = localURL
                        selection.headers = [:]
                        self.nativeBridgeSession = nil
                    } else {
                        let session = NativeBridgeSession(plan: plan, token: await apiClient.currentSession()?.token)
                        try await session.prepare()
                        self.nativeBridgeSession = session
                        self.syntheticHLSSession = nil
                        self.localHLSServer?.stop(reason: "switch_to_resource_loader")
                        self.localHLSServer = nil
                        self.localHLSStartupSummary = nil
                    }
                } catch {
                    // NativeBridge failed — fall back to transcode instead of failing entirely
                    NativeBridgeFailureCache.recordFailure(itemID: item.id)
                    AppLog.playback.warning("NativeBridge prepare failed: \(error.localizedDescription, privacy: .public). Falling back to transcode.")
                    activeTranscodeProfile = isMKVHEVCSource(selection.source) ? .appleOptimizedHEVC : .serverDefault
                    selection = try await coordinator.resolvePlayback(
                        itemID: item.id,
                        mode: .balanced,
                        allowTranscodingFallbackInPerformance: true,
                        transcodeProfile: activeTranscodeProfile
                    )
                    selection = try await pinPreferredVariantIfNeeded(
                        selection: selection,
                        itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                            itemPrefersDolbyVision: item.hasDolbyVision,
                            source: selection.source
                        )
                    )
                    selection = try await stabilizeInitialSelectionIfNeeded(
                        itemID: item.id,
                        selection: selection,
                        itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                            itemPrefersDolbyVision: item.hasDolbyVision,
                            source: selection.source
                        )
                    )
                    selection = try await upgradeRiskyInitialSelectionIfNeeded(
                        itemID: item.id,
                        selection: selection,
                        itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                            itemPrefersDolbyVision: item.hasDolbyVision,
                            source: selection.source
                        )
                    )
                    activeTranscodeProfile = inferredTranscodeProfile(from: selection.assetURL, fallback: activeTranscodeProfile)
                    _ = registerAttempt(selection: selection, profile: activeTranscodeProfile)
                    await self.nativeBridgeSession?.invalidate()
                    self.nativeBridgeSession = nil
                    self.syntheticHLSSession = nil
                    self.localHLSServer?.stop(reason: "nativebridge_prepare_failed")
                    self.localHLSServer = nil
                    self.localHLSStartupSummary = nil
                }
            } else {
                await self.nativeBridgeSession?.invalidate()
                self.nativeBridgeSession = nil
                self.syntheticHLSSession = nil
                self.localHLSServer?.stop(reason: "non_nativebridge_route")
                self.localHLSServer = nil
                self.localHLSStartupSummary = nil
            }

            prepareAndLoadSelection(selection, resumeSeconds: nil)

            // Mark URL resolution phase complete
            ttffResolveInterval?.end(name: "ttff_url_resolution", message: "url_resolved")
            ttffResolveInterval = nil
            ttffResolveMs = Date().timeIntervalSince(resolveStartDate) * 1000

            // Retrieve TTFF tuning from coordinator
            ttffTuning = coordinator.ttffTuning

            if let seconds = try await resumeSeconds(for: item), seconds > 0 {
                if shouldDeferResumeSeek(route: selection.decision.route, seconds: seconds) {
                    pendingResumeSeconds = seconds
                } else {
                    let seekTime = CMTime(seconds: seconds, preferredTimescale: 600)
                    let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
                    _ = await player.seek(to: seekTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
                }
            }

            if autoPlay {
                play()
                scheduleDecodedFrameWatchdog()
            }
            scheduleStartupWatchdog()
        } catch {
            if usesDirectRemuxOnly {
                throw AppError.network(
                    "Direct/Remux only mode is enabled. This file requires transcoding on iOS. Disable the mode to play it."
                )
            }
            throw error
        }
    }

    private func resumeSeconds(for item: MediaItem) async throws -> Double? {
        if let progress = try await repository.fetchPlaybackProgress(itemID: item.id),
           progress.positionTicks > 0 {
            return Double(progress.positionTicks) / 10_000_000
        }

        if let itemTicks = item.playbackPositionTicks, itemTicks > 0 {
            return Double(itemTicks) / 10_000_000
        }

        return nil
    }

    private var usesDirectRemuxOnly: Bool {
        playbackStrategy == .directRemuxOnly
    }

    private static var prefersLocalSyntheticHLS: Bool {
        if let env = ProcessInfo.processInfo.environment["REELFIN_LOCAL_HLS_ENABLED"] {
            let normalized = env.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "1" || normalized == "true" || normalized == "yes"
        }
        if let persisted = UserDefaults.standard.object(forKey: "reelfin.playback.localhls.enabled") as? Bool {
            return persisted
        }
        return true
    }

    private static var forceVideoOnlyStartupHLS: Bool {
        if let env = ProcessInfo.processInfo.environment["REELFIN_LOCAL_HLS_VIDEO_ONLY_STARTUP"] {
            let normalized = env.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "1" || normalized == "true" || normalized == "yes"
        }
        if let persisted = UserDefaults.standard.object(forKey: "reelfin.playback.localhls.videoOnlyStartup") as? Bool {
            return persisted
        }
        return false
    }

    private func prepareSyntheticLocalHLS(plan: NativeBridgePlan) async throws -> URL {
        var headers: [String: String] = [:]
        if let token = await apiClient.currentSession()?.token {
            headers["Authorization"] = "MediaBrowser Token=\"\(token)\""
            headers["X-Emby-Token"] = token
        }
        let startupPlan = makeStartupPlan(from: plan)
        var lastError: Error?
        for attempt in 1...Self.localhostHLSMaxStartupAttempts {
            var server: LocalHLSServer?
            do {
                // Clean-room attempt: build fresh reader/demuxer/repackager/session each time.
                let readerConfig = HTTPRangeReader.Configuration(
                    chunkSize: 64 * 1024,
                    maxCacheSize: 24 * 1024 * 1024,
                    maxRetries: 4,
                    baseRetryDelayMs: 150,
                    timeoutInterval: 20,
                    maxConcurrentRequests: 2,
                    readAheadChunks: 0
                )
                let reader = HTTPRangeReader(url: startupPlan.sourceURL, headers: headers, config: readerConfig)
                let demuxer = MatroskaDemuxer(reader: reader, plan: startupPlan)
                let diagnostics = NativeBridgeDiagnosticsCollector(config: startupPlan.diagnostics)
                let repackager = FMP4Repackager(plan: startupPlan, diagnostics: diagnostics)
                let session = SyntheticHLSSession(plan: startupPlan, demuxer: demuxer, repackager: repackager)
                try await session.prepare()

                let localServer = LocalHLSServer(session: session)
                server = localServer

                let baseURL = try localServer.start()
                guard let port = baseURL.port, port > 0 else {
                    throw AppError.network("Local HLS server returned invalid port: \(baseURL.absoluteString)")
                }

                let masterURL = baseURL.appendingPathComponent("master.m3u8")
                localServer.setStartupPreflightSnapshotMode(true)
                defer { localServer.setStartupPreflightSnapshotMode(false) }
                let preflight = try await preflightSyntheticLocalHLS(masterURL: masterURL)

                localHLSServer?.stop(reason: "replace_after_successful_start")
                localHLSServer = localServer
                syntheticHLSSession = session
                localHLSStartupSummary = LocalHLSStartupSummary(
                    host: "127.0.0.1",
                    port: port,
                    masterURL: masterURL,
                    initBytes: preflight.initBytes,
                    firstSegmentBytes: preflight.firstSegmentBytes,
                    firstSegmentDurationSeconds: preflight.firstSegmentDurationSeconds,
                    keyframePresent: nil
                )

                AppLog.playback.info("Using synthetic local HLS delivery \(masterURL.absoluteString, privacy: .public)")
                AppLog.nativeBridge.notice(
                    "[NB-DIAG] hls.startup.summary — lane=nativeBridge host=127.0.0.1 port=\(port, privacy: .public) master=\(masterURL.absoluteString, privacy: .public) initBytes=\(preflight.initBytes, privacy: .public) firstSegBytes=\(preflight.firstSegmentBytes, privacy: .public) firstSegDuration=\(preflight.firstSegmentDurationSeconds, format: .fixed(precision: 3)) keyframe=unknown preflight=pass avplayer=not_created"
                )
                return masterURL
            } catch {
                lastError = error
                server?.stop(reason: "startup_attempt_\(attempt)_failed")
                syntheticHLSSession = nil
                localHLSStartupSummary = nil
                AppLog.nativeBridge.error(
                    "[NB-DIAG] hls.server.retry — attempt=\(attempt, privacy: .public) reason=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        localHLSServer?.stop(reason: "all_startup_attempts_failed")
        localHLSServer = nil
        syntheticHLSSession = nil
        localHLSStartupSummary = nil
        throw lastError ?? AppError.network("Local synthetic HLS startup failed.")
    }

    private func makeStartupPlan(from plan: NativeBridgePlan) -> NativeBridgePlan {
        guard Self.forceVideoOnlyStartupHLS, plan.audioTrack != nil else {
            return plan
        }
        AppLog.nativeBridge.notice(
            "[NB-DIAG] hls.startup.video-only — enabled=true reason=debug_switch"
        )
        return NativeBridgePlan(
            itemID: plan.itemID,
            sourceID: plan.sourceID,
            sourceURL: plan.sourceURL,
            videoTrack: plan.videoTrack,
            audioTrack: nil,
            videoAction: plan.videoAction,
            audioAction: plan.audioAction,
            subtitleTracks: plan.subtitleTracks,
            videoRangeType: plan.videoRangeType,
            dvProfile: plan.dvProfile,
            dvLevel: plan.dvLevel,
            dvBlSignalCompatibilityId: plan.dvBlSignalCompatibilityId,
            hdr10PlusPresentFlag: plan.hdr10PlusPresentFlag,
            diagnostics: plan.diagnostics,
            whyChosen: "\(plan.whyChosen) [startup_video_only]"
        )
    }

    private func preflightSyntheticLocalHLS(masterURL: URL) async throws -> LocalHLSPreflightResult {
        guard let port = masterURL.port, port > 0 else {
            throw AppError.network("Invalid local HLS URL (missing/non-positive port): \(masterURL.absoluteString)")
        }

        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.master.start — url=\(masterURL.absoluteString, privacy: .public)")
        let masterProbe = try await fetchHTTPProbe(url: masterURL)
        guard masterProbe.statusCode == 200 else {
            throw AppError.network("Local HLS master preflight failed with status \(masterProbe.statusCode).")
        }
        guard let masterManifest = String(data: masterProbe.data, encoding: .utf8), masterManifest.contains("#EXTM3U") else {
            throw AppError.network("Local HLS master preflight returned invalid manifest.")
        }
        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.master.ok — status=\(masterProbe.statusCode, privacy: .public) bytes=\(masterProbe.data.count, privacy: .public)")
        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.master.content\n\(masterManifest, privacy: .public)")

        guard
            let mediaLine = firstMediaLine(in: masterManifest),
            let mediaURL = resolveSegmentURL(firstSegmentLine: mediaLine, masterURL: masterURL)
        else {
            throw AppError.network("Local HLS master playlist has no child media playlist.")
        }

        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.media.start — url=\(mediaURL.absoluteString, privacy: .public)")
        let mediaProbe = try await fetchHTTPProbe(url: mediaURL)
        guard mediaProbe.statusCode == 200 else {
            throw AppError.network("Local HLS media preflight failed with status \(mediaProbe.statusCode).")
        }
        guard let mediaManifest = String(data: mediaProbe.data, encoding: .utf8), mediaManifest.contains("#EXTM3U") else {
            throw AppError.network("Local HLS media preflight returned invalid playlist.")
        }
        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.media.ok — status=\(mediaProbe.statusCode, privacy: .public) bytes=\(mediaProbe.data.count, privacy: .public)")
        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.media.content\n\(mediaManifest, privacy: .public)")
        selectedMasterPlaylistURL = masterURL
        selectedVariantPlaylistInspection = StreamVariantInspector.inspectVariantPlaylist(
            manifest: mediaManifest,
            variantURL: mediaURL
        )

        let mediaLines = mediaManifest.split(whereSeparator: \.isNewline).map(String.init)
        guard
            let mapLine = mediaLines.first(where: { $0.hasPrefix("#EXT-X-MAP:") }),
            let initURI = extractQuotedAttribute(named: "URI", fromTagLine: mapLine),
            let initURL = resolveSegmentURL(firstSegmentLine: initURI, masterURL: mediaURL)
        else {
            throw AppError.network("Local HLS media playlist is missing #EXT-X-MAP URI.")
        }

        let firstSegmentDuration = extractFirstSegmentDurationSeconds(fromMediaPlaylist: mediaManifest)
        guard
            let firstSegmentLine = firstMediaLine(in: mediaManifest),
            let firstSegmentURL = resolveSegmentURL(firstSegmentLine: firstSegmentLine, masterURL: mediaURL)
        else {
            throw AppError.network("Local HLS media playlist has no segment URI.")
        }

        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.init.start — url=\(initURL.absoluteString, privacy: .public)")
        let initProbe = try await fetchHTTPProbe(url: initURL)
        guard initProbe.statusCode == 200, !initProbe.data.isEmpty else {
            throw AppError.network("Local HLS init segment preflight failed (status=\(initProbe.statusCode), bytes=\(initProbe.data.count)).")
        }
        selectedInitSegmentInspection = InitSegmentInspector.inspect(initProbe.data)
        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.init.ok — status=\(initProbe.statusCode, privacy: .public) bytes=\(initProbe.data.count, privacy: .public)")
        if let initTree = try? BMFFInspector.inspect(initProbe.data) {
            AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.init.tree\n\(BMFFInspector.formatTree(initTree), privacy: .public)")
        }

        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.segment.start — url=\(firstSegmentURL.absoluteString, privacy: .public)")
        let firstSegmentProbe = try await fetchHTTPProbe(url: firstSegmentURL)
        guard firstSegmentProbe.statusCode == 200, !firstSegmentProbe.data.isEmpty else {
            throw AppError.network("Local HLS first segment preflight failed (status=\(firstSegmentProbe.statusCode), bytes=\(firstSegmentProbe.data.count)).")
        }
        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.segment.ok — status=\(firstSegmentProbe.statusCode, privacy: .public) bytes=\(firstSegmentProbe.data.count, privacy: .public)")
        if let fragmentTree = try? BMFFInspector.inspect(firstSegmentProbe.data) {
            AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.segment.tree\n\(BMFFInspector.formatTree(fragmentTree), privacy: .public)")
        }

        return LocalHLSPreflightResult(
            masterStatus: masterProbe.statusCode,
            masterBytes: masterProbe.data.count,
            mediaStatus: mediaProbe.statusCode,
            mediaBytes: mediaProbe.data.count,
            initStatus: initProbe.statusCode,
            initBytes: initProbe.data.count,
            firstSegmentStatus: firstSegmentProbe.statusCode,
            firstSegmentBytes: firstSegmentProbe.data.count,
            firstSegmentDurationSeconds: firstSegmentDuration
        )
    }

    private func fetchHTTPProbe(url: URL, timeout: TimeInterval = 8) async throws -> (statusCode: Int, data: Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.network("Local HLS preflight did not receive an HTTP response.")
        }
        return (http.statusCode, data)
    }

    private func extractQuotedAttribute(named name: String, fromTagLine line: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard
            let match = regex.firstMatch(in: line, options: [], range: range),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[valueRange])
    }

    private func extractFirstSegmentDurationSeconds(fromMediaPlaylist media: String) -> Double {
        for line in media.split(whereSeparator: \.isNewline).map(String.init) {
            guard line.hasPrefix("#EXTINF:") else { continue }
            let value = line
                .replacingOccurrences(of: "#EXTINF:", with: "")
                .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                .first
            if let value, let duration = Double(value.trimmingCharacters(in: .whitespaces)) {
                return duration
            }
        }
        return 0
    }

    private func currentPlaybackStrategy() async -> PlaybackStrategy {
        guard let configuration = await apiClient.currentConfiguration() else {
            return .bestQualityFastest
        }
        return configuration.playbackStrategy
    }

    private func prepareAndLoadSelection(_ selection: PlaybackAssetSelection, resumeSeconds: Double?) {
        lastPreparedSelection = selection
        startupWatchdogTask?.cancel()
        decodedFrameWatchdogTask?.cancel()
        videoOutputPollTask?.cancel()
        videoOutput = nil
        activeTranscodeProfile = inferredTranscodeProfile(from: selection.assetURL, fallback: activeTranscodeProfile)
        currentSource = selection.source
        // Keep runtime quality mode tied to explicit policy/user settings.
        debugInfo = selection.debugInfo
        currentPlaybackPlan = selection.playbackPlan ?? selection.decision.playbackPlan
        if let plan = currentPlaybackPlan {
            playbackDiagnostics.recordPlan(plan)
        }
        runtimeHDRMode = selection.debugInfo.hdrMode
        playMethodForReporting = selection.decision.playMethod
        let deviceCaps = DeviceCapabilityFingerprint.current()
        let routeIsNativeApple = selection.assetURL.pathExtension.lowercased() == "m3u8" || playMethodForReporting == "NativeBridge"
        playbackProof = PlaybackProofSnapshot(
            decodedResolution: "unknown",
            codecFourCC: "unknown",
            bitDepth: selection.source.videoBitDepth,
            hdrTransfer: "Unknown",
            dolbyVisionActive: false,
            playbackMethod: selection.decision.playMethod,
            variantResolution: selectedVariantInfo.map { "\($0.width)x\($0.height)" },
            variantBandwidth: selectedVariantInfo?.bandwidth,
            variantCodecs: selectedVariantInfo?.codecs,
            transcodeProfile: activeTranscodeProfile.rawValue,
            sourceBitrate: selection.source.bitrate,
            sourceContainer: selection.source.container,
            sourceVideoCodec: selection.source.videoCodec,
            sourceAudioCodec: selection.source.audioCodec,
            dvProfile: selection.source.dvProfile,
            dvLevel: selection.source.dvLevel,
            videoRangeType: selection.source.videoRangeType ?? selection.source.videoRange,
            sourceHDRFlag: selection.source.isLikelyHDRorDV,
            sourceDolbyVisionProfile: selection.source.dvProfile,
            sourceColorPrimaries: selection.source.colorPrimaries,
            sourceColorTransfer: selection.source.colorTransfer,
            sourceAudioTrackSelected: nil,
            deviceHDRCapable: deviceCaps.supportsHDR10,
            deviceDolbyVisionCapable: deviceCaps.supportsDolbyVision,
            nativePlayerPathActive: routeIsNativeApple,
            strictQualityModeEnabled: strictQualityIsActive,
            selectedMasterPlaylistURL: selectedMasterPlaylistURL?.absoluteString,
            selectedVariantURL: selectedVariantInfo?.resolvedURL.absoluteString,
            selectedVideoRange: selectedVariantInfo?.videoRange,
            selectedSupplementalCodecs: selectedVariantInfo?.supplementalCodecs,
            selectedAudioCodec: selection.source.audioCodec,
            selectedTransport: selectedVariantInfo.map { StreamVariantInspector.inferTransport(from: $0, playlist: selectedVariantPlaylistInspection) } ?? (isLocalSyntheticHLSURL(selection.assetURL) ? "fMP4" : nil),
            initHasHvcC: selectedInitSegmentInspection?.hasHvcC ?? false,
            initHasDvcC: selectedInitSegmentInspection?.hasDvcC ?? false,
            initHasDvvC: selectedInitSegmentInspection?.hasDvvC ?? false,
            inferredEffectiveVideoMode: selectedInitSegmentInspection?.inferredMode.rawValue ?? EffectivePlaybackVideoMode.unknown.rawValue,
            playerItemStatus: lastPlayerItemStatus,
            fallbackOccurred: fallbackOccurred,
            fallbackReason: fallbackReason,
            failureDomain: lastFailureDomain,
            failureCode: lastFailureCode,
            failureReason: lastFailureReason,
            recoverySuggestion: lastRecoverySuggestion
        )

        availableAudioTracks = selection.source.audioTracks
        availableSubtitleTracks = selection.source.subtitleTracks
        let audioSelection = audioSelector.selectPreferredAudioTrack(
            from: availableAudioTracks,
            fallbackCodec: selection.source.normalizedAudioCodec,
            nativePlayerPath: routeIsNativeApple,
            preferredLanguage: preferredAudioLanguage
        )
        let preferredAudioTrack = availableAudioTracks.first(where: { $0.index == audioSelection.selectedTrackIndex })
            ?? availableAudioTracks.first(where: { ($0.codec ?? "").lowercased() == audioSelection.selectedCodec })
            ?? availableAudioTracks.first(where: { $0.isDefault })
            ?? availableAudioTracks.first
        selectedAudioTrackID = preferredAudioTrack?.id
        playbackProof.sourceAudioTrackSelected = preferredAudioTrack?.title
        AppLog.playback.info(
            "Audio selected: '\(preferredAudioTrack?.title ?? "none", privacy: .public)' lang='\(preferredAudioTrack?.language ?? "?", privacy: .public)' codec=\(audioSelection.selectedCodec, privacy: .public) reason=[\(audioSelection.reason, privacy: .public)]"
        )
        if audioSelection.trueHDWasDeprioritized {
            AppLog.playback.notice("\(PlaybackFailureReason.trueHDDeprioritizedForNativePath.localizedDescription ?? "TrueHD deprioritized", privacy: .public)")
        }

        // ── Initial subtitle selection ────────────────────────────────────────────
        // Auto-select a subtitle track at startup when an unambiguous choice exists:
        //   1. A track explicitly marked `isDefault` in the source metadata.
        //   2. A forced-subtitle track in the preferred subtitle language (or audio language).
        // Manual user selection always overrides this at runtime.
        selectedSubtitleTrackID = initialSubtitleTrackID(
            tracks: availableSubtitleTracks,
            preferredSubtitleLanguage: preferredSubtitleLanguage,
            selectedAudioLanguage: preferredAudioTrack?.language
        )
        if let initialSubID = selectedSubtitleTrackID,
           let track = availableSubtitleTracks.first(where: { $0.id == initialSubID }) {
            AppLog.playback.info(
                "Subtitle auto-selected: '\(track.title, privacy: .public)' lang='\(track.language ?? "?", privacy: .public)' default=\(track.isDefault, privacy: .public)"
            )
        }

        routeDescription = routeLabel(for: selection.decision.route)

        // ── HDR / DV expectation log ─────────────────────────────────────────────
        // Emit an honest single-line summary of what dynamic range this session
        // expects to deliver, and why.  This makes "did DV survive the pipeline?"
        // answerable from logs without a full diagnostics session.
        emitDynamicRangeExpectationLog(selection: selection)

        // Determine buffer tuning per play method
        var forwardBuffer: Double
        var waitsToMinimize: Bool
        switch selection.decision.route {
        case .directPlay, .nativeBridge:
            forwardBuffer = ttffTuning.directPlayForwardBufferDuration
            waitsToMinimize = ttffTuning.directPlayWaitsToMinimizeStalling
        case .remux:
            forwardBuffer = ttffTuning.remuxForwardBufferDuration
            waitsToMinimize = ttffTuning.remuxWaitsToMinimizeStalling
        case .transcode:
            forwardBuffer = ttffTuning.transcodeForwardBufferDuration
            waitsToMinimize = ttffTuning.transcodeWaitsToMinimizeStalling
        }

        if isLocalSyntheticHLSURL(selection.assetURL) {
            // NativeBridge local HLS startup: bias for earliest first frame.
            forwardBuffer = min(forwardBuffer, 0.25)
            waitsToMinimize = false
        }

        player.automaticallyWaitsToMinimizeStalling = waitsToMinimize

        if let urlValidationError = assetURLValidator.validate(url: selection.assetURL) {
            AppLog.playback.error("Asset URL validation failed: \(urlValidationError.localizedDescription, privacy: .public)")
            playbackErrorMessage = urlValidationError.localizedDescription
            return
        }
        AppLog.playback.notice("Preparing AVURLAsset url=\(selection.assetURL.absoluteString, privacy: .public)")

        let asset: AVURLAsset
        if let bridgeSession = self.nativeBridgeSession {
            asset = bridgeSession.makeAsset()
        } else {
            if isLocalSyntheticHLSURL(selection.assetURL) {
                guard let localHLSServer else {
                    AppLog.nativeBridge.error("[NB-DIAG] hls.server.missing-before-avasset — url=\(selection.assetURL.absoluteString, privacy: .public)")
                    playbackErrorMessage = "Local HLS server is unavailable."
                    return
                }

                let state = localHLSServer.currentState()
                switch state {
                case .listening, .serving:
                    break
                case .failed(let reason):
                    AppLog.nativeBridge.error("[NB-DIAG] hls.server.invalid-state-before-avasset — state=failed reason=\(reason, privacy: .public)")
                    playbackErrorMessage = "Local HLS server failed before playback."
                    return
                default:
                    AppLog.nativeBridge.error("[NB-DIAG] hls.server.invalid-state-before-avasset — state=\(String(describing: state), privacy: .public)")
                    playbackErrorMessage = "Local HLS server is not ready."
                    return
                }
            }

            // Do not use AVURLAssetHTTPHeaderFieldsKey here.
            // Apple has stated this key is unsupported API and can cause unstable behavior.
            // We authenticate using api_key in URL query for playback URLs instead.
            // Ref: https://developer.apple.com/forums/thread/671139
            var assetOptions: [String: Any] = [:]
#if os(iOS)
            assetOptions[AVURLAssetAllowsCellularAccessKey] = true
#endif
            if !selection.headers.isEmpty {
                AppLog.playback.notice(
                    "Ignoring unsupported AVURLAsset header injection for stable playback (headerCount=\(selection.headers.count, privacy: .public))."
                )
            }
            asset = AVURLAsset(url: selection.assetURL, options: assetOptions)
            AppLog.nativeBridge.notice("[NB-DIAG] avasset.created — url=\(selection.assetURL.absoluteString, privacy: .public)")
        }

        let playerItem = AVPlayerItem(asset: asset)
        AppLog.nativeBridge.notice("[NB-DIAG] avplayeritem.created — method=\(self.playMethodForReporting, privacy: .public)")
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        let output = AVPlayerItemVideoOutput(
            pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
            ]
        )
        playerItem.add(output)
        videoOutput = output
        playerItem.preferredForwardBufferDuration = forwardBuffer

        readyInterval = SignpostInterval(signposter: Signpost.playerLifecycle, name: "avplayer_item_ready")
        firstFrameInterval = SignpostInterval(signposter: Signpost.playerLifecycle, name: "avplayer_first_frame")
        hasMarkedFirstFrame = false
        hasDecodedVideoFrame = false
        startDate = Date()

        player.replaceCurrentItem(with: playerItem)
        configureObservers(for: playerItem)
        updatePlaybackProof(from: playerItem)
        startVideoOutputPolling(for: playerItem)

        if let resumeSeconds, resumeSeconds > 0 {
            let seek = CMTime(seconds: resumeSeconds, preferredTimescale: 600)
            let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
            player.seek(to: seek, toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
    }

    public func stop() {
        let progressSnapshot = makeProgressSnapshot(isPaused: true, didFinish: false)
        let bridgeSession = nativeBridgeSession

        pause()
        tearDownCurrentItemObservers()
        player.replaceCurrentItem(with: nil)

        currentTime = 0
        duration = 0
        availableAudioTracks = []
        availableSubtitleTracks = []
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = nil
        routeDescription = ""
        debugInfo = nil
        currentPlaybackPlan = nil
        runtimeHDRMode = .unknown
        metrics = PlaybackPerformanceMetrics()
        isExternalPlaybackActive = false
        playbackErrorMessage = nil
        playbackProof = PlaybackProofSnapshot()

        currentItemID = nil
        currentItemHasDolbyVision = false
        currentSource = nil
        pendingResumeSeconds = nil
        didResumeAfterForeground = false
        hasMarkedFirstFrame = false
        hasDecodedVideoFrame = false
        playMethodForReporting = "Transcode"
        lastPreparedSelection = nil
        videoOutput = nil
        selectedVariantInfo = nil
        selectedMasterPlaylistURL = nil
        selectedVariantPlaylistInspection = nil
        selectedInitSegmentInspection = nil
        localHLSStartupSummary = nil

        readyInterval = nil
        firstFrameInterval = nil
        activeStallInterval = nil
        ttffPipelineInterval = nil
        ttffInfoInterval = nil
        ttffResolveInterval = nil
        ttffFirstBytesInterval = nil
        ttffReadyMs = 0
        ttffInfoMs = 0
        ttffResolveMs = 0
        ttffFirstBytesMs = 0

        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
        decodedFrameWatchdogTask?.cancel()
        decodedFrameWatchdogTask = nil
        videoOutputPollTask?.cancel()
        videoOutputPollTask = nil

        nativeBridgeSession = nil
        syntheticHLSSession = nil
        localHLSServer?.stop(reason: "session_stopped")
        localHLSServer = nil

        if let progressSnapshot {
            Task { @MainActor [weak self] in
                await self?.persistProgress(snapshot: progressSnapshot)
            }
        }

        if let bridgeSession {
            Task {
                await bridgeSession.invalidate()
            }
        }
    }

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    public func seek(by seconds: Double) {
        let current = player.currentTime().seconds
        let newTime = max(0, current + seconds)
        let target = CMTime(seconds: newTime, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        handleSyntheticSeekInvalidation(target: target)
    }

    public func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        handleSyntheticSeekInvalidation(target: target)
    }

    public func exportNativeBridgeDebugBundle() async -> URL? {
        guard let session = nativeBridgeSession else { return nil }
        return try? await session.exportDebugBundle()
    }

    /// Whether the current playback is a progressive DirectPlay (static=true).
    public var isCurrentlyDirectPlay: Bool {
        playMethodForReporting == "DirectPlay"
    }

    public func selectAudioTrack(id: String) {
        guard let track = availableAudioTracks.first(where: { $0.id == id }) else { return }

        // 1. Try native AVMediaSelectionGroup first (works for multi-track containers).
        if let item = player.currentItem,
           let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            let options = group.options
            let descriptors = makeSelectionDescriptors(options: options)
            if let optionIndex = PlaybackTrackMatcher.bestOptionIndex(for: track, options: descriptors) {
                item.select(options[optionIndex], in: group)
                selectedAudioTrackID = id
                AppLog.playback.info("Audio track switched natively: '\(track.title, privacy: .public)'")
                return
            }
        }

        // 2. Fallback: reload with AudioStreamIndex.
        //    Works for both progressive DirectPlay and Jellyfin HLS manifests.
        //    NativeBridge delivers a single-track fMP4; audio switching is not yet supported there.
        guard playMethodForReporting != "NativeBridge" else {
            AppLog.playback.warning("Audio track switching not supported on NativeBridge path.")
            return
        }
        Task { @MainActor [weak self] in
            await self?.reloadForAudioTrack(track)
        }
    }

    /// Reload the current stream with a different AudioStreamIndex.
    ///
    /// Handles both progressive DirectPlay URLs and Jellyfin HLS manifests.
    /// The `assetURL` from the last prepared selection already carries authentication
    /// parameters, so no extra auth injection is needed.
    /// Preserves any active subtitle selection so the subtitle track is not lost on reload.
    private func reloadForAudioTrack(_ track: MediaTrack) async {
        guard let selection = lastPreparedSelection else { return }

        let currentSeconds = player.currentTime().seconds.isFinite ? max(0, player.currentTime().seconds) : 0
        guard var components = URLComponents(url: selection.assetURL, resolvingAgainstBaseURL: false) else { return }

        var items = components.queryItems ?? []
        items.removeAll { $0.name.lowercased() == "audiostreamindex" }
        items.append(URLQueryItem(name: "AudioStreamIndex", value: "\(track.index)"))

        // Preserve an active subtitle selection so it is not lost after the reload.
        if let subID = selectedSubtitleTrackID,
           let sub = availableSubtitleTracks.first(where: { $0.id == subID }) {
            items.removeAll { ["subtitlestreamindex", "subtitlemethod"].contains($0.name.lowercased()) }
            items.append(URLQueryItem(name: "SubtitleStreamIndex", value: "\(sub.index)"))
            items.append(URLQueryItem(name: "SubtitleMethod", value: "Hls"))
        }

        components.queryItems = items
        guard let newURL = components.url else { return }

        AppLog.playback.info(
            "Audio reload: track='\(track.title, privacy: .public)' index=\(track.index, privacy: .public)"
        )

        var assetOptions: [String: Any] = [:]
#if os(iOS)
        assetOptions[AVURLAssetAllowsCellularAccessKey] = true
#endif
        let newAsset = AVURLAsset(url: newURL, options: assetOptions)
        let newItem = AVPlayerItem(asset: newAsset)
        newItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        player.replaceCurrentItem(with: newItem)
        selectedAudioTrackID = track.id

        if currentSeconds > 0 {
            let seekTarget = CMTime(seconds: currentSeconds, preferredTimescale: 600)
            let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
            await player.seek(to: seekTarget, toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
        if isPlaying { player.play() }
    }

    public func selectSubtitleTrack(id: String?) {
        if let id, let track = availableSubtitleTracks.first(where: { $0.id == id }) {
            // Guard: block bitmap subtitles in strict HDR mode (they force destructive transcode).
            if subtitlePolicy.shouldBlockSubtitleSelection(
                track: track,
                strictMode: strictQualityIsActive,
                sourceIsHDRorDV: currentSource?.isLikelyHDRorDV == true
            ) {
                AppLog.playback.warning(
                    "\(PlaybackFailureReason.subtitleWouldForceDestructiveTranscode.localizedDescription ?? "Strict subtitle guard triggered.", privacy: .public) subtitle=\(track.title, privacy: .public)"
                )
                playbackErrorMessage = "PGS/VobSub subtitles are disabled in strict HDR mode to protect video quality."
                return
            }

            // 1. Try native AVMediaSelectionGroup (works for embedded subtitle tracks).
            if let item = player.currentItem,
               let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                let options = group.options
                let descriptors = makeSelectionDescriptors(options: options)
                if let optionIndex = PlaybackTrackMatcher.bestOptionIndex(for: track, options: descriptors) {
                    item.select(options[optionIndex], in: group)
                    selectedSubtitleTrackID = id
                    AppLog.playback.info("Subtitle track switched natively: '\(track.title, privacy: .public)'")
                    return
                }
            }

            // 2. Fallback: the subtitle is not embedded in the container (external SRT/ASS).
            //    Reload via Jellyfin's HLS direct-stream endpoint with the subtitle injected
            //    in the manifest (SubtitleStreamIndex + SubtitleMethod=Hls).
            AppLog.playback.info(
                "Subtitle '\(track.title, privacy: .public)' not in AVMediaSelectionGroup — reloading via HLS sidecar"
            )
            Task { @MainActor [weak self] in
                await self?.reloadForSubtitleTrack(track)
            }
        } else {
            // Disable subtitles.
            selectedSubtitleTrackID = nil
            if let item = player.currentItem,
               let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                item.select(nil, in: group)
            }
        }
    }

    /// Reload the current stream via Jellyfin's HLS direct-stream endpoint,
    /// asking it to embed the given subtitle track in the manifest.
    ///
    /// This is the fallback path for tracks that are NOT embedded in the
    /// primary container (e.g. external SRT/ASS files alongside an MKV/MP4).
    /// Jellyfin responds with an HLS master playlist that contains an
    /// EXT-X-MEDIA TYPE=SUBTITLES entry referencing the sidecar WebVTT.
    private func reloadForSubtitleTrack(_ track: MediaTrack) async {
        guard let selection = lastPreparedSelection else { return }

        // Prefer the HLS direct-stream URL so Jellyfin can embed the subtitle
        // track in the manifest. Fall back to the transcode URL when no direct
        // stream is available.
        let baseURL = selection.source.directStreamURL ?? selection.source.transcodeURL
        guard let baseURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        else {
            AppLog.playback.warning("selectSubtitleTrack: no HLS base URL available for subtitle reload")
            return
        }

        var items = components.queryItems ?? []
        items.removeAll {
            ["subtitlestreamindex", "subtitlemethod"].contains($0.name.lowercased())
        }
        items.append(URLQueryItem(name: "SubtitleStreamIndex", value: "\(track.index)"))
        items.append(URLQueryItem(name: "SubtitleMethod", value: "Hls"))

        // Preserve an active audio selection so it is not lost after the reload.
        if let audioID = selectedAudioTrackID,
           let audio = availableAudioTracks.first(where: { $0.id == audioID }) {
            items.removeAll { $0.name.lowercased() == "audiostreamindex" }
            items.append(URLQueryItem(name: "AudioStreamIndex", value: "\(audio.index)"))
        }

        // Inject api_key if not already present (api_key is preferred over X-Emby-Token
        // headers for AVURLAsset; see note in prepareAndLoadSelection).
        if !items.contains(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame }) {
            if let token = await apiClient.currentSession()?.token {
                items.append(URLQueryItem(name: "api_key", value: token))
            }
        }
        components.queryItems = items

        guard let hlsURL = components.url else { return }

        AppLog.playback.info(
            "Subtitle reload via HLS: track='\(track.title, privacy: .public)' index=\(track.index, privacy: .public)"
        )

        let currentSeconds = player.currentTime().seconds.isFinite ? max(0, player.currentTime().seconds) : 0

        var assetOptions: [String: Any] = [:]
#if os(iOS)
        assetOptions[AVURLAssetAllowsCellularAccessKey] = true
#endif
        let newAsset = AVURLAsset(url: hlsURL, options: assetOptions)
        let newItem = AVPlayerItem(asset: newAsset)
        newItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        player.replaceCurrentItem(with: newItem)
        selectedSubtitleTrackID = track.id

        // Resume from the same timestamp after the reload.
        if currentSeconds > 0 {
            let target = CMTime(seconds: currentSeconds, preferredTimescale: 600)
            let tolerance = CMTime(seconds: 2.0, preferredTimescale: 600)
            await player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
        if isPlaying { player.play() }
    }

    /// Log the expected dynamic range outcome for the current playback session.
    ///
    /// This is intentionally pessimistic: it reports the *worst-case* expected
    /// outcome given the chosen route, not the best-case hope.
    ///
    /// Examples:
    ///  • MKV DV 8.1 → transcode (appleOptimizedHEVC) → expected: HDR10
    ///    Reason: server-side HEVC transcode can preserve HDR10 metadata but DV
    ///    SEI metadata is not reliably carried through the Jellyfin remux pipeline.
    ///  • MP4 DV 5 → directPlay → expected: Dolby Vision
    ///  • MKV HDR10 → transcode (forceH264Transcode) → expected: SDR
    ///    Reason: H.264 output is SDR; HDR metadata is dropped.
    private func emitDynamicRangeExpectationLog(selection: PlaybackAssetSelection) {
        let source = selection.source
        let route = selection.decision.route

        // Derive what the source carries
        let sourceDV = (source.dvProfile ?? 0) > 0
            || source.normalizedVideoCodec.contains("dvhe")
            || source.normalizedVideoCodec.contains("dvh1")
        let sourceHDR = source.isLikelyHDRorDV
        let sourceHDR10Plus = source.hdr10PlusPresentFlag == true

        guard sourceHDR else {
            // SDR source — nothing noteworthy to log
            AppLog.playback.debug("HDR: source is SDR — no HDR/DV metadata present.")
            return
        }

        let expected: String
        let reason: String

        switch route {
        case .directPlay:
            if sourceDV {
                expected = "Dolby Vision"
                reason = "direct play of native DV container"
            } else {
                expected = sourceHDR10Plus ? "HDR10 (HDR10+ not guaranteed)" : "HDR10"
                reason = "direct play preserves HDR metadata"
            }

        case .remux:
            if sourceDV {
                expected = "HDR10 (DV downgrade)"
                reason = "remux path does not carry DV SEI; DV metadata is lost"
            } else {
                expected = sourceHDR10Plus ? "HDR10 (HDR10+ dynamic metadata not preserved)" : "HDR10"
                reason = "remux preserves static HDR10 but may drop dynamic metadata"
            }

        case .transcode(let url):
            let urlString = url.absoluteString.lowercased()
            let isH264 = urlString.contains("videocodec=h264") || urlString.contains("requireavc=true")
            let isFMP4HEVC = urlString.contains("container=fmp4") && (urlString.contains("videocodec=hevc") || !urlString.contains("videocodec=h264"))
            if isH264 {
                expected = "SDR"
                reason = "H.264 transcode drops all HDR/DV metadata"
            } else if isFMP4HEVC && sourceDV {
                expected = "HDR10 (DV not reliably preserved through Jellyfin remux)"
                reason = "HEVC fMP4 can carry HDR10 boxes; DV RPU/EL depends on server support"
            } else if isFMP4HEVC {
                expected = sourceHDR10Plus ? "HDR10 (HDR10+ dynamic metadata not preserved)" : "HDR10"
                reason = "HEVC fMP4 transcode preserves static HDR10 color metadata"
            } else {
                expected = "SDR (TS container does not carry HDR metadata)"
                reason = "TS segment container cannot carry HDR10/DV metadata boxes"
            }

        case .nativeBridge:
            if sourceDV {
                expected = "Dolby Vision (if dvcC box generated correctly)"
                reason = "local fMP4 repackager writes dvcC; verify init segment inspection"
            } else {
                expected = sourceHDR10Plus ? "HDR10 (HDR10+ not preserved in fMP4)" : "HDR10"
                reason = "local fMP4 repackager writes mdcv/clli boxes for HDR10"
            }
        }

        AppLog.playback.notice(
            "HDR expectation: expected='\(expected, privacy: .public)' source=\(sourceDV ? "DV" : (sourceHDR10Plus ? "HDR10+" : "HDR10"), privacy: .public) route=\(selection.decision.playMethod, privacy: .public) reason='\(reason, privacy: .public)'"
        )
        if sourceDV && expected.contains("HDR10") {
            AppLog.playback.warning(
                "HDR downgrade: Dolby Vision source will play as HDR10 on this route. To preserve DV, use direct play or ensure server-side DV packaging is enabled."
            )
        }
        if sourceHDR10Plus && !expected.contains("HDR10+") {
            AppLog.playback.info(
                "HDR10+: dynamic HDR metadata (HDR10+) present in source but will not be preserved on this route."
            )
        }
    }

    /// Determine which subtitle track (if any) should be auto-selected at startup.
    ///
    /// Rules applied in order:
    ///  1. A track flagged `isDefault` is selected if it exists and is not a bitmap
    ///     format that would conflict with strict-quality mode.
    ///  2. A forced-subtitle track whose language matches `preferredSubtitleLanguage`
    ///     or `selectedAudioLanguage` (so foreign-language inserts are shown even
    ///     when the user did not explicitly choose subtitles).
    ///  3. Otherwise nil — no subtitle is auto-selected; user must choose manually.
    private func initialSubtitleTrackID(
        tracks: [MediaTrack],
        preferredSubtitleLanguage: String?,
        selectedAudioLanguage: String?
    ) -> String? {
        guard !tracks.isEmpty else { return nil }

        let isHDRSource = currentSource?.isLikelyHDRorDV == true

        // Helper: is this track selectable given current quality mode?
        func isSelectable(_ track: MediaTrack) -> Bool {
            !subtitlePolicy.shouldBlockSubtitleSelection(
                track: track,
                strictMode: strictQualityIsActive,
                sourceIsHDRorDV: isHDRSource
            )
        }

        // Helper: does the track language match a preferred language tag?
        func matchesPreferred(_ track: MediaTrack, _ preferred: String?) -> Bool {
            guard let preferred, let lang = track.language else { return false }
            return AudioTrackLanguageNormalizer.matches(lang, preferred)
        }

        // 1. Explicit default track — mirrors what the encoder/muxer intended.
        if let defaultTrack = tracks.first(where: { $0.isDefault && isSelectable($0) }) {
            return defaultTrack.id
        }

        // 2. Forced subtitles in the preferred subtitle language (explicit preference).
        let titleLower = { (t: MediaTrack) in t.title.lowercased() }
        func isForced(_ t: MediaTrack) -> Bool {
            t.isForced || titleLower(t).contains("forced") || titleLower(t).contains("forcé")
        }

        if let preferred = preferredSubtitleLanguage {
            if let forced = tracks.first(where: { isForced($0) && matchesPreferred($0, preferred) && isSelectable($0) }) {
                return forced.id
            }
        }

        // 3. Forced subtitles in the currently selected audio language
        //    (common use case: French audio with occasional English dialogue inserts).
        if let audioLang = selectedAudioLanguage {
            if let forced = tracks.first(where: { isForced($0) && matchesPreferred($0, audioLang) && isSelectable($0) }) {
                return forced.id
            }
        }

        return nil
    }

    private func configurePlayerBase() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = true
        player.appliesMediaSelectionCriteriaAutomatically = false
        // Keep local rendering stable by default; user can still explicitly route to AirPlay.
        player.usesExternalPlaybackWhileExternalScreenIsActive = false
        player.actionAtItemEnd = .pause

#if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            do {
#if targetEnvironment(simulator)
                // Simulator haptic/audio stack can reject moviePlayback options (OSStatus -50).
                try session.setCategory(.playback)
#else
                try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
#endif
                try session.setActive(true)
            } catch {
                // Fallback profile for devices/simulators that reject advanced movie session options.
                try session.setCategory(.playback)
                try session.setActive(true)
            }
        } catch {
            AppLog.playback.warning("Audio session setup failed: \(error.localizedDescription, privacy: .public)")
        }
#endif

        externalPlaybackObserver = player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            Task { @MainActor in
                self.isExternalPlaybackActive = player.isExternalPlaybackActive
            }
        }
    }

    private func makeSelectionDescriptors(options: [AVMediaSelectionOption]) -> [MediaSelectionOptionDescriptor] {
        options.enumerated().map { index, option in
            MediaSelectionOptionDescriptor(
                optionIndex: index,
                displayName: option.displayName,
                languageIdentifier: option.locale?.identifier,
                extendedLanguageTag: option.extendedLanguageTag,
                isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
            )
        }
    }

    private func setupLifecycleObservers() {
        let center = NotificationCenter.default

        let resign = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.isPlaying {
                    self.didResumeAfterForeground = true
                    self.pause()
                }
            }
        }

        let active = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.didResumeAfterForeground {
                    self.didResumeAfterForeground = false
                    self.play()
                }
            }
        }

        lifecycleObservers = [resign, active]
    }

    private func configureObservers(for item: AVPlayerItem) {
        tearDownCurrentItemObservers()

        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = max(0, time.seconds)
                self.duration = max(self.currentTime, self.player.currentItem?.duration.seconds ?? 0)
                self.refreshDecodedVideoFrameState()
                self.markFirstFrameIfNeeded(currentSeconds: self.currentTime)
                await self.persistProgress(isPaused: !self.isPlaying, didFinish: false)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.isPlaying = false
                await self.persistProgress(isPaused: true, didFinish: true)
                if let currentItemID = self.currentItemID {
                    try? await self.apiClient.reportPlayed(itemID: currentItemID)
                }
            }
        }

        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.metrics.stallCount += 1
                self.activeStallInterval = SignpostInterval(signposter: Signpost.playbackStalls, name: "playback_stall")
                AppLog.playback.warning("Playback stalled.")
            }
        }

        accessLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let event = item.accessLog()?.events.last else { return }
                self.metrics.droppedFrames = Int(event.numberOfDroppedVideoFrames)
                if self.debugInfo?.bitrate == nil, event.observedBitrate > 0 {
                    self.debugInfo?.bitrate = Int(event.observedBitrate)
                }
                if event.indicatedBitrate > 0 {
                    self.playbackProof.variantBandwidth = Int(event.indicatedBitrate)
                }
                if event.observedBitrate > 0 {
                    self.playbackProof.observedBitrate = Int(event.observedBitrate)
                }
                self.updatePlaybackProof(from: item)
            }
        }

        playerItemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.player.currentItem === observedItem else { return }
                let statusText: String
                switch observedItem.status {
                case .unknown: statusText = "unknown"
                case .readyToPlay: statusText = "readyToPlay"
                case .failed: statusText = "failed"
                @unknown default: statusText = "unknown_future"
                }
                self.lastPlayerItemStatus = statusText
                self.playbackProof.playerItemStatus = statusText
                AppLog.nativeBridge.notice("[NB-DIAG] avplayeritem.status — status=\(statusText, privacy: .public)")

                if observedItem.status == .readyToPlay {
                    self.readyInterval?.end(name: "avplayer_item_ready", message: "ready_to_play")
                    self.readyInterval = nil
                    self.ttffReadyMs = Date().timeIntervalSince(self.startDate) * 1000
                    self.runtimeHDRMode = self.detectHDRMode(from: observedItem, fallback: .unknown)
                    self.updatePlaybackProof(from: observedItem)
                    self.scheduleVideoValidation(for: observedItem)
                    self.emitLocalHLSStartupSummary(avplayerResult: "readyToPlay")
                    // Apply the initial subtitle selection now that AVFoundation media
                    // selection groups are available. This is a no-op if nil.
                    if let initialSubID = self.selectedSubtitleTrackID {
                        self.selectSubtitleTrack(id: initialSubID)
                    }
                } else if observedItem.status == .failed {
                    self.readyInterval?.end(name: "avplayer_item_ready", message: "ready_failed")
                    self.firstFrameInterval?.end(name: "avplayer_first_frame", message: "first_frame_failed")
                    let message = observedItem.error?.localizedDescription ?? "Playback failed."
                    self.isPlaying = false
                    if let nsError = observedItem.error as NSError? {
                        self.lastFailureDomain = nsError.domain
                        self.lastFailureCode = nsError.code
                        self.lastFailureReason = nsError.localizedFailureReason
                        self.lastRecoverySuggestion = nsError.localizedRecoverySuggestion
                        self.playbackProof.failureDomain = nsError.domain
                        self.playbackProof.failureCode = nsError.code
                        self.playbackProof.failureReason = nsError.localizedFailureReason
                        self.playbackProof.recoverySuggestion = nsError.localizedRecoverySuggestion
                        AppLog.playback.error(
                            "AVPlayerItem error domain=\(nsError.domain, privacy: .public) code=\(nsError.code) message=\(message, privacy: .public)"
                        )
                        if let reason = nsError.localizedFailureReason {
                            AppLog.playback.error("AVPlayerItem failureReason=\(reason, privacy: .public)")
                        }
                        if let suggestion = nsError.localizedRecoverySuggestion {
                            AppLog.playback.error("AVPlayerItem recoverySuggestion=\(suggestion, privacy: .public)")
                        }
                    }
                    AppLog.playback.error("AVPlayerItem failed: \(message, privacy: .public)")
                    self.emitLocalHLSStartupSummary(avplayerResult: "failed")

                    if await self.handlePlaybackFailure(message: message, error: observedItem.error as NSError?) {
                        return
                    }

                    self.playbackErrorMessage = message
                }
            }
        }

        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, _ in
            guard let self else { return }
            Task { @MainActor in
                switch observedPlayer.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.activeStallInterval?.end(name: "playback_stall", message: "recovered")
                    self.activeStallInterval = nil
                case .paused:
                    self.isPlaying = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = false
                @unknown default:
                    self.isPlaying = false
                }
            }
        }
    }

    private func markFirstFrameIfNeeded(currentSeconds: Double) {
        guard !hasMarkedFirstFrame, currentSeconds > 0 else { return }
        guard let currentItem = player.currentItem else { return }
        let size = currentItem.presentationSize
        guard hasDecodedVideoFrame else { return }
        guard size.width > 1, size.height > 1 else { return }
        hasMarkedFirstFrame = true
        playbackErrorMessage = nil
        startupWatchdogTask?.cancel()
        decodedFrameWatchdogTask?.cancel()
        videoOutputPollTask?.cancel()
        let elapsedMs = Date().timeIntervalSince(startDate) * 1000
        metrics.timeToFirstFrameMs = elapsedMs
        AppLog.nativeBridge.notice("[NB-DIAG] avplayer.first-frame — elapsedMs=\(elapsedMs, format: .fixed(precision: 1)) currentTime=\(currentSeconds, format: .fixed(precision: 3))")
        emitLocalHLSStartupSummary(avplayerResult: "firstFrame")
        firstFrameInterval?.end(name: "avplayer_first_frame", message: "first_frame_rendered")
        firstFrameInterval = nil
        ttffPipelineInterval?.end(name: "ttff_total", message: "complete")
        ttffPipelineInterval = nil
        applyDeferredResumeSeekIfNeeded()
        rememberWorkingProfileForCurrentItem()

        // Structured TTFF pipeline summary
        let method = playMethodForReporting
        let profile = activeTranscodeProfile.rawValue
        AppLog.playback.info(
            "TTFF \(elapsedMs, format: .fixed(precision: 1))ms [info=\(self.ttffInfoMs, format: .fixed(precision: 1))ms resolve=\(self.ttffResolveMs, format: .fixed(precision: 1))ms ready=\(self.ttffReadyMs, format: .fixed(precision: 1))ms] method=\(method, privacy: .public) profile=\(profile, privacy: .public)"
        )

        if playMethodForReporting == "NativeBridge", let itemID = currentItemID {
            NativeBridgeFailureCache.clearFailure(itemID: itemID)
        }
    }

    private func scheduleVideoValidation(for item: AVPlayerItem) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let validationDelay = self.videoValidationDelayNanoseconds()
            try? await Task.sleep(nanoseconds: validationDelay)
            guard self.player.currentItem === item else { return }
            guard !self.hasMarkedFirstFrame else { return }
            self.refreshDecodedVideoFrameState()

            if self.isRiskyServerDefaultHEVCTranscode(item: item) {
                AppLog.playback.warning("Server default HEVC stream-copy detected before first frame. Switching to Apple optimized profile.")
                if !(await self.attemptRecovery(
                    reason: "risky_hevc_stream_copy",
                    userMessage: "Optimizing HEVC playback path to avoid black screen."
                )) {
                    self.playbackErrorMessage = "Could not stabilize HEVC playback automatically."
                }
                return
            }

            if self.currentTime >= 3.0, !self.hasDecodedVideoFrame {
                AppLog.playback.warning("Playback advanced without decoded video frame. Trying compatibility profile.")
                if !(await self.attemptRecovery(
                    reason: "audio_only_no_video",
                    userMessage: "Audio is playing without video. Switching stream profile."
                )) {
                    self.playbackErrorMessage = "Audio is playing but no video frame is decoding."
                }
                return
            }

            let size = item.presentationSize
            guard size.width <= 1 || size.height <= 1 else { return }

            AppLog.playback.error("Ready item has no video presentation size. Trying compatibility transcode.")
            if !(await self.attemptRecovery(
                reason: "video_presentation_size_zero",
                userMessage: "No video frame decoded. Trying compatibility stream."
            )) {
                self.playbackErrorMessage = "Audio plays but no video frame is decodable for this source."
            }
        }
    }

    private func emitLocalHLSStartupSummary(avplayerResult: String) {
        guard let summary = localHLSStartupSummary else { return }
        let keyframeValue: String
        if let keyframePresent = summary.keyframePresent {
            keyframeValue = keyframePresent ? "yes" : "no"
        } else {
            keyframeValue = "unknown"
        }

        AppLog.nativeBridge.notice(
            "[NB-DIAG] hls.startup.summary — lane=nativeBridge host=\(summary.host, privacy: .public) port=\(summary.port, privacy: .public) master=\(summary.masterURL.absoluteString, privacy: .public) initBytes=\(summary.initBytes, privacy: .public) firstSegBytes=\(summary.firstSegmentBytes, privacy: .public) firstSegDuration=\(summary.firstSegmentDurationSeconds, format: .fixed(precision: 3)) keyframe=\(keyframeValue, privacy: .public) preflight=pass avplayer=\(avplayerResult, privacy: .public)"
        )
    }

    private func scheduleStartupWatchdog() {
        startupWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let delay = self.startupWatchdogDelayNanoseconds()
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            guard !self.hasMarkedFirstFrame else { return }
            guard let currentItem = self.player.currentItem else { return }

            let delaySeconds = Double(delay) / 1_000_000_000

            if currentItem.status == .readyToPlay {
                // Item is readyToPlay but no first frame yet.
                // Give a bounded extension (8s) before hard-failing.
                // This prevents the zombie state where readyToPlay never
                // produces a decoded video frame.
                let extensionNs: UInt64 = 8_000_000_000
                try? await Task.sleep(nanoseconds: extensionNs)
                guard !Task.isCancelled else { return }
                guard !self.hasMarkedFirstFrame else { return }

                self.refreshDecodedVideoFrameState()
                guard !self.hasDecodedVideoFrame else { return }

                let totalDelay = delaySeconds + Double(extensionNs) / 1_000_000_000
                let reason = StartupFailureReason.readyButNoVideoFrame
                AppLog.playback.error(
                    "playback.startup.failure — reason=\(reason.rawValue, privacy: .public) profile=\(self.activeTranscodeProfile.rawValue, privacy: .public) hardDeadline=\(totalDelay, format: .fixed(precision: 1))s status=readyToPlay decodedFrame=false"
                )
                if !(await self.attemptRecovery(
                    reason: reason.rawValue,
                    userMessage: "No video frame after readyToPlay. Switching profile."
                )), self.playbackErrorMessage == nil {
                    self.playbackErrorMessage = "No video frame received. Try changing quality or source."
                }
                return
            }

            AppLog.playback.warning("Startup watchdog fired: no first frame after \(delaySeconds, format: .fixed(precision: 1))s.")
            if !(await self.attemptRecovery(
                reason: StartupFailureReason.startupWatchdogExpired.rawValue,
                userMessage: "Startup was too slow. Retrying with safer playback profile."
            )), self.playbackErrorMessage == nil {
                self.playbackErrorMessage = "No video frame received. Try changing quality or source."
            }
        }
    }

    private func scheduleDecodedFrameWatchdog() {
        decodedFrameWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let delay = self.decodedFrameWatchdogDelayNanoseconds()
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            guard !self.hasMarkedFirstFrame else { return }
            guard self.player.currentItem != nil else { return }

            self.refreshDecodedVideoFrameState()
            guard !self.hasDecodedVideoFrame else { return }

            let playerSecondsRaw = self.player.currentTime().seconds
            let playerSeconds = playerSecondsRaw.isFinite ? max(0, playerSecondsRaw) : 0
            let playbackSeconds = max(self.currentTime, playerSeconds)
            let playbackHasStarted = playbackSeconds >= 0.8
            guard playbackHasStarted else { return }

            let delaySeconds = Double(delay) / 1_000_000_000
            AppLog.playback.warning("Decoded-frame watchdog fired after \(delaySeconds, format: .fixed(precision: 1))s.")
            if !(await self.attemptRecovery(
                reason: "decoded_frame_watchdog",
                userMessage: "Video decoding did not start quickly enough. Retrying profile."
            )), self.playbackErrorMessage == nil {
                self.playbackErrorMessage = "Video decoding did not start."
            }
        }
    }

    private func decodedFrameWatchdogDelayNanoseconds() -> UInt64 {
        switch activeTranscodeProfile {
        case .serverDefault:
            return isCurrentHEVCStreamCopyTranscode() ? 3_000_000_000 : 5_000_000_000
        case .appleOptimizedHEVC:
            return 5_000_000_000
        case .conservativeCompatibility:
            return 5_000_000_000
        case .forceH264Transcode:
            return 4_000_000_000
        }
    }

    private func startupWatchdogDelayNanoseconds() -> UInt64 {
        switch activeTranscodeProfile {
        case .serverDefault:
            return isCurrentHEVCStreamCopyTranscode() ? 6_000_000_000 : 8_000_000_000
        case .appleOptimizedHEVC:
            // HEVC startup on large HDR/DV assets can legitimately exceed 8s.
            // Give more room before switching to an SDR fallback profile.
            return currentItemHasDolbyVision ? 14_000_000_000 : 10_000_000_000
        case .conservativeCompatibility:
            return 8_000_000_000
        case .forceH264Transcode:
            // H264 compatibility fallback may legitimately take longer to produce
            // the first video frame; avoid premature recovery loops.
            return 30_000_000_000
        }
    }

    private func attemptRecovery(
        reason: String,
        userMessage: String,
        retryDelayNanoseconds: UInt64 = 0
    ) async -> Bool {
        if isRecoveryInProgress {
            return true
        }
        guard recoveryAttemptCount < maxRecoveryAttempts else {
            if strictQualityIsActive {
                playbackErrorMessage = "Cannot play in HDR/DV without downgrade."
            }
            return false
        }
        isRecoveryInProgress = true
        defer { isRecoveryInProgress = false }
        recoveryAttemptCount += 1

        let attempt = recoveryAttemptCount
        if let action = plannedFallbackAction(for: attempt) {
            AppLog.playback.notice("Plan fallback step #\(attempt, privacy: .public): \(action.rawValue, privacy: .public)")
        }
        let elapsed = Date().timeIntervalSince(startDate) * 1000
        AppLog.playback.warning(
            "playback.fallback.triggered — attempt=\(attempt, privacy: .public) reason=\(reason, privacy: .public) fromProfile=\(self.activeTranscodeProfile.rawValue, privacy: .public) elapsedMs=\(elapsed, format: .fixed(precision: 1)) maxAttempts=\(self.maxRecoveryAttempts, privacy: .public)"
        )
        fallbackOccurred = true
        fallbackReason = reason
        _ = userMessage
        playbackErrorMessage = nil

        if retryDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            guard player.currentItem != nil else { return false }
        }

        return await reloadRecoveryTranscode(reason: reason, attempt: attempt)
    }

    private func handlePlaybackFailure(message: String, error: NSError?) async -> Bool {
        if isLocalSyntheticHLSTransportFailure(error) {
            return await attemptLocalSyntheticHLSRecovery(
                reason: "local_hls_transport_failure",
                userMessage: "Local HLS transport failed. Restarting NativeBridge delivery."
            )
        }

        if isLocalSyntheticHLSParseFailure(error) {
            if let itemID = currentItemID {
                NativeBridgeFailureCache.recordFailure(itemID: itemID)
                AppLog.nativeBridge.error("[NB-DIAG] hls.parse.failure — disabling NativeBridge for item=\(itemID, privacy: .public)")
            }
            return await attemptRecovery(
                reason: "nativebridge_packaging_failure",
                userMessage: "NativeBridge packaging failed. Switching to compatibility playback."
            )
        }

        if isTransientPlaybackFailure(error), recoveryAttemptCount < maxRecoveryAttempts {
            // 500ms, then 1000ms
            let delay = UInt64(500_000_000 * (recoveryAttemptCount + 1))
            return await attemptRecovery(
                reason: "player_item_failed_transient",
                userMessage: "Network hiccup detected. Retrying playback…",
                retryDelayNanoseconds: delay
            )
        }

        if recoveryAttemptCount < maxRecoveryAttempts {
            return await attemptRecovery(
                reason: "player_item_failed",
                userMessage: "Primary stream failed. Trying compatibility stream."
            )
        }

        AppLog.playback.error("Recovery budget exhausted. Last error: \(message, privacy: .public)")
        if playMethodForReporting == "NativeBridge", let itemID = currentItemID {
            NativeBridgeFailureCache.recordFailure(itemID: itemID)
            AppLog.nativeBridge.notice("Native Bridge temporarily disabled for item \(itemID, privacy: .public)")
        }
        if strictQualityIsActive {
            playbackErrorMessage = "Cannot play in HDR/DV without downgrade."
        }
        return false
    }

    private func attemptLocalSyntheticHLSRecovery(reason: String, userMessage: String) async -> Bool {
        if isRecoveryInProgress {
            return true
        }
        guard recoveryAttemptCount < maxRecoveryAttempts else {
            return false
        }
        guard let itemID = currentItemID else {
            return false
        }

        isRecoveryInProgress = true
        defer { isRecoveryInProgress = false }
        recoveryAttemptCount += 1

        let attempt = recoveryAttemptCount
        let resumeSeconds: Double? = hasMarkedFirstFrame ? max(0, player.currentTime().seconds) : nil
        AppLog.nativeBridge.warning("[NB-DIAG] hls.server.recovery.start — attempt=\(attempt, privacy: .public) reason=\(reason, privacy: .public)")
        fallbackOccurred = true
        fallbackReason = reason
        _ = userMessage

        do {
            var selection = try await coordinator.resolvePlayback(
                itemID: itemID,
                mode: .balanced,
                allowTranscodingFallbackInPerformance: true,
                transcodeProfile: activeTranscodeProfile
            )
            guard case let .nativeBridge(plan) = selection.decision.route else {
                AppLog.nativeBridge.error("[NB-DIAG] hls.server.recovery.abort — fallback_route_not_nativebridge")
                return false
            }

            await nativeBridgeSession?.invalidate()
            nativeBridgeSession = nil
            syntheticHLSSession = nil
            localHLSServer?.stop(reason: "local_transport_recovery_attempt_\(attempt)")
            localHLSServer = nil
            localHLSStartupSummary = nil

            let localURL = try await prepareSyntheticLocalHLS(plan: plan)
            selection.assetURL = localURL
            selection.headers = [:]

            if !registerAttempt(selection: selection, profile: activeTranscodeProfile) {
                AppLog.nativeBridge.warning("[NB-DIAG] hls.server.recovery.duplicate-attempt")
                return false
            }

            prepareAndLoadSelection(selection, resumeSeconds: resumeSeconds)
            routeDescription = "Recovery #\(attempt): NativeBridge [local-hls-restart]"
            playbackErrorMessage = nil
            player.play()
            scheduleDecodedFrameWatchdog()
            scheduleStartupWatchdog()

            AppLog.nativeBridge.notice("[NB-DIAG] hls.server.recovery.success — attempt=\(attempt, privacy: .public)")
            return true
        } catch {
            AppLog.nativeBridge.error("[NB-DIAG] hls.server.recovery.failed — attempt=\(attempt, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func isTransientPlaybackFailure(_ error: NSError?) -> Bool {
        guard let error else { return false }

        if error.domain == NSURLErrorDomain {
            let transient: Set<Int> = [
                NSURLErrorResourceUnavailable,
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorInternationalRoamingOff,
                NSURLErrorCallIsActive,
                NSURLErrorDataNotAllowed
            ]
            return transient.contains(error.code)
        }

        if error.domain == AVFoundationErrorDomain {
            let transient: Set<Int> = [
                AVError.serverIncorrectlyConfigured.rawValue,
                AVError.contentIsUnavailable.rawValue,
                AVError.mediaServicesWereReset.rawValue,
                -11863 // Resource unavailable (not exposed on all SDKs as AVError case)
            ]
            return transient.contains(error.code)
        }

        return false
    }

    private func isLocalSyntheticHLSTransportFailure(_ error: NSError?) -> Bool {
        guard playMethodForReporting == "NativeBridge" else { return false }
        guard let url = (player.currentItem?.asset as? AVURLAsset)?.url, isLocalSyntheticHLSURL(url) else {
            return false
        }

        guard let error else { return false }

        if error.domain == NSURLErrorDomain {
            let transportCodes: Set<Int> = [
                NSURLErrorCannotConnectToHost,
                NSURLErrorTimedOut,
                NSURLErrorResourceUnavailable,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotFindHost
            ]
            return transportCodes.contains(error.code)
        }

        if error.domain == AVFoundationErrorDomain {
            let transportLikeCodes: Set<Int> = [
                AVError.serverIncorrectlyConfigured.rawValue,
                AVError.contentIsUnavailable.rawValue,
                -11828, // Cannot Open
                -11863  // Resource unavailable
            ]
            return transportLikeCodes.contains(error.code)
        }

        return false
    }

    private func isLocalSyntheticHLSParseFailure(_ error: NSError?) -> Bool {
        guard playMethodForReporting == "NativeBridge" else { return false }
        guard let url = (player.currentItem?.asset as? AVURLAsset)?.url, isLocalSyntheticHLSURL(url) else {
            return false
        }
        guard let error else { return false }

        if error.domain == "CoreMediaErrorDomain" {
            return true
        }

        if error.domain == AVFoundationErrorDomain {
            let parseCodes: Set<Int> = [
                AVError.failedToParse.rawValue,
                AVError.decoderNotFound.rawValue,
                AVError.fileFormatNotRecognized.rawValue,
                -11828 // Cannot Open
            ]
            return parseCodes.contains(error.code)
        }
        return false
    }

    private func preflightSelection(_ selection: PlaybackAssetSelection) async -> Bool {
        guard case .transcode = selection.decision.route else { return true }

        do {
            let firstManifest = try await fetchPlaylist(
                url: selection.assetURL,
                headers: selection.headers
            )
            guard
                let firstLine = firstMediaLine(in: firstManifest),
                let firstURL = resolveSegmentURL(
                    firstSegmentLine: firstLine,
                    masterURL: selection.assetURL
                )
            else {
                AppLog.playback.warning("Preflight failed: no playable line in master playlist.")
                return false
            }

            let probeURL: URL
            if firstURL.pathExtension.lowercased() == "m3u8" {
                let childManifest = try await fetchPlaylist(
                    url: firstURL,
                    headers: selection.headers
                )
                guard
                    let childLine = firstMediaLine(in: childManifest),
                    let childURL = resolveSegmentURL(
                        firstSegmentLine: childLine,
                        masterURL: firstURL
                    )
                else {
                    AppLog.playback.warning("Preflight failed: no segment in child playlist.")
                    return false
                }
                probeURL = childURL
            } else {
                probeURL = firstURL
            }

            var segmentData = Data()
            var segmentHTTP: HTTPURLResponse?
            for attempt in 0 ..< 2 {
                let segmentRequest = makeProbeRequest(
                    url: probeURL,
                    headers: selection.headers,
                    range: "bytes=0-2047"
                )
                let (data, response) = try await URLSession.shared.data(for: segmentRequest)
                guard let http = response as? HTTPURLResponse else {
                    return false
                }

                if (200 ..< 300).contains(http.statusCode) || http.statusCode == 206 {
                    segmentData = data
                    segmentHTTP = http
                    break
                }

                if attempt == 0, (500 ... 504).contains(http.statusCode) {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                return false
            }

            guard let segmentHTTP else {
                return false
            }

            let contentType = (segmentHTTP.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if contentType.contains("text/") || contentType.contains("json") || contentType.contains("application/problem") {
                return false
            }

            if let prefix = String(data: segmentData.prefix(128), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                prefix.contains("error processing request") {
                return false
            }

            return !segmentData.isEmpty
        } catch {
            AppLog.playback.warning("Preflight failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func shouldForceCompatibilityH264(for selection: PlaybackAssetSelection) async -> Bool {
        guard case .transcode = selection.decision.route else { return false }
        guard activeTranscodeProfile != .forceH264Transcode else { return false }

        let query = transcodeQueryMap(from: selection.assetURL)
        let codec = query["videocodec"] ?? selection.source.normalizedVideoCodec
        let isHEVCTranscode = isHEVCCodec(codec) && query["allowvideostreamcopy"] == "false"
        guard isHEVCTranscode else { return false }

        let sourceLikelyHighQuality = (selection.source.bitrate ?? 0) >= 15_000_000 || (selection.source.videoBitDepth ?? 8) >= 10
        guard sourceLikelyHighQuality else { return false }

        do {
            let manifest = try await fetchPlaylist(url: selection.assetURL, headers: selection.headers)
            guard let streamInfLine = manifest.split(whereSeparator: \.isNewline).map(String.init).first(where: {
                $0.hasPrefix("#EXT-X-STREAM-INF:")
            }) else {
                return false
            }

            let bandwidth = parseIntAttribute("BANDWIDTH", from: streamInfLine)
            let (width, _) = parseResolution(from: streamInfLine)
            let isDegradedBandwidth = bandwidth > 0 && bandwidth < 2_000_000
            let isLowResolutionVariant = width > 0 && width < 960

            return isDegradedBandwidth || isLowResolutionVariant
        } catch {
            return false
        }
    }

    private func shouldPreemptivelyFallbackToH264(
        for selection: PlaybackAssetSelection,
        itemPrefersDolbyVision: Bool
    ) async -> Bool {
        guard case .transcode = selection.decision.route else { return false }
        guard activeTranscodeProfile != .forceH264Transcode else { return false }

        let query = transcodeQueryMap(from: selection.assetURL)
        let transport = selectedVariantInfo.map {
            StreamVariantInspector.inferTransport(from: $0, playlist: selectedVariantPlaylistInspection)
        } ?? selectedVariantPlaylistInspection?.transport ?? "TS"
        let hasInitMap = selectedVariantPlaylistInspection?.mapURL != nil
        let codec = selectedVariantInfo?.normalizedCodec
            ?? query["videocodec"]
            ?? selection.source.normalizedVideoCodec
        let allowAudioCopy = query["allowaudiostreamcopy"] == "true"

        if Self.shouldPreferForceH264Fallback(
            transport: transport,
            hasInitMap: hasInitMap,
            source: selection.source,
            allowSDRFallback: allowSDRFallback,
            itemPrefersDolbyVision: itemPrefersDolbyVision,
            strictQualityMode: strictQualityIsActive,
            videoCodec: codec,
            allowAudioStreamCopy: allowAudioCopy
        ) {
            AppLog.playback.notice(
                "Preemptive profile upgrade profile=\(self.activeTranscodeProfile.rawValue, privacy: .public)->forceH264Transcode reason=unsafe_hevc_startup_packaging"
            )
            return true
        }

        if await shouldForceCompatibilityH264(for: selection) {
            AppLog.playback.notice(
                "Preemptive profile upgrade profile=\(self.activeTranscodeProfile.rawValue, privacy: .public)->forceH264Transcode reason=degraded_hevc_variant"
            )
            return true
        }

        return false
    }

    private func parseIntAttribute(_ name: String, from streamInfLine: String) -> Int {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))=([0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(streamInfLine.startIndex..<streamInfLine.endIndex, in: streamInfLine)
        guard
            let match = regex.firstMatch(in: streamInfLine, options: [], range: range),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: streamInfLine)
        else {
            return 0
        }
        return Int(streamInfLine[valueRange]) ?? 0
    }

    private func parseResolution(from streamInfLine: String) -> (Int, Int) {
        let pattern = "RESOLUTION=([0-9]+)x([0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (0, 0) }
        let range = NSRange(streamInfLine.startIndex..<streamInfLine.endIndex, in: streamInfLine)
        guard
            let match = regex.firstMatch(in: streamInfLine, options: [], range: range),
            match.numberOfRanges > 2,
            let widthRange = Range(match.range(at: 1), in: streamInfLine),
            let heightRange = Range(match.range(at: 2), in: streamInfLine)
        else {
            return (0, 0)
        }
        let width = Int(streamInfLine[widthRange]) ?? 0
        let height = Int(streamInfLine[heightRange]) ?? 0
        return (width, height)
    }

    private func fetchPlaylist(url: URL, headers: [String: String]) async throws -> String {
        AppLog.playback.notice("Loading HLS playlist url=\(url.absoluteString, privacy: .public)")
        let request = makeProbeRequest(url: url, headers: headers, range: nil)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw AppError.network("Playlist request failed.")
        }

        guard let manifest = String(data: data, encoding: .utf8), manifest.contains("#EXTM3U") else {
            throw AppError.network("Invalid HLS playlist.")
        }
        AppLog.playback.notice("Loaded HLS playlist url=\(url.absoluteString, privacy: .public) status=\(http.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)")
        return manifest
    }

    private func fetchInitSegmentData(url: URL, headers: [String: String]) async throws -> Data {
        AppLog.playback.notice("Loading HLS init segment url=\(url.absoluteString, privacy: .public)")
        let request = makeProbeRequest(url: url, headers: headers, range: "bytes=0-524287")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) || http.statusCode == 206 else {
            throw AppError.network("Failed to fetch init segment.")
        }
        guard !data.isEmpty else {
            throw AppError.network("Init segment is empty.")
        }
        AppLog.playback.notice("Loaded HLS init segment url=\(url.absoluteString, privacy: .public) status=\(http.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)")
        return data
    }

    private func effectiveVideoMode(
        source: MediaSource,
        variant: HLSVariantInfo,
        initInspection: InitSegmentInspection
    ) -> EffectivePlaybackVideoMode {
        if (source.dvProfile ?? 0) > 0,
           (initInspection.hasDvcC || initInspection.hasDvvC),
           variant.isDolbyVisionSignaled {
            return .dolbyVision
        }

        if initInspection.hasHvcC, variant.isHDRSignaled {
            return .hdr10
        }

        if variant.isSDR {
            return .sdr
        }

        if source.isLikelyHDRorDV, initInspection.hasHvcC {
            return .hdr10
        }

        return .unknown
    }

    private func firstMediaLine(in manifest: String) -> String? {
        manifest
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.isEmpty && !$0.hasPrefix("#") })
    }

    private func makeProbeRequest(url: URL, headers: [String: String], range: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/vnd.apple.mpegurl,application/x-mpegURL,*/*", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let range {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        return request
    }

    private func resolveSegmentURL(firstSegmentLine: String, masterURL: URL) -> URL? {
        if let absolute = URL(string: firstSegmentLine), absolute.scheme != nil {
            return absolute
        }

        guard let resolved = URL(string: firstSegmentLine, relativeTo: masterURL)?.absoluteURL else {
            return nil
        }

        guard
            let masterComponents = URLComponents(url: masterURL, resolvingAgainstBaseURL: false),
            let apiKey = masterComponents.queryItems?.first(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame })?.value
        else {
            return resolved
        }

        guard var segmentComponents = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else {
            return resolved
        }

        var queryItems = segmentComponents.queryItems ?? []
        if !queryItems.contains(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame }) {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
            segmentComponents.queryItems = queryItems
        }
        return segmentComponents.url ?? resolved
    }

    private func isLocalSyntheticHLSURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        guard let host = url.host?.lowercased(), let port = url.port else { return false }
        guard port > 0 else { return false }
        guard host == "127.0.0.1" || host == "localhost" else { return false }
        return url.pathExtension.lowercased() == "m3u8"
    }

    private func currentPlaybackConfiguration() async -> (
        playbackPolicy: PlaybackPolicy,
        allowSDRFallback: Bool,
        preferAudioTranscodeOnly: Bool,
        preferredAudioLanguage: String?,
        preferredSubtitleLanguage: String?
    ) {
        guard let configuration = await apiClient.currentConfiguration() else {
            return (.auto, true, true, nil, nil)
        }
        return (
            configuration.playbackPolicy,
            configuration.allowSDRFallback,
            configuration.preferAudioTranscodeOnly,
            configuration.preferredAudioLanguage,
            configuration.preferredSubtitleLanguage
        )
    }

    private func initialProfileForItem(itemID: String, itemHasDolbyVision: Bool) -> TranscodeURLProfile {
        let stored = preferredProfilesByItemID[itemID] ?? .serverDefault
        return Self.initialProfile(
            stored: stored,
            playbackPolicy: playbackPolicy,
            allowSDRFallback: allowSDRFallback,
            itemHasDolbyVision: itemHasDolbyVision
        )
    }

    private func isMKVHEVCSource(_ source: MediaSource) -> Bool {
        let container = source.normalizedContainer
        guard container == "mkv" || container == "matroska" || container == "webm" else { return false }
        let codec = source.normalizedVideoCodec
        return codec.contains("hevc") || codec.contains("h265") || codec.contains("dvhe") || codec.contains("dvh1")
    }

    private func shouldPreferDolbyVisionVariant(itemPrefersDolbyVision: Bool, source: MediaSource) -> Bool {
        guard itemPrefersDolbyVision else { return false }
        // For Profile 8 titles, stay on HDR10 ladders by default.
        // Only prefer DV ladders when user explicitly selected strict HDR/DV lock mode.
        if source.dvProfile == 8 {
            return strictQualityIsActive
        }
        if source.videoRangeType?.lowercased().contains("dovi") == true, source.dvProfile == nil {
            return false
        }
        return true
    }

    private func registerAttempt(selection: PlaybackAssetSelection, profile: TranscodeURLProfile) -> Bool {
        let variantURL = selectedVariantInfo?.resolvedURL.absoluteString ?? selection.assetURL.absoluteString
        let key = Self.attemptTripleKey(
            profile: profile,
            routeLabel: routeLabel(for: selection.decision.route),
            url: variantURL
        )
        let inserted = Self.insertAttemptTriple(key, attempted: &attemptedPlaybackTriples)
        if !inserted {
            AppLog.playback.warning("Skipping duplicate playback attempt \(key, privacy: .public)")
        }
        return inserted
    }

    private func pinPreferredVariantIfNeeded(
        selection: PlaybackAssetSelection,
        itemPrefersDolbyVision: Bool,
        profileOverride: TranscodeURLProfile? = nil
    ) async throws -> PlaybackAssetSelection {
        guard case .transcode = selection.decision.route else {
            selectedVariantInfo = nil
            selectedMasterPlaylistURL = nil
            selectedVariantPlaylistInspection = nil
            selectedInitSegmentInspection = nil
            return selection
        }
        guard selection.assetURL.pathExtension.lowercased() == "m3u8" else {
            selectedVariantInfo = nil
            selectedMasterPlaylistURL = nil
            selectedVariantPlaylistInspection = nil
            selectedInitSegmentInspection = nil
            return selection
        }

        let variantSelectionProfile = profileOverride ?? activeTranscodeProfile

        do {
            selectedMasterPlaylistURL = selection.assetURL
            let manifest = try await fetchPlaylist(url: selection.assetURL, headers: selection.headers)
            let variants = HLSVariantSelector.parseVariants(manifest: manifest, masterURL: selection.assetURL)
            guard !variants.isEmpty else {
                selectedVariantInfo = nil
                return selection
            }
            for variant in variants {
                AppLog.playback.notice(
                    "HLS variant candidate url=\(variant.resolvedURL.absoluteString, privacy: .public) \(variant.loggingSummary, privacy: .public)"
                )
            }

            guard let preferred = HLSVariantSelector.preferredVariant(
                from: variants,
                playbackPolicy: playbackPolicy,
                activeProfile: variantSelectionProfile,
                source: selection.source,
                itemPrefersDolbyVision: itemPrefersDolbyVision,
                allowSDRFallback: allowSDRFallback,
                strictQualityMode: strictQualityIsActive
            ) else {
                if strictQualityIsActive {
                    throw AppError.network("Cannot play in HDR/DV without downgrade.")
                }
                selectedVariantInfo = nil
                return selection
            }

            if strictQualityIsActive, selection.source.isLikelyHDRorDV, preferred.isSDR {
                throw AppError.network(PlaybackFailureReason.strictModeRejectedSDRVariant.localizedDescription ?? "Strict mode rejected SDR variant.")
            }

            if strictQualityIsActive, selection.source.isLikelyHDRorDV, !preferred.usesFMP4Transport {
                throw AppError.network(PlaybackFailureReason.strictModeRequiresFMP4Transport.localizedDescription ?? "Strict mode requires fMP4 transport.")
            }

            if strictQualityIsActive, selection.source.isLikelyHDRorDV, preferred.isH264 {
                throw AppError.network(PlaybackFailureReason.strictModeBlockedDestructiveTranscode.localizedDescription ?? "Strict mode blocked destructive transcode.")
            }

            selectedVariantInfo = preferred
            var updated = selection
            updated.assetURL = preferred.resolvedURL
            AppLog.playback.info(
                    "Pinned HLS variant bandwidth=\(preferred.bandwidth, privacy: .public) resolution=\(preferred.width, privacy: .public)x\(preferred.height, privacy: .public) codec=\(preferred.normalizedCodec, privacy: .public) codecs=\(preferred.codecs, privacy: .public) supplemental=\(preferred.supplementalCodecs, privacy: .public) videoRange=\(preferred.videoRange, privacy: .public) allowVideoCopy=\(String(describing: preferred.allowsVideoCopy), privacy: .public)"
            )

            let variantManifest = try await fetchPlaylist(url: preferred.resolvedURL, headers: selection.headers)
            let variantInspection = StreamVariantInspector.inspectVariantPlaylist(
                manifest: variantManifest,
                variantURL: preferred.resolvedURL
            )
            selectedVariantPlaylistInspection = variantInspection
            let transport = StreamVariantInspector.inferTransport(from: preferred, playlist: variantInspection)
            AppLog.playback.notice(
                "HLS selected variant url=\(preferred.resolvedURL.absoluteString, privacy: .public) transport=\(transport, privacy: .public) map=\(variantInspection.mapURI ?? "none", privacy: .public) firstSegment=\(variantInspection.firstSegmentURI ?? "none", privacy: .public)"
            )

            if strictQualityIsActive, selection.source.isLikelyHDRorDV, transport != "fMP4" {
                throw AppError.network(PlaybackFailureReason.strictModeRequiresFMP4Transport.localizedDescription ?? "Strict mode requires fMP4 transport.")
            }

            if let mapURL = variantInspection.mapURL {
                let initData = try await fetchInitSegmentData(url: mapURL, headers: selection.headers)
                let initInspection = InitSegmentInspector.inspect(initData)
                selectedInitSegmentInspection = initInspection
                let effectiveMode = effectiveVideoMode(
                    source: selection.source,
                    variant: preferred,
                    initInspection: initInspection
                )
                AppLog.playback.notice(
                    "Init segment inspection hvcC=\(initInspection.hasHvcC, privacy: .public) dvcC=\(initInspection.hasDvcC, privacy: .public) dvvC=\(initInspection.hasDvvC, privacy: .public) effectiveMode=\(effectiveMode.rawValue, privacy: .public)"
                )

                if strictQualityIsActive, selection.source.isLikelyHDRorDV, effectiveMode == .sdr || effectiveMode == .unknown {
                    throw AppError.network(PlaybackFailureReason.strictModeNoHDRCapablePath.localizedDescription ?? "No HDR-capable path available.")
                }

                if (selection.source.dvProfile ?? 0) > 0, effectiveMode == .hdr10, !(initInspection.hasDvcC || initInspection.hasDvvC) {
                    AppLog.playback.notice(
                        "\(PlaybackFailureReason.missingDolbyVisionBoxesFallingBackToHDR10.localizedDescription ?? "DV metadata missing, HDR10 fallback.", privacy: .public)"
                    )
                }
            } else {
                selectedInitSegmentInspection = nil
                if strictQualityIsActive, selection.source.isLikelyHDRorDV {
                    throw AppError.network(PlaybackFailureReason.strictModeNoHDRCapablePath.localizedDescription ?? "No HDR-capable path available.")
                }
            }
            return updated
        } catch {
            if strictQualityIsActive {
                throw error
            }
            AppLog.playback.warning("Variant pinning skipped: \(error.localizedDescription, privacy: .public)")
            selectedVariantInfo = nil
            return selection
        }
    }

    private func reloadRecoveryTranscode(reason: String, attempt: Int) async -> Bool {
        let resumeSeconds: Double? = hasMarkedFirstFrame ? max(0, player.currentTime().seconds) : nil
        guard let itemID = currentItemID else { return false }

        if playMethodForReporting == "NativeBridge" || reason == "nativebridge_packaging_failure" {
            NativeBridgeFailureCache.recordFailure(itemID: itemID)
            await nativeBridgeSession?.invalidate()
            nativeBridgeSession = nil
            syntheticHLSSession = nil
            localHLSServer?.stop(reason: "switch_to_non_nativebridge_recovery")
            localHLSServer = nil
            localHLSStartupSummary = nil
        }

        let mode: PlaybackMode = usesDirectRemuxOnly ? .performance : .balanced
        let allowTranscodingFallback = !usesDirectRemuxOnly

        var lastError: Error?
        for profile in recoveryProfiles(for: reason, attempt: attempt) {
            do {
                var selection = try await coordinator.resolvePlayback(
                    itemID: itemID,
                    mode: mode,
                    allowTranscodingFallbackInPerformance: allowTranscodingFallback,
                    transcodeProfile: profile
                )

                if case let .nativeBridge(plan) = selection.decision.route {
                    AppLog.nativeBridge.notice(
                        "[NB-DIAG] recovery.nativebridge.reprepare — reason=\(reason, privacy: .public) attempt=\(attempt, privacy: .public)"
                    )
                    if Self.prefersLocalSyntheticHLS {
                        let localURL = try await prepareSyntheticLocalHLS(plan: plan)
                        selection.assetURL = localURL
                        selection.headers = [:]
                        nativeBridgeSession = nil
                    } else {
                        let session = NativeBridgeSession(plan: plan, token: await apiClient.currentSession()?.token)
                        try await session.prepare()
                        nativeBridgeSession = session
                        syntheticHLSSession = nil
                        localHLSServer?.stop(reason: "recovery_switch_to_resource_loader")
                        localHLSServer = nil
                        localHLSStartupSummary = nil
                    }
                }

                selection = try await pinPreferredVariantIfNeeded(
                    selection: selection,
                    itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                        itemPrefersDolbyVision: currentItemHasDolbyVision || (currentSource?.isLikelyHDRorDV ?? false),
                        source: selection.source
                    )
                )
                selection = try await stabilizeInitialSelectionIfNeeded(
                    itemID: itemID,
                    selection: selection,
                    itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                        itemPrefersDolbyVision: currentItemHasDolbyVision || (currentSource?.isLikelyHDRorDV ?? false),
                        source: selection.source
                    )
                )

                if !registerAttempt(selection: selection, profile: profile) {
                    continue
                }

                if case .transcode = selection.decision.route, !(await preflightSelection(selection)) {
                    AppLog.playback.warning(
                        "Recovery preflight failed for profile=\(profile.rawValue, privacy: .public). Continuing load."
                    )
                }

                activeTranscodeProfile = profile
                prepareAndLoadSelection(selection, resumeSeconds: resumeSeconds)
                routeDescription = "Recovery #\(attempt): \(routeLabel(for: selection.decision.route)) [\(profile.rawValue)]"
                playbackErrorMessage = nil
                player.play()
                scheduleDecodedFrameWatchdog()
                scheduleStartupWatchdog()
                return true
            } catch {
                lastError = error
                AppLog.playback.warning(
                    "Recovery candidate failed profile=\(profile.rawValue, privacy: .public) reason=\(reason, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        if let lastError {
            playbackErrorMessage = lastError.localizedDescription
            AppLog.playback.error("Recovery playback failed (reason=\(reason, privacy: .public)): \(lastError.localizedDescription, privacy: .public)")
        } else if strictQualityIsActive {
            playbackErrorMessage = "Cannot play in HDR/DV without downgrade."
        }
        return false
    }

    private func recoveryProfiles(for reason: String, attempt: Int) -> [TranscodeURLProfile] {
        _ = attempt
        if usesDirectRemuxOnly {
            return [.serverDefault]
        }

        let failureReason = StartupFailureReason(rawValue: reason)
        let baseProfiles: [TranscodeURLProfile]

        switch failureReason {
        case .readyButNoVideoFrame, .decoderStall, .presentationSizeZero:
            // Video decode failure on HEVC: skip to H264 directly when allowed
            if (activeTranscodeProfile == .appleOptimizedHEVC || activeTranscodeProfile == .serverDefault),
               allowSDRFallback {
                baseProfiles = [.forceH264Transcode]
            } else {
                baseProfiles = startupRecoveryProfiles(after: activeTranscodeProfile)
            }
        default:
            baseProfiles = startupRecoveryProfiles(after: activeTranscodeProfile)
        }

        AppLog.playback.notice(
            "playback.fallback.profiles — reason=\(reason, privacy: .public) active=\(self.activeTranscodeProfile.rawValue, privacy: .public) candidates=\(baseProfiles.map(\.rawValue).joined(separator: ","), privacy: .public)"
        )

        return deduplicatedProfiles(baseProfiles)
    }

    private func deduplicatedProfiles(_ profiles: [TranscodeURLProfile]) -> [TranscodeURLProfile] {
        var seen = Set<TranscodeURLProfile>()
        return profiles.filter { seen.insert($0).inserted }
    }

    private func startupRecoveryProfiles(after activeProfile: TranscodeURLProfile) -> [TranscodeURLProfile] {
        Self.recoveryPlan(after: activeProfile, policy: playbackPolicy, allowSDRFallback: allowSDRFallback)
    }

    private func refreshDecodedVideoFrameState() {
        guard !hasDecodedVideoFrame else { return }
        guard let item = player.currentItem else { return }

        if let output = videoOutput {
            let itemTime = item.currentTime()
            if output.hasNewPixelBuffer(forItemTime: itemTime) {
                var presentationTime = CMTime.zero
                if let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &presentationTime) {
                    hasDecodedVideoFrame = true
                    updateHDRModeFromPixelBuffer(pixelBuffer)
                    updatePlaybackProof(from: item)
                    return
                }
            }
        }

        let size = item.presentationSize
        if size.width > 2 && size.height > 2 {
            hasDecodedVideoFrame = true
            updatePlaybackProof(from: item)
        }
    }

    private func startVideoOutputPolling(for item: AVPlayerItem) {
        videoOutputPollTask?.cancel()
        videoOutputPollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard self.player.currentItem === item else { return }
                self.refreshDecodedVideoFrameState()
                if self.hasDecodedVideoFrame { return }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func updateHDRModeFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        let primaries = CVBufferGetAttachment(
            pixelBuffer,
            kCVImageBufferColorPrimariesKey,
            nil
        )?.takeUnretainedValue() as? String
        let transfer = CVBufferGetAttachment(
            pixelBuffer,
            kCVImageBufferTransferFunctionKey,
            nil
        )?.takeUnretainedValue() as? String

        let p = (primaries ?? "").lowercased()
        let t = (transfer ?? "").lowercased()
        if t.contains("pq") || p.contains("2020") {
            if runtimeHDRMode == .unknown || runtimeHDRMode == .sdr {
                runtimeHDRMode = .hdr10
            }
        }
    }

    private func isRiskyServerDefaultHEVCTranscode(item: AVPlayerItem) -> Bool {
        guard activeTranscodeProfile == .serverDefault else { return false }
        guard playMethodForReporting == "Transcode" else { return false }
        guard let url = (item.asset as? AVURLAsset)?.url else { return false }

        let query = transcodeQueryMap(from: url)
        guard query["allowvideostreamcopy"] == "true" else { return false }

        let codec = query["videocodec"] ?? currentSource?.normalizedVideoCodec
        return isHEVCCodec(codec)
    }

    private func shouldUpgradeInitialTranscodeProfile(_ selection: PlaybackAssetSelection) -> Bool {
        guard case .transcode = selection.decision.route else { return false }
        guard activeTranscodeProfile == .serverDefault else { return false }
        guard !usesDirectRemuxOnly else { return false }

        let query = transcodeQueryMap(from: selection.assetURL)
        guard query["allowvideostreamcopy"] == "true" else { return false }

        let codec = query["videocodec"] ?? selection.source.normalizedVideoCodec
        guard isHEVCCodec(codec) else { return false }

        let container = selection.source.normalizedContainer
        let isMKVFamily = container == "mkv" || container == "matroska" || container == "webm"
        return isMKVFamily || selection.source.isPremiumVideoSource
    }

    private func upgradeRiskyInitialSelectionIfNeeded(
        itemID: String,
        selection: PlaybackAssetSelection,
        itemPrefersDolbyVision: Bool
    ) async throws -> PlaybackAssetSelection {
        guard shouldUpgradeInitialTranscodeProfile(selection) else { return selection }

        let saferProfile = startupFallbackProfile(from: selection.source, itemPrefersDolbyVision: itemPrefersDolbyVision)
        guard saferProfile != activeTranscodeProfile else { return selection }
        let reason = saferProfile == .forceH264Transcode
            ? "api_metadata_dovi_mkv_fast_start"
            : "risky_hevc_stream_copy_startup"
        AppLog.playback.notice(
            "Preemptive profile upgrade profile=\(self.activeTranscodeProfile.rawValue, privacy: .public)->\(saferProfile.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
        )

        var upgraded = try await coordinator.resolvePlayback(
            itemID: itemID,
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: saferProfile
        )
        upgraded = try await pinPreferredVariantIfNeeded(
            selection: upgraded,
            itemPrefersDolbyVision: itemPrefersDolbyVision,
            profileOverride: saferProfile
        )
        activeTranscodeProfile = saferProfile
        return upgraded
    }

    private func stabilizeInitialSelectionIfNeeded(
        itemID: String,
        selection: PlaybackAssetSelection,
        itemPrefersDolbyVision: Bool
    ) async throws -> PlaybackAssetSelection {
        guard await shouldPreemptivelyFallbackToH264(
            for: selection,
            itemPrefersDolbyVision: itemPrefersDolbyVision
        ) else {
            return selection
        }

        var upgraded = try await coordinator.resolvePlayback(
            itemID: itemID,
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .forceH264Transcode
        )
        upgraded = try await pinPreferredVariantIfNeeded(
            selection: upgraded,
            itemPrefersDolbyVision: itemPrefersDolbyVision,
            profileOverride: .forceH264Transcode
        )
        activeTranscodeProfile = .forceH264Transcode
        return upgraded
    }

    private func startupFallbackProfile(from source: MediaSource, itemPrefersDolbyVision: Bool) -> TranscodeURLProfile {
        if shouldPreferForceH264FastStart(from: source, itemPrefersDolbyVision: itemPrefersDolbyVision) {
            return .forceH264Transcode
        }
        return .appleOptimizedHEVC
    }

    private func shouldPreferForceH264FastStart(from source: MediaSource, itemPrefersDolbyVision: Bool) -> Bool {
        guard playbackPolicy == .auto, allowSDRFallback else { return false }

        let container = source.normalizedContainer
        let mkvLike = container == "mkv" || container == "matroska" || container == "webm"
        guard mkvLike else { return false }

        let codec = source.normalizedVideoCodec
        let hevcLike = codec.contains("hevc") || codec.contains("h265") || codec.contains("dvhe") || codec.contains("dvh1")
        guard hevcLike else { return false }

        let likelyDV = itemPrefersDolbyVision
            || (source.dvProfile ?? 0) > 0
            || (source.videoRangeType?.lowercased().contains("dovi") ?? false)
            || (source.videoRange?.lowercased().contains("dolby") ?? false)
        let tenBitOrHDR = (source.videoBitDepth ?? 8) >= 10 || source.isLikelyHDRorDV
        let highRes = (source.videoWidth ?? 0) >= 3000 || (source.videoHeight ?? 0) >= 1600
        let audioLikelyNeedsTranscode = {
            let audio = source.normalizedAudioCodec
            return audio.contains("truehd") || audio.contains("eac3")
        }()

        // If user/title prefers Dolby Vision, keep HEVC path first; do not force AVC.
        if likelyDV {
            return false
        }

        // This profile family is the one that repeatedly stalls on iOS AVPlayer startup.
        return tenBitOrHDR && highRes && audioLikelyNeedsTranscode
    }

    private func videoValidationDelayNanoseconds() -> UInt64 {
        switch activeTranscodeProfile {
        case .serverDefault:
            return isCurrentHEVCStreamCopyTranscode() ? 3_000_000_000 : 6_000_000_000
        case .appleOptimizedHEVC:
            return 6_000_000_000
        case .conservativeCompatibility:
            return 6_000_000_000
        case .forceH264Transcode:
            return 4_000_000_000
        }
    }

    private func isCurrentHEVCStreamCopyTranscode() -> Bool {
        guard playMethodForReporting == "Transcode" else { return false }
        guard let url = (player.currentItem?.asset as? AVURLAsset)?.url else { return false }
        let query = transcodeQueryMap(from: url)
        guard query["allowvideostreamcopy"] == "true" else { return false }
        let codec = query["videocodec"] ?? currentSource?.normalizedVideoCodec
        return isHEVCCodec(codec)
    }

    private func shouldDeferResumeSeek(route: PlaybackRoute, seconds: Double) -> Bool {
        guard seconds > 0 else { return false }
        switch route {
        case .transcode, .remux, .nativeBridge:
            return true
        case .directPlay:
            return false
        }
    }

    private func applyDeferredResumeSeekIfNeeded() {
        guard let seconds = pendingResumeSeconds, seconds > 0 else { return }
        pendingResumeSeconds = nil

        let current = player.currentTime().seconds
        if current.isFinite, abs(current - seconds) < 3 {
            return
        }

        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance)
        AppLog.playback.info("Deferred resume seek applied at \(seconds, format: .fixed(precision: 3))s after first frame.")
    }

    private func transcodeQueryMap(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }

        var map: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            map[item.name.lowercased()] = value.lowercased()
        }
        return map
    }

    private func isHEVCCodec(_ codec: String?) -> Bool {
        guard let codec else { return false }
        return codec.contains("hevc")
            || codec.contains("h265")
            || codec.contains("dvhe")
            || codec.contains("dvh1")
    }

    private func rememberWorkingProfileForCurrentItem() {
        guard playMethodForReporting == "Transcode" else { return }
        guard let itemID = currentItemID else { return }
        guard playbackPolicy == .auto else {
            preferredProfilesByItemID.removeValue(forKey: itemID)
            Self.storePreferredProfiles(preferredProfilesByItemID)
            return
        }

        let profile = inferredTranscodeProfile(
            from: (player.currentItem?.asset as? AVURLAsset)?.url,
            fallback: activeTranscodeProfile
        )

        // Avoid locking Dolby Vision titles into SDR H264 fallback forever.
        if currentItemHasDolbyVision, profile == .forceH264Transcode {
            preferredProfilesByItemID.removeValue(forKey: itemID)
            Self.storePreferredProfiles(preferredProfilesByItemID)
            return
        }

        if profile == .serverDefault {
            preferredProfilesByItemID.removeValue(forKey: itemID)
        } else {
            preferredProfilesByItemID[itemID] = profile
        }
        Self.storePreferredProfiles(preferredProfilesByItemID)
    }

    private func inferredTranscodeProfile(from url: URL?, fallback: TranscodeURLProfile) -> TranscodeURLProfile {
        guard let url else { return fallback }
        let query = transcodeQueryMap(from: url)
        guard !query.isEmpty else { return fallback }

        let allowVideoCopy = query["allowvideostreamcopy"] == "true"
        let codec = query["videocodec"] ?? ""
        if codec == "h264", !allowVideoCopy {
            return .forceH264Transcode
        }
        if codec == "hevc", !allowVideoCopy {
            return .appleOptimizedHEVC
        }
        if allowVideoCopy {
            return fallback == .conservativeCompatibility ? .conservativeCompatibility : .serverDefault
        }
        return fallback
    }

    private static func loadStoredPreferredProfiles() -> [String: TranscodeURLProfile] {
        guard let stored = UserDefaults.standard.dictionary(forKey: preferredProfileStorageKey) as? [String: String] else {
            return [:]
        }

        var map: [String: TranscodeURLProfile] = [:]
        for (itemID, raw) in stored {
            guard let profile = TranscodeURLProfile(rawValue: raw) else { continue }
            map[itemID] = profile
        }
        return map
    }

    private static func storePreferredProfiles(_ map: [String: TranscodeURLProfile]) {
        let serialized = map.mapValues(\.rawValue)
        UserDefaults.standard.set(serialized, forKey: preferredProfileStorageKey)
    }

    private func persistProgress(isPaused: Bool, didFinish: Bool) async {
        guard let snapshot = makeProgressSnapshot(isPaused: isPaused, didFinish: didFinish) else { return }
        await persistProgress(snapshot: snapshot)
    }

    private func makeProgressSnapshot(
        isPaused: Bool,
        didFinish: Bool
    ) -> (local: PlaybackProgress, remote: PlaybackProgressUpdate)? {
        guard let itemID = currentItemID else { return nil }

        let positionSeconds = max(0, player.currentTime().seconds)
        let totalSeconds = max(positionSeconds, player.currentItem?.duration.seconds ?? 0)
        let positionTicks = Int64(positionSeconds * 10_000_000)
        let totalTicks = Int64(totalSeconds * 10_000_000)

        let local = PlaybackProgress(
            itemID: itemID,
            positionTicks: positionTicks,
            totalTicks: totalTicks,
            updatedAt: Date()
        )
        let remote = PlaybackProgressUpdate(
            itemID: itemID,
            positionTicks: positionTicks,
            totalTicks: totalTicks,
            isPaused: isPaused,
            isPlaying: !isPaused,
            didFinish: didFinish,
            playMethod: playMethodForReporting
        )
        return (local, remote)
    }

    private func persistProgress(
        snapshot: (local: PlaybackProgress, remote: PlaybackProgressUpdate)
    ) async {
        if (try? await repository.fetchItem(id: snapshot.local.itemID)) != nil {
            try? await repository.savePlaybackProgress(snapshot.local)
        }
        try? await apiClient.reportPlayback(progress: snapshot.remote)
    }

    private func tearDownCurrentItemObservers() {
        if let periodicObserver {
            player.removeTimeObserver(periodicObserver)
            self.periodicObserver = nil
        }

        [endObserver, stalledObserver, accessLogObserver].forEach {
            if let observer = $0 {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        endObserver = nil
        stalledObserver = nil
        accessLogObserver = nil
        playerItemStatusObserver = nil
    }

    private func routeLabel(for route: PlaybackRoute) -> String {
        switch route {
        case .directPlay:
            return "Direct Play"
        case .nativeBridge:
            return "Direct Play (Native Bridge)"
        case .remux:
            return "Direct Stream"
        case .transcode:
            return "Transcode (HLS)"
        }
    }

    nonisolated static func recoveryPlan(
        after activeProfile: TranscodeURLProfile,
        policy: PlaybackPolicy,
        allowSDRFallback: Bool
    ) -> [TranscodeURLProfile] {
        _ = policy
        let canUseH264Fallback = allowSDRFallback

        switch activeProfile {
        case .serverDefault:
            return canUseH264Fallback ? [.appleOptimizedHEVC, .forceH264Transcode] : [.appleOptimizedHEVC]
        case .appleOptimizedHEVC:
            // Try conservative (stream-copy) before dropping all the way to H264
            return canUseH264Fallback ? [.conservativeCompatibility, .forceH264Transcode] : [.conservativeCompatibility]
        case .conservativeCompatibility:
            return canUseH264Fallback ? [.forceH264Transcode] : []
        case .forceH264Transcode:
            return []
        }
    }

    nonisolated static func initialProfile(
        stored: TranscodeURLProfile,
        playbackPolicy: PlaybackPolicy,
        allowSDRFallback: Bool,
        itemHasDolbyVision: Bool
    ) -> TranscodeURLProfile {
        guard playbackPolicy == .auto else {
            return .serverDefault
        }

        // Do not persist an SDR-only H264 fallback as the default start profile
        // for Dolby Vision titles. Try HEVC optimized first to preserve HDR/DV.
        if itemHasDolbyVision, stored == .forceH264Transcode {
            return .appleOptimizedHEVC
        }

        if stored == .forceH264Transcode, !allowSDRFallback {
            return .serverDefault
        }

        return stored
    }

    nonisolated static func shouldPreferForceH264Fallback(
        transport: String,
        hasInitMap: Bool,
        source: MediaSource,
        allowSDRFallback: Bool,
        itemPrefersDolbyVision: Bool,
        strictQualityMode: Bool,
        videoCodec: String,
        allowAudioStreamCopy: Bool
    ) -> Bool {
        guard allowSDRFallback, !strictQualityMode else { return false }
        guard !itemPrefersDolbyVision, !sourceHasExplicitHDROrDolbyVisionMetadata(source) else { return false }
        guard !allowAudioStreamCopy else { return false }
        guard transport == "fMP4", !hasInitMap else { return false }

        let container = source.normalizedContainer
        let mkvLike = container == "mkv" || container == "matroska" || container == "webm"
        guard mkvLike else { return false }

        let codec = videoCodec.lowercased()
        let hevcLike = codec.contains("hevc")
            || codec.contains("h265")
            || codec.contains("dvhe")
            || codec.contains("dvh1")
            || codec.contains("hvc1")
            || codec.contains("hev1")
        return hevcLike
    }

    nonisolated private static func sourceHasExplicitHDROrDolbyVisionMetadata(_ source: MediaSource) -> Bool {
        let range = (source.videoRange ?? "").lowercased()
        let rangeType = (source.videoRangeType ?? "").lowercased()
        let profile = (source.videoProfile ?? "").lowercased()
        let codec = source.normalizedVideoCodec

        return range.contains("hdr")
            || rangeType.contains("dovi")
            || rangeType.contains("hdr10")
            || rangeType.contains("hlg")
            || range.contains("pq")
            || range.contains("hlg")
            || range.contains("dolby")
            || range.contains("vision")
            || profile.contains("dolby")
            || profile.contains("vision")
            || (source.dvProfile ?? 0) > 0
            || source.hdr10PlusPresentFlag == true
            || codec.contains("dvhe")
            || codec.contains("dvh1")
    }

    nonisolated static func attemptTripleKey(profile: TranscodeURLProfile, routeLabel: String, url: String) -> String {
        "\(profile.rawValue)|\(routeLabel)|\(url)"
    }

    nonisolated static func insertAttemptTriple(_ key: String, attempted: inout Set<String>) -> Bool {
        attempted.insert(key).inserted
    }

    private func updatePlaybackProof(from item: AVPlayerItem) {
        var updated = playbackProof

        let size = item.presentationSize
        if size.width > 1, size.height > 1 {
            updated.decodedResolution = "\(Int(size.width))x\(Int(size.height))"
        }
        updated.playbackMethod = playMethodForReporting

        if let variant = selectedVariantInfo {
            updated.variantResolution = "\(variant.width)x\(variant.height)"
            updated.variantBandwidth = variant.bandwidth
            updated.variantCodecs = variant.codecs
            updated.selectedVariantURL = variant.resolvedURL.absoluteString
            updated.selectedVideoRange = variant.videoRange
            updated.selectedSupplementalCodecs = variant.supplementalCodecs
        }
        updated.selectedMasterPlaylistURL = selectedMasterPlaylistURL?.absoluteString
        updated.strictQualityModeEnabled = strictQualityIsActive
        updated.playerItemStatus = lastPlayerItemStatus
        updated.fallbackOccurred = fallbackOccurred
        updated.fallbackReason = fallbackReason
        updated.failureDomain = lastFailureDomain
        updated.failureCode = lastFailureCode
        updated.failureReason = lastFailureReason
        updated.recoverySuggestion = lastRecoverySuggestion
        updated.initHasHvcC = selectedInitSegmentInspection?.hasHvcC ?? false
        updated.initHasDvcC = selectedInitSegmentInspection?.hasDvcC ?? false
        updated.initHasDvvC = selectedInitSegmentInspection?.hasDvvC ?? false
        updated.inferredEffectiveVideoMode = selectedInitSegmentInspection?.inferredMode.rawValue ?? EffectivePlaybackVideoMode.unknown.rawValue
        if let source = currentSource {
            updated.sourceHDRFlag = source.isLikelyHDRorDV
            updated.sourceDolbyVisionProfile = source.dvProfile
            updated.sourceColorPrimaries = source.colorPrimaries
            updated.sourceColorTransfer = source.colorTransfer
            updated.sourceAudioTrackSelected = availableAudioTracks.first(where: { $0.id == selectedAudioTrackID })?.title
        }
        if let variant = selectedVariantInfo {
            updated.selectedTransport = StreamVariantInspector.inferTransport(from: variant, playlist: selectedVariantPlaylistInspection)
        } else if isLocalSyntheticHLSURL((player.currentItem?.asset as? AVURLAsset)?.url) {
            updated.selectedTransport = "fMP4"
        }

        if let format = firstVideoFormatDescription(in: item) {
            let subtype = fourCCString(from: CMFormatDescriptionGetMediaSubType(format))
            if !subtype.isEmpty {
                updated.codecFourCC = subtype
            }

            if let extensions = CMFormatDescriptionGetExtensions(format) as? [CFString: Any] {
                if let depth = (extensions[kCMFormatDescriptionExtension_Depth] as? NSNumber)?.intValue {
                    updated.bitDepth = depth
                } else if updated.bitDepth == nil {
                    updated.bitDepth = debugInfo?.videoBitDepth
                }

                let transfer = (extensions[kCMFormatDescriptionExtension_TransferFunction] as? String)?.lowercased() ?? ""
                let primaries = (extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String)?.lowercased() ?? ""
                updated.hdrTransfer = hdrTransferName(transfer: transfer, primaries: primaries)

                let extDescription = String(describing: extensions).lowercased()
                updated.dolbyVisionActive = subtype == "dvh1"
                    || subtype == "dvhe"
                    || extDescription.contains("dolby")
                    || extDescription.contains("vision")
            }
        }

        if updated != playbackProof {
            playbackProof = updated
            AppLog.playback.info(
                "Playback proof resolution=\(updated.decodedResolution, privacy: .public) codec=\(updated.codecFourCC, privacy: .public) bitDepth=\(updated.bitDepth ?? 0, privacy: .public) hdr=\(updated.hdrTransfer, privacy: .public) dv=\(updated.dolbyVisionActive, privacy: .public) method=\(updated.playbackMethod, privacy: .public) profile=\(updated.transcodeProfile ?? "n/a", privacy: .public) srcBitrate=\(updated.sourceBitrate ?? 0, privacy: .public) container=\(updated.sourceContainer ?? "n/a", privacy: .public) dvProfile=\(updated.dvProfile ?? 0, privacy: .public) dvLevel=\(updated.dvLevel ?? 0, privacy: .public) videoRange=\(updated.videoRangeType ?? "n/a", privacy: .public) observedBitrate=\(updated.observedBitrate ?? 0, privacy: .public)"
            )
        }
    }

    private func firstVideoFormatDescription(in item: AVPlayerItem) -> CMFormatDescription? {
        let tracks = item.asset.tracks(withMediaType: .video)
        for track in tracks {
            for case let format as CMFormatDescription in track.formatDescriptions {
                return format
            }
        }
        return nil
    }

    private func hdrTransferName(transfer: String, primaries: String) -> String {
        if transfer.contains("pq") {
            return "PQ"
        }
        if transfer.contains("hlg") {
            return "HLG"
        }
        if primaries.contains("2020") {
            return "PQ"
        }
        if runtimeHDRMode == .dolbyVision {
            return "PQ"
        }
        if runtimeHDRMode == .hdr10 {
            return "PQ"
        }
        return "SDR"
    }

    private func detectHDRMode(from item: AVPlayerItem, fallback: HDRPlaybackMode) -> HDRPlaybackMode {
        let tracks = item.asset.tracks(withMediaType: .video)
        for track in tracks {
            for case let format as CMFormatDescription in track.formatDescriptions {
                let subtype = fourCCString(from: CMFormatDescriptionGetMediaSubType(format))
                if subtype == "dvh1" || subtype == "dvhe" {
                    return .dolbyVision
                }

                guard let extensions = CMFormatDescriptionGetExtensions(format) as? [CFString: Any] else { continue }
                let transfer = (extensions[kCMFormatDescriptionExtension_TransferFunction] as? String)?.lowercased() ?? ""
                let primaries = (extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String)?.lowercased() ?? ""

                if transfer.contains("pq") || transfer.contains("hlg") || primaries.contains("2020") {
                    return .hdr10
                }
            }
        }
        return fallback
    }

    private func plannedFallbackAction(for attempt: Int) -> FallbackAction? {
        guard attempt > 0, let plan = currentPlaybackPlan, let first = plan.fallbackGraph.first else {
            return nil
        }
        if attempt == 1 {
            return first
        }

        var action = first
        for _ in 2...attempt {
            action = fallbackPlanner.nextStep(after: action)
        }
        return action
    }

    private func handleSyntheticSeekInvalidation(target: CMTime) {
        guard let syntheticHLSSession else { return }
        let targetPTS = Int64(max(0, target.seconds) * 1_000_000_000.0)
        Task {
            do {
                try await syntheticHLSSession.invalidateForSeek(targetPTS: targetPTS)
                playbackDiagnostics.recordSeekRecovery(targetPTS: targetPTS, recovered: true)
            } catch {
                playbackDiagnostics.recordSeekRecovery(targetPTS: targetPTS, recovered: false)
                AppLog.playback.warning("Synthetic HLS seek invalidation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func fourCCString(from value: FourCharCode) -> String {
        let n = Int(value.bigEndian)
        let bytes = [
            UInt8((n >> 24) & 0xff),
            UInt8((n >> 16) & 0xff),
            UInt8((n >> 8) & 0xff),
            UInt8(n & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii)?.lowercased() ?? ""
    }
}
