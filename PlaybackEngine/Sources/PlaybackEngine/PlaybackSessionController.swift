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

public struct PlaybackTransportState: Sendable, Equatable {
    public var availableAudioTracks: [MediaTrack]
    public var availableSubtitleTracks: [MediaTrack]
    public var selectedAudioTrackID: String?
    public var selectedSubtitleTrackID: String?
    public var activeSkipSuggestion: PlaybackSkipSuggestion?
    public var trickplayManifest: TrickplayManifest?
    public var playbackTimeOffsetSeconds: Double

    public init(
        availableAudioTracks: [MediaTrack] = [],
        availableSubtitleTracks: [MediaTrack] = [],
        selectedAudioTrackID: String? = nil,
        selectedSubtitleTrackID: String? = nil,
        activeSkipSuggestion: PlaybackSkipSuggestion? = nil,
        trickplayManifest: TrickplayManifest? = nil,
        playbackTimeOffsetSeconds: Double = 0
    ) {
        self.availableAudioTracks = availableAudioTracks
        self.availableSubtitleTracks = availableSubtitleTracks
        self.selectedAudioTrackID = selectedAudioTrackID
        self.selectedSubtitleTrackID = selectedSubtitleTrackID
        self.activeSkipSuggestion = activeSkipSuggestion
        self.trickplayManifest = trickplayManifest
        self.playbackTimeOffsetSeconds = playbackTimeOffsetSeconds
    }

    public static let empty = PlaybackTransportState()
}

@MainActor
final class PlaybackTransportStateCommitter {
    private var pendingCommitTask: Task<Void, Never>?
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64 = 120_000_000) {
        self.delayNanoseconds = delayNanoseconds
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        pendingCommitTask?.cancel()
        pendingCommitTask = Task { @MainActor [delayNanoseconds] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func commitNow(_ action: @escaping @MainActor () -> Void) {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        action()
    }

    func cancel() {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
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
    public var routeGuaranteeSummary: String?
    public var videoIntegrity: String?
    public var hdrIntegrity: String?
    public var startupClass: String?
    public var preservesOriginalVideo: Bool
    public var preservesDolbyVision: Bool
    public var preservesHDR: Bool
    public var healthState: String?
    public var observedSafetyRatio: Double?
    public var requiredBitrate: Int?
    public var localMediaGatewayEnabled: Bool
    public var finalURL: String?

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
        recoverySuggestion: String? = nil,
        routeGuaranteeSummary: String? = nil,
        videoIntegrity: String? = nil,
        hdrIntegrity: String? = nil,
        startupClass: String? = nil,
        preservesOriginalVideo: Bool = false,
        preservesDolbyVision: Bool = false,
        preservesHDR: Bool = false,
        healthState: String? = nil,
        observedSafetyRatio: Double? = nil,
        requiredBitrate: Int? = nil,
        localMediaGatewayEnabled: Bool = false,
        finalURL: String? = nil
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
        self.routeGuaranteeSummary = routeGuaranteeSummary
        self.videoIntegrity = videoIntegrity
        self.hdrIntegrity = hdrIntegrity
        self.startupClass = startupClass
        self.preservesOriginalVideo = preservesOriginalVideo
        self.preservesDolbyVision = preservesDolbyVision
        self.preservesHDR = preservesHDR
        self.healthState = healthState
        self.observedSafetyRatio = observedSafetyRatio
        self.requiredBitrate = requiredBitrate
        self.localMediaGatewayEnabled = localMediaGatewayEnabled
        self.finalURL = finalURL
    }
}

struct VideoFormatSnapshot: Sendable, Equatable {
    let codecFourCC: String
    let bitDepth: Int?
    let hdrTransfer: String
    let dolbyVisionActive: Bool
    let hdrMode: HDRPlaybackMode
}

@Observable
@MainActor
public final class PlaybackSessionController {
    public private(set) var isPlaying = false
    public internal(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var availableAudioTracks: [MediaTrack] = [] {
        didSet { scheduleTransportStateSnapshotUpdate() }
    }
    public private(set) var availableSubtitleTracks: [MediaTrack] = [] {
        didSet { scheduleTransportStateSnapshotUpdate() }
    }
    public private(set) var selectedAudioTrackID: String? {
        didSet { scheduleTransportStateSnapshotUpdate() }
    }
    public private(set) var selectedSubtitleTrackID: String? {
        didSet { scheduleTransportStateSnapshotUpdate() }
    }
    public private(set) var routeDescription: String = ""
    public private(set) var debugInfo: PlaybackDebugInfo?
    public private(set) var isNativePlayerActive = false
    public private(set) var nativePlayerPlaybackSurface: NativePlayerPlaybackSurface = .sampleBuffer
    public private(set) var nativePlayerDiagnosticsOverlayLines: [String] = []
    public private(set) var nativePlayerPlaybackURL: URL?
    public private(set) var nativePlayerPlaybackHeaders: [String: String] = [:]
    public private(set) var nativePlayerStartTimeSeconds: Double?
    public private(set) var currentPlaybackPlan: PlaybackPlan?
    public private(set) var runtimeHDRMode: HDRPlaybackMode = .unknown
    public private(set) var metrics = PlaybackPerformanceMetrics()
    public private(set) var routeGuarantees: PlaybackRouteGuarantees = .unknown
    public private(set) var playbackHealth = PlaybackHealthSnapshot()
    public private(set) var fallbackRecommendation: PlaybackFallbackRecommendation?
    public private(set) var startupTrace = PlaybackStartupTrace()
    public private(set) var isExternalPlaybackActive = false
    public internal(set) var playbackErrorMessage: String?
    public internal(set) var activeSkipSuggestion: PlaybackSkipSuggestion? {
        didSet { scheduleTransportStateSnapshotUpdate() }
    }
    public internal(set) var activeTrickplayManifest: TrickplayManifest? {
        didSet { scheduleTransportStateSnapshotUpdate() }
    }
    public internal(set) var playbackTimeOffsetSeconds: Double = 0 {
        didSet { scheduleTransportStateSnapshotUpdate() }
    }
    public private(set) var playbackProof = PlaybackProofSnapshot()
    public private(set) var transportState = PlaybackTransportState.empty

    public let player = AVPlayer()

    let apiClient: any JellyfinAPIClientProtocol & Sendable
    private let repository: MetadataRepositoryProtocol
    private let episodeReleaseTracker: (any EpisodeReleaseTrackingProtocol)?
    private let coordinator: PlaybackCoordinator
    private let nativePlayerController: NativePlayerPlaybackController
    private let warmupManager: (any PlaybackWarmupManaging)?
    private let progressPersistenceEnabled: Bool
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

    var currentItemID: String?
    var currentMediaItem: MediaItem?
    var nextEpisodeQueue: [MediaItem] = []
    var mediaSegments: [MediaSegment] = []
    private var currentItemHasDolbyVision = false
    private var currentSource: MediaSource?
    private var playMethodForReporting = "Transcode"
    private var didResumeAfterForeground = false
    private var hasMarkedFirstFrame = false
    private var firstFrameDate: Date?
    private var lastDeepPlaybackEvidenceLogDate: Date?
    private var lastDeepPlaybackEvidencePlaybackTime: Double?
    private var hasDecodedVideoFrame = false
    private var avkitReadyForDisplay = false
    private var pendingResumeSeconds: Double?
    private var directPlayAutoplayStartupGateOwnsResumeSeek = false
    private var directPlayStartupPlaybackBlocked = false
    private var lastKnownPlaybackPositionSeconds: Double?
    private var pendingPlaybackPositionOverrideSeconds: Double?
    private var transcodeStartOffset: Double = 0
    private var currentForwardBufferDuration: Double = 0
    private var tvosHealthyAccessLogSamples: Int = 0
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
    private var videoFormatSnapshotTask: Task<Void, Never>?
    private var cachedVideoFormatSnapshot: VideoFormatSnapshot?
    private var recoveryAttemptCount = 0
    private var isRecoveryInProgress = false
    private var recentStallTimestamps: [Date] = []
    private var playbackHealthMonitor = PlaybackHealthMonitor()
    private var didAttemptDirectPlayStallRecovery = false
    private var attemptedPlaybackTriples = Set<String>()
    private static var fragileDirectPlayRoutes: [String: Date] = [:]
    private static let fragileDirectPlayRouteTTL: TimeInterval = 600
    private var sessionInitialResumeSeconds: Double = 0
    private var selectedVariantInfo: HLSVariantInfo?
    private var selectedMasterPlaylistURL: URL?
    private var selectedVariantPlaylistInspection: VariantPlaylistInspection?
    private var selectedInitSegmentInspection: InitSegmentInspection?
    private var fallbackOccurred = false
    private var fallbackReason: String?
    private var nativeModeCoordinatorFallbackRootReason: String?
    private var lastPlayerItemStatus = "unknown"
    private var lastFailureDomain: String?
    private var lastFailureCode: Int?
    private var lastFailureReason: String?
    private var lastRecoverySuggestion: String?
    private var playbackLogSessionID = "none"
    private let audioSelector = AudioCompatibilitySelector()
    private let subtitlePolicy = SubtitleCompatibilityPolicy()
    private let assetURLValidator = AssetURLValidator()
    private let mediaGatewayStore: MediaGatewayStore?
    private var localMediaGatewayServer: LocalMediaGatewayServer?
    private var localMediaGatewaySession: LocalMediaGatewaySession?
    private var localMediaGatewayRemoteSelection: PlaybackAssetSelection?
    private var localMediaGatewayLocalSelection: PlaybackAssetSelection?
    private var localMediaGatewayDisabledSourceIDs = Set<String>()
    // Cache-loader playback path (raw original, no HLS, DV-preserved). Lifetime is the playback
    // session; torn down in `stopLocalMediaGateway`. See `CacheLoaderRoutePolicy` (flag OFF by default).
    private var cacheResourceLoader: CacheResourceLoaderDelegate?
    private var cacheOriginDownloader: OriginDownloader?
    /// Localhost HTTP cache proxy (Infuse-class never-cut path): AVPlayer reads the deep local cache
    /// over http://127.0.0.1 so DV renders, while the parallel downloader fills ahead of the playhead.
    private var cacheProxyServer: LocalCacheHTTPServer?
    private var startDate = Date()
    private var loadStartDate = Date()
    private var preferredProfilesByItemID: [String: TranscodeURLProfile] = [:]
    private var lastPreparedSelection: PlaybackAssetSelection?
    var markerRefreshTask: Task<Void, Never>?
    private var trickplayRefreshTask: Task<Void, Never>?
    private var didApplyStartupSubtitleSelection = false
    @ObservationIgnored private let transportStateCommitter = PlaybackTransportStateCommitter()
    private var transportStateSnapshotUpdatesSuspended = false

    enum StartupSubtitleLoadAction: Equatable {
        case none
        case applyEmbedded(String)
        case skipExternal(String)
    }

    struct DirectPlayStabilityPolicy: Equatable {
        let forwardBufferDuration: Double
        let waitsToMinimizeStalling: Bool
        let reason: String?
    }

    nonisolated static func makePlaybackLogSessionID(itemID: String) -> String {
        "\(AppLogFormat.shortIdentifier(itemID))-\(UUID().uuidString.prefix(6))"
    }

    nonisolated static func playbackLogScope(
        sessionID: String,
        itemID: String?,
        attempt: Int? = nil
    ) -> String {
        var parts = [
            "session=\(sessionID)",
            "item=\(AppLogFormat.shortIdentifier(itemID))"
        ]
        if let attempt {
            parts.append("attempt=\(attempt)")
        }
        return parts.joined(separator: " ")
    }

    private func playbackLogScope(attempt: Int? = nil) -> String {
        Self.playbackLogScope(sessionID: playbackLogSessionID, itemID: currentItemID, attempt: attempt)
    }

    private func isActivePlaybackTarget(itemID: String) -> Bool {
        guard currentItemID == itemID else { return false }
        guard let currentMediaItem else { return false }
        return currentMediaItem.id == itemID
    }

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
    private var remoteProgressReportTask: Task<Void, Never>?
    private var pendingRemoteProgressUpdate: PlaybackProgressUpdate?
    private var lastRemoteProgressReportDate: Date?
    private var currentMaxStreamingBitrate = QualityPreference.auto.maxStreamingBitrate
    private var videoOutput: AVPlayerItemVideoOutput?
    private var ttffTuning: TTFFTuningConfiguration = .default
    private var ttffInfoMs: Double = 0
    private var ttffResolveMs: Double = 0
    private var ttffFirstBytesMs: Double = 0
    private var ttffReadyMs: Double = 0
    public static let preferredProfileStorageKey = "reelfin.playback.preferredTranscodeProfileByItemID.v2"
    private static let localhostHLSMaxStartupAttempts = 2
    private static let remoteProgressMinimumInterval: TimeInterval = 10
    private static let remoteProgressRecoveryPollInterval: TimeInterval = 1
    private var startupSubtitleSelectionTask: Task<Void, Never>?
    private var videoValidationTask: Task<Void, Never>?
    private var directPlayPostStartRebufferTask: Task<Void, Never>?
    /// Watchdog armed when a post-start direct-play stall is being ridden out on the original
    /// (Dolby Vision) stream. If playback hasn't progressed past the stall point within
    /// `sustainedStallEscalationGraceSeconds`, the stall is not a transient blip and we escalate to
    /// the watchable adaptive transcode (never-freeze). Cancelled as soon as playback resumes.
    private var directPlayStallEscalationTask: Task<Void, Never>?

    public static func clearStoredPreferredTranscodeProfiles(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: preferredProfileStorageKey)
    }

    private static var isTvOSPlatform: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

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
        episodeReleaseTracker: (any EpisodeReleaseTrackingProtocol)? = nil,
        warmupManager: (any PlaybackWarmupManaging)? = nil,
        decisionEngine: PlaybackDecisionEngine = PlaybackDecisionEngine(),
        progressPersistenceEnabled: Bool = true
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.episodeReleaseTracker = episodeReleaseTracker
        self.coordinator = PlaybackCoordinator(apiClient: apiClient, decisionEngine: decisionEngine)
        let mediaGatewayStore = try? MediaGatewayStore()
        self.mediaGatewayStore = mediaGatewayStore
        self.nativePlayerController = NativePlayerPlaybackController(
            apiClient: apiClient,
            mediaGatewayStore: mediaGatewayStore
        )
        self.warmupManager = warmupManager
        self.progressPersistenceEnabled = progressPersistenceEnabled
        self.preferredProfilesByItemID = Self.loadStoredPreferredProfiles()
        configurePlayerBase()
        setupLifecycleObservers()
    }

    private func beginTransportStateSnapshotBatch() {
        transportStateSnapshotUpdatesSuspended = true
        transportStateCommitter.cancel()
    }

    private func endTransportStateSnapshotBatch(commitNow: Bool = true) {
        transportStateSnapshotUpdatesSuspended = false
        if commitNow {
            commitTransportStateSnapshotNow()
        }
    }

    private func makeTransportState() -> PlaybackTransportState {
        PlaybackTransportState(
            availableAudioTracks: availableAudioTracks,
            availableSubtitleTracks: availableSubtitleTracks,
            selectedAudioTrackID: selectedAudioTrackID,
            selectedSubtitleTrackID: selectedSubtitleTrackID,
            activeSkipSuggestion: activeSkipSuggestion,
            trickplayManifest: activeTrickplayManifest,
            playbackTimeOffsetSeconds: playbackTimeOffsetSeconds
        )
    }

    private func applyTransportStateSnapshot() {
        let snapshot = makeTransportState()
        guard snapshot != transportState else { return }
        transportState = snapshot
    }

    private func scheduleTransportStateSnapshotUpdate() {
        guard !transportStateSnapshotUpdatesSuspended else { return }
        transportStateCommitter.schedule { [weak self] in
            self?.applyTransportStateSnapshot()
        }
    }

    private func commitTransportStateSnapshotNow() {
        transportStateCommitter.commitNow { [weak self] in
            self?.applyTransportStateSnapshot()
        }
    }

    @MainActor
    deinit {
        tearDownCurrentItemObservers()

        lifecycleObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        transportStateCommitter.cancel()
        startupWatchdogTask?.cancel()
        decodedFrameWatchdogTask?.cancel()
        videoOutputPollTask?.cancel()
        remoteProgressReportTask?.cancel()
        directPlayPostStartRebufferTask?.cancel()
        markerRefreshTask?.cancel()
        trickplayRefreshTask?.cancel()
        stopLocalMediaGateway(reason: "controller_deinit")
        localHLSServer?.stop(reason: "controller_deinit")
    }

    public func load(
        item: MediaItem,
        autoPlay: Bool = true,
        upNextEpisodes: [MediaItem] = [],
        startPosition: PlaybackStartPosition = .resumeIfAvailable,
        forceNativeOriginalPlayback: Bool = false
    ) async throws {
        currentItemID = item.id
        playbackLogSessionID = Self.makePlaybackLogSessionID(itemID: item.id)
        stopLocalMediaGateway(reason: "new_load")
        localMediaGatewayDisabledSourceIDs.removeAll()
        currentMediaItem = item
        nextEpisodeQueue = upNextEpisodes
        currentTime = 0
        duration = 0
        mediaSegments = []
        markerRefreshTask?.cancel()
        markerRefreshTask = Task { @MainActor [weak self] in
            await self?.refreshPlaybackMarkers(for: item)
        }
        trickplayRefreshTask?.cancel()
        currentItemHasDolbyVision = item.hasDolbyVision
        loadStartDate = Date()
        startDate = loadStartDate
        hasMarkedFirstFrame = false
        firstFrameDate = nil
        lastDeepPlaybackEvidenceLogDate = nil
        lastDeepPlaybackEvidencePlaybackTime = nil
        hasDecodedVideoFrame = false
        avkitReadyForDisplay = false
        pendingResumeSeconds = nil
        lastKnownPlaybackPositionSeconds = nil
        pendingPlaybackPositionOverrideSeconds = nil
        directPlayStartupPlaybackBlocked = false
        transcodeStartOffset = 0
        sessionInitialResumeSeconds = 0
        playbackTimeOffsetSeconds = 0
        currentForwardBufferDuration = 0
        tvosHealthyAccessLogSamples = 0
        videoFormatSnapshotTask?.cancel()
        videoFormatSnapshotTask = nil
        cachedVideoFormatSnapshot = nil
        recentStallTimestamps.removeAll()
        didAttemptDirectPlayStallRecovery = false
        recoveryAttemptCount = 0
        metrics = PlaybackPerformanceMetrics()
        routeGuarantees = .unknown
        playbackHealthMonitor = PlaybackHealthMonitor()
        playbackHealth = playbackHealthMonitor.snapshot()
        fallbackRecommendation = nil
        startupTrace = PlaybackStartupTrace(userTappedPlayAt: loadStartDate)
        playbackErrorMessage = nil
        isNativePlayerActive = false
        nativePlayerPlaybackSurface = .sampleBuffer
        nativePlayerDiagnosticsOverlayLines = []
        nativePlayerPlaybackURL = nil
        nativePlayerPlaybackHeaders = [:]
        nativePlayerStartTimeSeconds = nil
        currentPlaybackPlan = nil
        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
        decodedFrameWatchdogTask?.cancel()
        decodedFrameWatchdogTask = nil
        videoOutputPollTask?.cancel()
        videoOutputPollTask = nil
        remoteProgressReportTask?.cancel()
        remoteProgressReportTask = nil
        pendingRemoteProgressUpdate = nil
        lastRemoteProgressReportDate = nil
        startupSubtitleSelectionTask?.cancel()
        startupSubtitleSelectionTask = nil
        videoValidationTask?.cancel()
        videoValidationTask = nil
        directPlayPostStartRebufferTask?.cancel()
        directPlayPostStartRebufferTask = nil
        attemptedPlaybackTriples.removeAll()
        selectedVariantInfo = nil
        selectedMasterPlaylistURL = nil
        selectedVariantPlaylistInspection = nil
        selectedInitSegmentInspection = nil
        fallbackOccurred = false
        fallbackReason = nil
        nativeModeCoordinatorFallbackRootReason = nil
        lastPlayerItemStatus = "unknown"
        lastFailureDomain = nil
        lastFailureCode = nil
        lastFailureReason = nil
        lastRecoverySuggestion = nil
        localHLSStartupSummary = nil
        var playbackConfig = await currentPlaybackConfiguration()
        if forceNativeOriginalPlayback {
            playbackConfig.nativePlayerConfig.enabled = true
            playbackConfig.nativePlayerConfig.alwaysRequestOriginalFile = true
            playbackConfig.nativePlayerConfig.allowCustomDemuxers = true
            playbackConfig.nativePlayerConfig.enableExperimentalMKV = true
            playbackConfig.nativePlayerConfig.allowServerTranscodeFallback = false
            AppLog.playback.notice(
                "nativeplayer.route.forced_original — \(self.playbackLogScope(), privacy: .public) reason=custom_mkv_handoff"
            )
        }
        playbackPolicy = playbackConfig.playbackPolicy
        allowSDRFallback = playbackConfig.allowSDRFallback
        preferAudioTranscodeOnly = playbackConfig.preferAudioTranscodeOnly
        preferredAudioLanguage = playbackConfig.preferredAudioLanguage
        preferredSubtitleLanguage = playbackConfig.preferredSubtitleLanguage
        currentMaxStreamingBitrate = playbackConfig.maxStreamingBitrate
        if playbackPolicy == .originalLockHDRDV {
            // Keep startup config byte-identical to baseline (no startup change → no black screen).
            // The adaptive fallback is RECOVERY-scoped: it forces a transcode on a sustained stall
            // via allowDirectRoutes=false + the coordinator fallback reason + destructive-block
            // bypass, none of which depend on the startup quality mode.
            playbackQualityMode = .strictQuality
            allowSDRFallback = false
        } else {
            playbackQualityMode = allowSDRFallback ? .compatibility : .strictQuality
        }
        activeTranscodeProfile = playbackConfig.nativePlayerConfig.enabled
            ? .serverDefault
            : initialProfileForItem(itemID: item.id, itemHasDolbyVision: item.hasDolbyVision)
        playbackStrategy = await currentPlaybackStrategy()
        AppLog.playback.notice(
            "playback.session.start — \(Self.playbackLogScope(sessionID: self.playbackLogSessionID, itemID: item.id), privacy: .public) autoplay=\(autoPlay, privacy: .public) strategy=\(self.playbackStrategy.rawValue, privacy: .public) policy=\(self.playbackPolicy.rawValue, privacy: .public) quality=\(self.playbackQualityMode.rawValue, privacy: .public) profile=\(self.activeTranscodeProfile.rawValue, privacy: .public)"
        )
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

        transportStateCommitter.cancel()
        transportState = .empty
        beginTransportStateSnapshotBatch()
        activeSkipSuggestion = nil
        activeTrickplayManifest = nil

        // Start the overall TTFF pipeline signpost
        ttffPipelineInterval = SignpostInterval(signposter: Signpost.ttffPipeline, name: "ttff_total")
        ttffInfoInterval = SignpostInterval(signposter: Signpost.ttffPipeline, name: "ttff_playback_info")
        let infoStartDate = Date()

        do {
            // Fetch resume position before resolving playback so we can pass StartTimeTicks
            // to Jellyfin. This makes the server transcode from the correct position immediately,
            // instead of transcoding from 0 and relying on a fragile mid-stream seek.
            let initialResumeSecs = (try? await resumeSeconds(for: item, startPosition: startPosition)) ?? 0
            sessionInitialResumeSeconds = initialResumeSecs
            let resumeTimeTicks: Int64? = initialResumeSecs > 0 ? Int64(initialResumeSecs * 10_000_000) : nil

            if playbackConfig.nativePlayerConfig.enabled {
                AppLog.playback.notice(
                    "nativeplayer.route.selected — \(self.playbackLogScope(), privacy: .public) surfacePreference=\(playbackConfig.nativePlayerConfig.surfacePreference.rawValue, privacy: .public) legacyCoordinator=false avPlayerItem=pending avPlayerViewController=pending profile=\(self.activeTranscodeProfile.rawValue, privacy: .public)"
                )
                try await prepareNativePlayerPlayback(
                    item: item,
                    nativeConfig: playbackConfig.nativePlayerConfig,
                    startTimeTicks: resumeTimeTicks,
                    autoPlay: autoPlay
                )
                ttffInfoInterval?.end(name: "ttff_playback_info", message: "native_player_info_received")
                ttffInfoInterval = nil
                ttffResolveInterval?.end(name: "ttff_url_resolution", message: "native_player_prepared")
                ttffResolveInterval = nil
                return
            }

            let warmedSelectionStart = Date()
            var selection: PlaybackAssetSelection

            // Transcode/remux warmups are resolved without StartTimeTicks, so they
            // cannot be reused for resume. DirectPlay seeks client-side and is safe.
            let candidateWarmed = await warmupManager?.selection(for: item.id)
            if let warmedSelection = candidateWarmed,
               Self.canUseWarmedSelection(warmedSelection, resumeSeconds: initialResumeSecs) {
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
                    transcodeProfile: activeTranscodeProfile,
                    startTimeTicks: resumeTimeTicks
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
                ),
                profileOverride: Self.variantPinningProfile(
                    from: selection.assetURL,
                    requestedProfile: activeTranscodeProfile
                )
            )
            selection = try await stabilizeInitialSelectionIfNeeded(
                itemID: item.id,
                selection: selection,
                startTimeTicks: resumeTimeTicks,
                itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                    itemPrefersDolbyVision: item.hasDolbyVision,
                    source: selection.source
                )
            )
            selection = try await upgradeRiskyInitialSelectionIfNeeded(
                itemID: item.id,
                selection: selection,
                startTimeTicks: resumeTimeTicks,
                itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                    itemPrefersDolbyVision: item.hasDolbyVision,
                    source: selection.source
                )
            )
            selection = try await preemptHighRiskProgressiveDirectPlayIfNeeded(
                itemID: item.id,
                selection: selection,
                startTimeTicks: resumeTimeTicks,
                maxStreamingBitrate: playbackConfig.maxStreamingBitrate,
                itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                    itemPrefersDolbyVision: item.hasDolbyVision,
                    source: selection.source
                )
            )
            activeTranscodeProfile = inferredActiveProfile(for: selection, fallback: activeTranscodeProfile)
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
                    // NativeBridge failed. Ask Jellyfin for the best copy/remux path
                    // before considering any route that changes the video bitstream.
                    NativeBridgeFailureCache.recordFailure(itemID: item.id)
                    AppLog.playback.warning("NativeBridge prepare failed: \(error.localizedDescription, privacy: .public). Falling back to server remux.")
                    activeTranscodeProfile = .serverDefault
                    selection = try await coordinator.resolvePlayback(
                        itemID: item.id,
                        mode: .balanced,
                        allowTranscodingFallbackInPerformance: true,
                        transcodeProfile: activeTranscodeProfile,
                        startTimeTicks: resumeTimeTicks
                    )
                    selection = try await pinPreferredVariantIfNeeded(
                        selection: selection,
                        itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                            itemPrefersDolbyVision: item.hasDolbyVision,
                            source: selection.source
                        ),
                        profileOverride: Self.variantPinningProfile(
                            from: selection.assetURL,
                            requestedProfile: activeTranscodeProfile
                        )
                    )
                    selection = try await stabilizeInitialSelectionIfNeeded(
                        itemID: item.id,
                        selection: selection,
                        startTimeTicks: resumeTimeTicks,
                        itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                            itemPrefersDolbyVision: item.hasDolbyVision,
                            source: selection.source
                        )
                    )
                    selection = try await upgradeRiskyInitialSelectionIfNeeded(
                        itemID: item.id,
                        selection: selection,
                        startTimeTicks: resumeTimeTicks,
                        itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                            itemPrefersDolbyVision: item.hasDolbyVision,
                            source: selection.source
                        )
                    )
                    selection = try await preemptHighRiskProgressiveDirectPlayIfNeeded(
                        itemID: item.id,
                        selection: selection,
                        startTimeTicks: resumeTimeTicks,
                        maxStreamingBitrate: playbackConfig.maxStreamingBitrate,
                        itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                            itemPrefersDolbyVision: item.hasDolbyVision,
                            source: selection.source
                        )
                    )
                    activeTranscodeProfile = inferredActiveProfile(for: selection, fallback: activeTranscodeProfile)
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

            selection = try await repairInitialSelectionIfNeeded(
                itemID: item.id,
                selection: selection,
                mode: .balanced,
                startTimeTicks: resumeTimeTicks,
                itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                    itemPrefersDolbyVision: item.hasDolbyVision,
                    source: selection.source
                )
            )
            let finalInitialGuarantees = resolvedRouteGuarantees(for: selection)
            if blockAutomaticDestructiveFallbackIfNeeded(
                selection: selection,
                guarantees: finalInitialGuarantees,
                reason: "initial_selection"
            ) {
                throw AppError.network(playbackErrorMessage ?? "Playback needs a quality fallback choice.")
            }

            let runtimeSeconds = item.runtimeTicks.map { Double($0) / 10_000_000 }
            let shouldPreserveDirectPlayStartup = Self.shouldPreserveDirectPlayStartup(
                route: selection.decision.route,
                source: selection.source,
                playbackPolicy: playbackPolicy,
                allowSDRFallback: allowSDRFallback,
                usesDirectRemuxOnly: usesDirectRemuxOnly,
                maxStreamingBitrate: playbackConfig.maxStreamingBitrate,
                isTVOS: Self.isTvOSPlatform
            )
            let shouldRunInlinePreheat = autoPlay && PlaybackStartupReadinessPolicy.requiresStartupPreheat(
                route: selection.decision.route,
                sourceBitrate: selection.source.bitrate,
                sourceIsHDRorDV: selection.source.isLikelyHDRorDV,
                runtimeSeconds: runtimeSeconds,
                resumeSeconds: initialResumeSecs,
                isTVOS: Self.isTvOSPlatform
            )
            let shouldUseStartupGateway = autoPlay
                ? await shouldUseLocalMediaGatewayForStartup(selection: selection, resumeSeconds: initialResumeSecs)
                : false
            if shouldUseStartupGateway {
                logPrestartEvidenceSkipped(selection: selection, reason: "local_gateway_startup")
            }
            let preheatTask = shouldRunInlinePreheat
                ? (
                    shouldUseStartupGateway
                    ? makeCachedStartupPreheatTask(
                        selection: selection,
                        resumeSeconds: initialResumeSecs,
                        runtimeSeconds: runtimeSeconds
                    )
                    : makeStartupPreheatTask(
                        selection: selection,
                        resumeSeconds: initialResumeSecs,
                        runtimeSeconds: runtimeSeconds
                    )
                )
                : nil
            let serverBaselineTask = shouldRunInlinePreheat && !shouldUseStartupGateway ? makeServerBaselineTask(
                selection: selection
            ) : nil
            let autoplayGateOwnsResumeSeek = Self.shouldAutoplayStartupGateOwnDirectPlayResumeSeek(
                route: selection.decision.route,
                autoPlay: autoPlay,
                resumeSeconds: initialResumeSecs
            )
            directPlayAutoplayStartupGateOwnsResumeSeek = autoplayGateOwnsResumeSeek

            // For transcode/remux routes, only apply an absolute-time offset when
            // the loaded stream proves that it starts from the resume position.
            // For directPlay: seek immediately (the raw URL doesn't support StartTimeTicks).
            if case .directPlay = selection.decision.route {
                transcodeStartOffset = 0
                await loadDirectPlaySelectionAtResumePosition(selection, resumeSeconds: initialResumeSecs)
            } else {
                transcodeStartOffset = Self.initialTranscodeStartOffset(
                    for: selection,
                    resumeSeconds: initialResumeSecs
                )
                prepareAndLoadSelection(selection, resumeSeconds: initialResumeSecs)
            }

            // Mark URL resolution phase complete
            ttffResolveInterval?.end(name: "ttff_url_resolution", message: "url_resolved")
            ttffResolveInterval = nil
            ttffResolveMs = Date().timeIntervalSince(resolveStartDate) * 1000

            // Retrieve TTFF tuning from coordinator
            ttffTuning = coordinator.ttffTuning

            if autoPlay {
                defer {
                    if autoplayGateOwnsResumeSeek {
                        directPlayAutoplayStartupGateOwnsResumeSeek = false
                    }
                }
                let evidence = await resolvePrestartEvidence(
                    selection: selection,
                    preheatTask: preheatTask,
                    serverBaselineTask: serverBaselineTask
                )
                let preheatResult = evidence.preheatResult
                let serverBaselineResult = evidence.serverBaselineResult
                if let prestartReason = Self.directPlayPrestartRecoveryReason(
                    route: selection.decision.route,
                    sourceBitrate: selection.source.bitrate,
                    sourceIsHDRorDV: selection.source.isLikelyHDRorDV,
                    preheatResult: preheatResult,
                    serverBaselineResult: serverBaselineResult,
                    isTVOS: Self.isTvOSPlatform
                ) {
                    logDirectPlayPrestartHeadroom(
                        selection: selection,
                        preheatResult: preheatResult,
                        serverBaselineResult: serverBaselineResult,
                        reason: prestartReason,
                        action: "profile_fallback"
                    )
                    if await attemptStartupRecoveryIfAvailable(
                        reason: prestartReason.rawValue,
                        userMessage: "Direct Play network preflight was too weak. Switching playback profile."
                    ) {
                        return
                    }
                }
                logUnsafeDirectPlayStartupHeadroomIfNeeded(
                    selection: selection,
                    preheatResult: preheatResult,
                    serverBaselineResult: serverBaselineResult
                )
                let startupResumePositionReady = await ensureDirectPlayResumePositionBeforeAutoplayIfNeeded(
                    selection: selection,
                    resumeSeconds: initialResumeSecs,
                    phase: "startup_preplay",
                    waitForItemReady: true
                )
                if !startupResumePositionReady,
                   Self.shouldBlockAutoplayAfterUnsafeStartup(
                    route: selection.decision.route,
                    source: selection.source,
                    runtimeSeconds: runtimeSeconds,
                    resumeSeconds: initialResumeSecs,
                    isTVOS: Self.isTvOSPlatform
                   ) {
                    logStartupRecoveryUnavailable(
                        reason: "directplay_resume_seek_not_ready",
                        action: "block_autoplay"
                    )
                    blockUnsafeDirectPlayStartupPlayback(
                        reason: "directplay_resume_seek_not_ready",
                        userMessage: "Playback could not resume safely. Try again or use a lower quality profile."
                    )
                    return
                }
                let startupReady = await performStartupReadinessGateIfNeeded(
                    selection: selection,
                    resumeSeconds: initialResumeSecs,
                    runtimeSeconds: runtimeSeconds,
                    preheatResult: preheatResult,
                    serverBaselineResult: serverBaselineResult,
                    maxStreamingBitrate: playbackConfig.maxStreamingBitrate
                )
                if !startupReady {
                    let shouldBlockUnsafeStartup = Self.shouldBlockAutoplayAfterUnsafeStartup(
                        route: selection.decision.route,
                        source: selection.source,
                        runtimeSeconds: runtimeSeconds,
                        resumeSeconds: initialResumeSecs,
                        isTVOS: Self.isTvOSPlatform
                    )
                    if !shouldPreserveDirectPlayStartup {
                        if await attemptStartupRecoveryIfAvailable(
                            reason: StartupFailureReason.startupReadinessTimeout.rawValue,
                            userMessage: "Playback did not build a safe buffer. Switching playback profile."
                        ) {
                            return
                        }
                    }
                    if shouldBlockUnsafeStartup {
                        logStartupRecoveryUnavailable(
                            reason: StartupFailureReason.startupReadinessTimeout.rawValue,
                            action: "block_autoplay"
                        )
                        blockUnsafeDirectPlayStartupPlayback(
                            reason: StartupFailureReason.startupReadinessTimeout.rawValue,
                            userMessage: "Playback did not build a safe buffer. Try a lower quality profile."
                        )
                        return
                    }
                    logStartupRecoveryUnavailable(
                        reason: StartupFailureReason.startupReadinessTimeout.rawValue,
                        action: "continue_current_item"
                    )
                }
                if !(await prepareSynchronizedStartupFrameIfNeeded(selection: selection)) {
                    let shouldBlockUnsafeStartup = Self.shouldBlockAutoplayAfterUnsafeStartup(
                        route: selection.decision.route,
                        source: selection.source,
                        runtimeSeconds: runtimeSeconds,
                        resumeSeconds: initialResumeSecs,
                        isTVOS: Self.isTvOSPlatform
                    )
                    if !shouldPreserveDirectPlayStartup {
                        if await attemptStartupRecoveryIfAvailable(
                            reason: StartupFailureReason.startupVideoPrerollTimeout.rawValue,
                            userMessage: "Video did not preroll before audio. Switching playback profile."
                        ) {
                            return
                        }
                    }
                    if shouldBlockUnsafeStartup {
                        logStartupRecoveryUnavailable(
                            reason: StartupFailureReason.startupVideoPrerollTimeout.rawValue,
                            action: "block_autoplay"
                        )
                        blockUnsafeDirectPlayStartupPlayback(
                            reason: StartupFailureReason.startupVideoPrerollTimeout.rawValue,
                            userMessage: "Video did not become ready before playback. Try again or use a lower quality profile."
                        )
                        return
                    }
                    logStartupRecoveryUnavailable(
                        reason: StartupFailureReason.startupVideoPrerollTimeout.rawValue,
                        action: "force_autoplay"
                    )
                }
                let resumePositionReady = await ensureDirectPlayResumePositionBeforeAutoplayIfNeeded(
                    selection: selection,
                    resumeSeconds: initialResumeSecs,
                    phase: "preplay",
                    waitForItemReady: false
                )
                if !resumePositionReady,
                   Self.shouldBlockAutoplayAfterUnsafeStartup(
                    route: selection.decision.route,
                    source: selection.source,
                    runtimeSeconds: runtimeSeconds,
                    resumeSeconds: initialResumeSecs,
                    isTVOS: Self.isTvOSPlatform
                   ) {
                    logStartupRecoveryUnavailable(
                        reason: "directplay_resume_seek_not_ready",
                        action: "block_autoplay"
                    )
                    blockUnsafeDirectPlayStartupPlayback(
                        reason: "directplay_resume_seek_not_ready",
                        userMessage: "Playback could not resume safely. Try again or use a lower quality profile."
                    )
                    return
                }
                directPlayStartupPlaybackBlocked = false
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

    private func resumeSeconds(
        for item: MediaItem,
        startPosition: PlaybackStartPosition
    ) async throws -> Double? {
        guard startPosition == .resumeIfAvailable else { return nil }
        let localProgress = try await repository.fetchPlaybackProgress(itemID: item.id)
        return Self.resolvedResumeSeconds(
            for: item,
            localProgress: localProgress,
            startPosition: startPosition
        )
    }

    nonisolated static func resolvedResumeSeconds(
        for item: MediaItem,
        localProgress: PlaybackProgress?,
        startPosition: PlaybackStartPosition = .resumeIfAvailable
    ) -> Double? {
        guard startPosition == .resumeIfAvailable else { return nil }
        guard let progress = PlaybackProgress.resolvedResumeProgress(
            for: item,
            localProgress: localProgress
        ) else { return nil }

        return Double(progress.positionTicks) / 10_000_000
    }

    nonisolated static func isResumePositionSatisfied(
        currentTime: Double,
        resumeSeconds: Double,
        toleranceSeconds: Double = 3
    ) -> Bool {
        DirectPlaySessionPolicy.isResumePositionSatisfied(
            currentTime: currentTime,
            resumeSeconds: resumeSeconds,
            toleranceSeconds: toleranceSeconds
        )
    }

    nonisolated static func shouldDelayFirstFrameUntilResumePosition(
        route: PlaybackRoute?,
        pendingResumeSeconds: Double?,
        currentTime: Double,
        transcodeStartOffset: Double
    ) -> Bool {
        DirectPlaySessionPolicy.shouldDelayFirstFrameUntilResumePosition(
            route: route,
            pendingResumeSeconds: pendingResumeSeconds,
            currentTime: currentTime,
            transcodeStartOffset: transcodeStartOffset
        )
    }

    nonisolated static func shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
        route: PlaybackRoute,
        hasMarkedFirstFrame: Bool,
        pendingResumeSeconds: Double?,
        currentTime: Double,
        itemStatus: AVPlayerItem.Status,
        transcodeStartOffset: Double,
        isPlaybackActive: Bool = false,
        allowPausedDirectPlayFirstFrame: Bool = false
    ) -> Bool {
        DirectPlaySessionPolicy.shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
            route: route,
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            pendingResumeSeconds: pendingResumeSeconds,
            currentTime: currentTime,
            itemStatus: itemStatus,
            transcodeStartOffset: transcodeStartOffset,
            isPlaybackActive: isPlaybackActive,
            allowPausedDirectPlayFirstFrame: allowPausedDirectPlayFirstFrame
        )
    }

    nonisolated static func shouldWaitForMaterializedDirectPlayResumePositionBeforeStartupSeek(
        route: PlaybackRoute,
        pendingResumeSeconds: Double?,
        currentTime: Double,
        itemStatus: AVPlayerItem.Status,
        transcodeStartOffset: Double,
        directPlayAutoplayStartupGateActive: Bool
    ) -> Bool {
        DirectPlaySessionPolicy.shouldWaitForMaterializedResumePositionBeforeStartupSeek(
            route: route,
            pendingResumeSeconds: pendingResumeSeconds,
            currentTime: currentTime,
            itemStatus: itemStatus,
            transcodeStartOffset: transcodeStartOffset,
            directPlayAutoplayStartupGateActive: directPlayAutoplayStartupGateActive
        )
    }

    nonisolated static var materializedDirectPlayResumePositionStartupWaitTimeout: TimeInterval {
        DirectPlaySessionPolicy.materializedResumePositionStartupWaitTimeout
    }

    nonisolated static func shouldReassertDirectPlayResumePositionAfterStartupSelection(
        route: PlaybackRoute?,
        resumeSeconds: Double?,
        currentTime: Double,
        transcodeStartOffset: Double
    ) -> Bool {
        DirectPlaySessionPolicy.shouldReassertResumePositionAfterStartupSelection(
            route: route,
            resumeSeconds: resumeSeconds,
            currentTime: currentTime,
            transcodeStartOffset: transcodeStartOffset
        )
    }

    nonisolated static func shouldSuppressPlaybackFailureRecoveryAfterFirstFrame(
        hasMarkedFirstFrame: Bool,
        route: PlaybackRoute?
    ) -> Bool {
        DirectPlaySessionPolicy.shouldSuppressPlaybackFailureRecoveryAfterFirstFrame(
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            route: route
        )
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
                let adjustedReaderConfig = PlaybackTVOSCachingPolicy.syntheticReaderConfiguration(
                    base: readerConfig,
                    isTVOS: Self.isTvOSPlatform
                )
                let reader = HTTPRangeReader(url: startupPlan.sourceURL, headers: headers, config: adjustedReaderConfig)
                let demuxer = MatroskaDemuxer(reader: reader, plan: startupPlan)
                let diagnostics = NativeBridgeDiagnosticsCollector(config: startupPlan.diagnostics)
                let repackager = FMP4Repackager(plan: startupPlan, diagnostics: diagnostics)
                let session = SyntheticHLSSession(
                    plan: startupPlan,
                    demuxer: demuxer,
                    repackager: repackager,
                    cache: SegmentCacheActor(
                        maxBytes: PlaybackTVOSCachingPolicy.syntheticSegmentCacheSize(isTVOS: Self.isTvOSPlatform)
                    ),
                    defaultPreloadCount: PlaybackTVOSCachingPolicy.syntheticPlaylistPreloadCount(isTVOS: Self.isTvOSPlatform)
                )
                try await session.prepare()

                let localServer = LocalHLSServer(session: session)
                server = localServer

                let baseURL = try localServer.start()
                guard let port = baseURL.port, port > 0 else {
                    throw AppError.network("Local HLS server returned invalid port: \(baseURL.reelfinLogString)")
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

                AppLog.playback.info("Using synthetic local HLS delivery \(masterURL.reelfinLogString, privacy: .public)")
                AppLog.nativeBridge.notice(
                    "[NB-DIAG] hls.startup.summary — lane=nativeBridge host=127.0.0.1 port=\(port, privacy: .public) master=\(masterURL.reelfinLogString, privacy: .public) initBytes=\(preflight.initBytes, privacy: .public) firstSegBytes=\(preflight.firstSegmentBytes, privacy: .public) firstSegDuration=\(preflight.firstSegmentDurationSeconds, format: .fixed(precision: 3)) keyframe=unknown preflight=pass avplayer=not_created"
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
            throw AppError.network("Invalid local HLS URL (missing/non-positive port): \(masterURL.reelfinLogString)")
        }

        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.master.start — url=\(masterURL.reelfinLogString, privacy: .public)")
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

        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.media.start — url=\(mediaURL.reelfinLogString, privacy: .public)")
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

        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.init.start — url=\(initURL.reelfinLogString, privacy: .public)")
        let initProbe = try await fetchHTTPProbe(url: initURL)
        guard initProbe.statusCode == 200, !initProbe.data.isEmpty else {
            throw AppError.network("Local HLS init segment preflight failed (status=\(initProbe.statusCode), bytes=\(initProbe.data.count)).")
        }
        selectedInitSegmentInspection = InitSegmentInspector.inspect(initProbe.data)
        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.init.ok — status=\(initProbe.statusCode, privacy: .public) bytes=\(initProbe.data.count, privacy: .public)")
        if let initTree = try? BMFFInspector.inspect(initProbe.data) {
            AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.init.tree\n\(BMFFInspector.formatTree(initTree), privacy: .public)")
        }

        AppLog.nativeBridge.notice("[NB-DIAG] hls.preflight.segment.start — url=\(firstSegmentURL.reelfinLogString, privacy: .public)")
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

    private func prepareNativePlayerPlayback(
        item: MediaItem,
        nativeConfig: NativePlayerConfig,
        startTimeTicks: Int64?,
        autoPlay: Bool
    ) async throws {
        guard
            let configuration = await apiClient.currentConfiguration(),
            let session = await apiClient.currentSession()
        else {
            throw AppError.unauthenticated
        }

        player.pause()
        player.replaceCurrentItem(with: nil)
        await nativeBridgeSession?.invalidate()
        nativeBridgeSession = nil
        syntheticHLSSession = nil
        stopLocalMediaGateway(reason: "native_player_class_route")
        localHLSServer?.stop(reason: "native_player_class_route")
        localHLSServer = nil
        localHLSStartupSummary = nil
        videoOutput = nil

        let resumeSeconds = startTimeTicks.map { Double($0) / 10_000_000 }
        if let warmedSelection = await warmupManager?.selection(for: item.id),
           nativeConfig.surfacePreference == .directPlayWhenPossible,
           Self.canUseWarmedSelection(warmedSelection, resumeSeconds: resumeSeconds ?? 0),
           case .directPlay = warmedSelection.decision.route,
           NativePlayerPlaybackController.shouldUseAppleNativeSurface(
            source: warmedSelection.source,
            url: warmedSelection.assetURL
           ),
           NativePlayerRouteGuard.validateOriginalPlaybackURL(warmedSelection.assetURL).isEmpty {
            AppLog.playback.notice(
                "nativeplayer.warmup.selection.hit — \(self.playbackLogScope(), privacy: .public) source=\(warmedSelection.source.id, privacy: .public)"
            )
            let snapshot = NativePlayerPlaybackController.makeAppleNativeSnapshot(
                selection: warmedSelection,
                session: session,
                startTimeTicks: startTimeTicks
            )
            try await applyPreparedNativePlayerSnapshot(
                snapshot,
                resumeSeconds: resumeSeconds,
                runtimeSeconds: item.runtimeTicks.map { Double($0) / 10_000_000 },
                autoPlay: autoPlay
            )
            return
        }

        do {
            let snapshot = try await nativePlayerController.prepare(
                itemID: item.id,
                configuration: configuration,
                session: session,
                nativeConfig: nativeConfig,
                startTimeTicks: startTimeTicks
            )
            try await applyPreparedNativePlayerSnapshot(
                snapshot,
                resumeSeconds: resumeSeconds,
                runtimeSeconds: item.runtimeTicks.map { Double($0) / 10_000_000 },
                autoPlay: autoPlay
            )
        } catch let error as NativePlayerPreparationError {
            switch error {
            case let .appleNativeContainerRequiresCoordinatorFallback(reason):
                try await prepareCoordinatorPlaybackAfterNativeBypass(
                    item: item,
                    startTimeTicks: startTimeTicks,
                    resumeSeconds: resumeSeconds,
                    autoPlay: autoPlay,
                    reason: reason
                )
            }
        } catch {
            let message = error.localizedDescription
            applyNativePlayerSnapshot(
                NativePlayerPlaybackSnapshot(
                    overlayLines: [
                        "originalMediaRequested=true",
                        "serverTranscodeUsed=false",
                        "failure=\(message)"
                    ],
                    routeDescription: "NativeEngine(failed)",
                    playbackErrorMessage: message
                )
            )
        }
    }

    private func prepareCoordinatorPlaybackAfterNativeBypass(
        item: MediaItem,
        startTimeTicks: Int64?,
        resumeSeconds: Double?,
        autoPlay: Bool,
        reason: String
    ) async throws {
        AppLog.playback.notice(
            "nativeplayer.coordinator.fallback — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public)"
        )
        let itemPrefersDolbyVision = currentItemHasDolbyVision
        var selection = try await resolveCoordinatorFallbackSelection(
            itemID: item.id,
            startTimeTicks: startTimeTicks,
            itemPrefersDolbyVision: itemPrefersDolbyVision,
            reason: "native_apple_container_\(reason)"
        )
        if autoPlay {
            selection = try await repairInitialSelectionIfNeeded(
                itemID: item.id,
                selection: selection,
                mode: .balanced,
                startTimeTicks: startTimeTicks,
                itemPrefersDolbyVision: itemPrefersDolbyVision
            )
        }
        let guarantees = resolvedRouteGuarantees(for: selection)
        if blockAutomaticDestructiveFallbackIfNeeded(
            selection: selection,
            guarantees: guarantees,
            reason: reason
        ) {
            throw AppError.network(playbackErrorMessage ?? "Playback needs a quality fallback choice.")
        }
        _ = registerAttempt(selection: selection, profile: activeTranscodeProfile)
        await loadCoordinatorFallbackSelection(
            selection,
            resumeSeconds: resumeSeconds,
            runtimeSeconds: item.runtimeTicks.map { Double($0) / 10_000_000 },
            autoPlay: autoPlay
        )
    }

    private func resolveCoordinatorFallbackSelection(
        itemID: String,
        startTimeTicks: Int64?,
        itemPrefersDolbyVision: Bool,
        reason: String
    ) async throws -> PlaybackAssetSelection {
        activeTranscodeProfile = .serverDefault
        var selection = try await coordinator.resolvePlayback(
            itemID: itemID,
            mode: .balanced,
            allowTranscodingFallbackInPerformance: !usesDirectRemuxOnly,
            transcodeProfile: activeTranscodeProfile,
            startTimeTicks: startTimeTicks,
            nativeEngineFallbackReason: reason
        )
        selection = try await pinPreferredVariantIfNeeded(
            selection: selection,
            itemPrefersDolbyVision: itemPrefersDolbyVision,
            profileOverride: Self.variantPinningProfile(
                from: selection.assetURL,
                requestedProfile: activeTranscodeProfile
            )
        )
        selection = try await stabilizeInitialSelectionIfNeeded(
            itemID: itemID,
            selection: selection,
            startTimeTicks: startTimeTicks,
            itemPrefersDolbyVision: itemPrefersDolbyVision
        )
        selection = try await upgradeRiskyInitialSelectionIfNeeded(
            itemID: itemID,
            selection: selection,
            startTimeTicks: startTimeTicks,
            itemPrefersDolbyVision: itemPrefersDolbyVision
        )
        selection = try await preemptHighRiskProgressiveDirectPlayIfNeeded(
            itemID: itemID,
            selection: selection,
            startTimeTicks: startTimeTicks,
            maxStreamingBitrate: currentMaxStreamingBitrate,
            itemPrefersDolbyVision: itemPrefersDolbyVision
        )
        activeTranscodeProfile = inferredActiveProfile(for: selection, fallback: activeTranscodeProfile)
        return selection
    }

    private func loadCoordinatorFallbackSelection(
        _ selection: PlaybackAssetSelection,
        resumeSeconds: Double?,
        runtimeSeconds: Double?,
        autoPlay: Bool
    ) async {
        isNativePlayerActive = false
        nativePlayerPlaybackSurface = .appleNative
        nativePlayerDiagnosticsOverlayLines = []
        nativePlayerPlaybackURL = nil
        nativePlayerPlaybackHeaders = [:]
        nativePlayerStartTimeSeconds = nil
        await nativeBridgeSession?.invalidate()
        nativeBridgeSession = nil
        syntheticHLSSession = nil
        localHLSServer?.stop(reason: "native_apple_container_coordinator_fallback")
        localHLSServer = nil
        localHLSStartupSummary = nil

        if case .directPlay = selection.decision.route {
            transcodeStartOffset = 0
            await loadDirectPlaySelectionAtResumePosition(selection, resumeSeconds: resumeSeconds)
        } else {
            transcodeStartOffset = Self.initialTranscodeStartOffset(for: selection, resumeSeconds: resumeSeconds)
            prepareAndLoadSelection(selection, resumeSeconds: resumeSeconds)
        }

        if autoPlay {
            _ = runtimeSeconds
            play()
            scheduleDecodedFrameWatchdog()
            scheduleStartupWatchdog()
        }
    }

    private func applyPreparedNativePlayerSnapshot(
        _ snapshot: NativePlayerPlaybackSnapshot,
        resumeSeconds: Double?,
        runtimeSeconds: Double?,
        autoPlay: Bool
    ) async throws {
        if snapshot.surface == .appleNative, let selection = snapshot.applePlaybackSelection {
            var selection = selection
            let sanitizedResumeSeconds = max(0, resumeSeconds ?? 0)
            let resumeTimeTicks: Int64? = sanitizedResumeSeconds > 0
                ? Int64(sanitizedResumeSeconds * 10_000_000)
                : nil
            selection = try await preemptHighRiskProgressiveDirectPlayIfNeeded(
                itemID: selection.source.itemID,
                selection: selection,
                startTimeTicks: resumeTimeTicks,
                maxStreamingBitrate: currentMaxStreamingBitrate,
                itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                    itemPrefersDolbyVision: currentItemHasDolbyVision || selection.source.isLikelyHDRorDV,
                    source: selection.source
                )
            )
            let shouldUseStartupGateway = autoPlay
                ? await shouldUseLocalMediaGatewayForStartup(selection: selection, resumeSeconds: sanitizedResumeSeconds)
                : false
            if shouldUseStartupGateway {
                logPrestartEvidenceSkipped(selection: selection, reason: "local_gateway_startup")
            }
            let preheatTask = autoPlay
                ? (
                    shouldUseStartupGateway
                    ? makeCachedStartupPreheatTask(
                        selection: selection,
                        resumeSeconds: sanitizedResumeSeconds,
                        runtimeSeconds: runtimeSeconds
                    )
                    : makeStartupPreheatTask(
                        selection: selection,
                        resumeSeconds: sanitizedResumeSeconds,
                        runtimeSeconds: runtimeSeconds
                    )
                )
                : nil
            let serverBaselineTask = autoPlay && !shouldUseStartupGateway
                ? makeServerBaselineTask(selection: selection)
                : nil
            let autoplayGateOwnsResumeSeek = Self.shouldAutoplayStartupGateOwnDirectPlayResumeSeek(
                route: selection.decision.route,
                autoPlay: autoPlay,
                resumeSeconds: sanitizedResumeSeconds
            )
            directPlayAutoplayStartupGateOwnsResumeSeek = autoplayGateOwnsResumeSeek
            isNativePlayerActive = false
            nativePlayerPlaybackSurface = .appleNative
            nativePlayerDiagnosticsOverlayLines = []
            nativePlayerPlaybackURL = nil
            nativePlayerPlaybackHeaders = [:]
            nativePlayerStartTimeSeconds = nil
            playbackErrorMessage = snapshot.playbackErrorMessage
            if case .directPlay = selection.decision.route {
                transcodeStartOffset = 0
                await loadDirectPlaySelectionAtResumePosition(selection, resumeSeconds: resumeSeconds)
            } else {
                transcodeStartOffset = Self.initialTranscodeStartOffset(
                    for: selection,
                    resumeSeconds: sanitizedResumeSeconds
                )
                prepareAndLoadSelection(selection, resumeSeconds: resumeSeconds)
            }
            if autoPlay {
                defer {
                    if autoplayGateOwnsResumeSeek {
                        directPlayAutoplayStartupGateOwnsResumeSeek = false
                    }
                }
                let evidence = await resolvePrestartEvidence(
                    selection: selection,
                    preheatTask: preheatTask,
                    serverBaselineTask: serverBaselineTask
                )
                let preheatResult = evidence.preheatResult
                let serverBaselineResult = evidence.serverBaselineResult
                if let prestartReason = Self.directPlayPrestartRecoveryReason(
                    route: selection.decision.route,
                    sourceBitrate: selection.source.bitrate,
                    sourceIsHDRorDV: selection.source.isLikelyHDRorDV,
                    preheatResult: preheatResult,
                    serverBaselineResult: serverBaselineResult,
                    isTVOS: Self.isTvOSPlatform
                ) {
                    logDirectPlayPrestartHeadroom(
                        selection: selection,
                        preheatResult: preheatResult,
                        serverBaselineResult: serverBaselineResult,
                        reason: prestartReason,
                        action: "profile_fallback"
                    )
                    if await attemptStartupRecoveryIfAvailable(
                        reason: prestartReason.rawValue,
                        userMessage: "Direct Play network preflight was too weak. Switching playback profile."
                    ) {
                        return
                    }
                }
                logUnsafeDirectPlayStartupHeadroomIfNeeded(
                    selection: selection,
                    preheatResult: preheatResult,
                    serverBaselineResult: serverBaselineResult
                )
                let startupResumePositionReady = await ensureDirectPlayResumePositionBeforeAutoplayIfNeeded(
                    selection: selection,
                    resumeSeconds: sanitizedResumeSeconds,
                    phase: "startup_preplay",
                    waitForItemReady: true
                )
                if !startupResumePositionReady,
                   Self.shouldBlockAutoplayAfterUnsafeStartup(
                    route: selection.decision.route,
                    source: selection.source,
                    runtimeSeconds: runtimeSeconds,
                    resumeSeconds: sanitizedResumeSeconds,
                    isTVOS: Self.isTvOSPlatform
                   ) {
                    logStartupRecoveryUnavailable(
                        reason: "directplay_resume_seek_not_ready",
                        action: "block_autoplay"
                    )
                    blockUnsafeDirectPlayStartupPlayback(
                        reason: "directplay_resume_seek_not_ready",
                        userMessage: "Playback could not resume safely. Try again or use a lower quality profile."
                    )
                    return
                }
                let startupReady = await performStartupReadinessGateIfNeeded(
                    selection: selection,
                    resumeSeconds: sanitizedResumeSeconds,
                    runtimeSeconds: runtimeSeconds,
                    preheatResult: preheatResult,
                    serverBaselineResult: serverBaselineResult,
                    maxStreamingBitrate: currentMaxStreamingBitrate
                )
                if !startupReady {
                    if Self.shouldBlockAutoplayAfterUnsafeStartup(
                        route: selection.decision.route,
                        source: selection.source,
                        runtimeSeconds: runtimeSeconds,
                        resumeSeconds: sanitizedResumeSeconds,
                        isTVOS: Self.isTvOSPlatform
                    ) {
                        logStartupRecoveryUnavailable(
                            reason: StartupFailureReason.startupReadinessTimeout.rawValue,
                            action: "block_autoplay"
                        )
                        blockUnsafeDirectPlayStartupPlayback(
                            reason: StartupFailureReason.startupReadinessTimeout.rawValue,
                            userMessage: "Playback did not build a safe buffer. Try again or use a lower quality profile."
                        )
                        return
                    }
                    logStartupRecoveryUnavailable(
                        reason: StartupFailureReason.startupReadinessTimeout.rawValue,
                        action: "continue_current_item"
                    )
                }
                if !(await prepareSynchronizedStartupFrameIfNeeded(selection: selection)) {
                    if Self.shouldBlockAutoplayAfterUnsafeStartup(
                        route: selection.decision.route,
                        source: selection.source,
                        runtimeSeconds: runtimeSeconds,
                        resumeSeconds: sanitizedResumeSeconds,
                        isTVOS: Self.isTvOSPlatform
                    ) {
                        logStartupRecoveryUnavailable(
                            reason: StartupFailureReason.startupVideoPrerollTimeout.rawValue,
                            action: "block_autoplay"
                        )
                        blockUnsafeDirectPlayStartupPlayback(
                            reason: StartupFailureReason.startupVideoPrerollTimeout.rawValue,
                            userMessage: "Video did not become ready before playback. Try again or use a lower quality profile."
                        )
                        return
                    }
                    logStartupRecoveryUnavailable(
                        reason: StartupFailureReason.startupVideoPrerollTimeout.rawValue,
                        action: "force_autoplay"
                    )
                }
                let resumePositionReady = await ensureDirectPlayResumePositionBeforeAutoplayIfNeeded(
                    selection: selection,
                    resumeSeconds: sanitizedResumeSeconds,
                    phase: "preplay",
                    waitForItemReady: false
                )
                if !resumePositionReady,
                   Self.shouldBlockAutoplayAfterUnsafeStartup(
                    route: selection.decision.route,
                    source: selection.source,
                    runtimeSeconds: runtimeSeconds,
                    resumeSeconds: sanitizedResumeSeconds,
                    isTVOS: Self.isTvOSPlatform
                   ) {
                    logStartupRecoveryUnavailable(
                        reason: "directplay_resume_seek_not_ready",
                        action: "block_autoplay"
                    )
                    blockUnsafeDirectPlayStartupPlayback(
                        reason: "directplay_resume_seek_not_ready",
                        userMessage: "Playback could not resume safely. Try again or use a lower quality profile."
                    )
                    return
                }
                directPlayStartupPlaybackBlocked = false
                play()
                scheduleDecodedFrameWatchdog()
                scheduleStartupWatchdog()
            }
            return
        }
        applyNativePlayerSnapshot(snapshot)
    }

    private func makeStartupPreheatTask(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?
    ) -> Task<PlaybackStartupPreheater.Result?, Never>? {
        guard PlaybackStartupReadinessPolicy.requiresStartupPreheat(
            route: selection.decision.route,
            sourceBitrate: selection.source.bitrate,
            sourceIsHDRorDV: selection.source.isLikelyHDRorDV,
            runtimeSeconds: runtimeSeconds,
            resumeSeconds: resumeSeconds,
            isTVOS: Self.isTvOSPlatform
        ) else {
            return nil
        }

        let warmupManager = warmupManager
        return Task(priority: .utility) {
            if let cachedResult = await warmupManager?.startupPreheatResult(
                for: selection,
                resumeSeconds: resumeSeconds,
                runtimeSeconds: runtimeSeconds,
                isTVOS: Self.isTvOSPlatform
            ) {
                return cachedResult
            }

            if let warmedResult = await warmupManager?.warm(
                selection: selection,
                resumeSeconds: resumeSeconds,
                runtimeSeconds: runtimeSeconds,
                isTVOS: Self.isTvOSPlatform
            ) {
                return warmedResult
            }

            return await PlaybackStartupPreheater.preheat(
                selection: selection,
                resumeSeconds: resumeSeconds,
                runtimeSeconds: runtimeSeconds,
                isTVOS: Self.isTvOSPlatform
            )
        }
    }

    private func makeCachedStartupPreheatTask(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?
    ) -> Task<PlaybackStartupPreheater.Result?, Never>? {
        guard let warmupManager else { return nil }
        return Task(priority: .utility) {
            await warmupManager.startupPreheatResult(
                for: selection,
                resumeSeconds: resumeSeconds,
                runtimeSeconds: runtimeSeconds,
                isTVOS: Self.isTvOSPlatform
            )
        }
    }

    private func makeServerBaselineTask(
        selection: PlaybackAssetSelection
    ) -> Task<PlaybackServerNetworkBaseline.Result?, Never>? {
        guard PlaybackServerNetworkBaseline.isEligible(selection: selection) else {
            return nil
        }

        let warmupManager = warmupManager
        return Task(priority: .utility) {
            if let cachedResult = await warmupManager?.serverBaselineResult(
                for: selection,
                isTVOS: Self.isTvOSPlatform
            ) {
                return cachedResult
            }

            if let warmedResult = await warmupManager?.warmServerBaselineIfNeeded(
                selection: selection,
                isTVOS: Self.isTvOSPlatform
            ) {
                return warmedResult
            }

            return await PlaybackServerNetworkBaseline.warm(
                selection: selection,
                isTVOS: Self.isTvOSPlatform
            )
        }
    }

    private func shouldUseLocalMediaGatewayForStartup(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double?
    ) async -> Bool {
        guard case .directPlay = selection.decision.route else { return false }
        guard mediaGatewayStore != nil else { return false }
        guard !localMediaGatewayDisabledSourceIDs.contains(selection.source.id) else { return false }
        guard LocalMediaGatewayURLPolicy.isSupportedRemoteURL(selection.assetURL) else { return false }
        guard let configuration = await apiClient.currentConfiguration() else { return false }

        var cachedBytes: Int64 = 0
        if let store = mediaGatewayStore, let session = await apiClient.currentSession() {
            let key = mediaGatewayKey(
                selection: selection,
                configuration: configuration,
                session: session
            )
            cachedBytes = ((try? await store.coveredRanges(key: key)) ?? [])
                .reduce(0) { $0 + Int64($1.length) }
        }

        return LocalMediaGatewayRoutePolicy.shouldUseGateway(
            route: selection.decision.route,
            source: selection.source,
            mediaCacheMode: configuration.mediaCacheMode,
            isTVOS: Self.isTvOSPlatform,
            resumeSeconds: resumeSeconds,
            hasCachedBytes: cachedBytes > 0,
            cachedBytes: cachedBytes
        )
    }

    private func logPrestartEvidenceSkipped(selection: PlaybackAssetSelection, reason: String) {
        AppLog.playback.info(
            "playback.prestart.evidence.skipped — \(self.playbackLogScope(), privacy: .public) source=\(selection.source.id, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    private func resolvePrestartEvidence(
        selection: PlaybackAssetSelection,
        preheatTask: Task<PlaybackStartupPreheater.Result?, Never>?,
        serverBaselineTask: Task<PlaybackServerNetworkBaseline.Result?, Never>?
    ) async -> (
        preheatResult: PlaybackStartupPreheater.Result?,
        serverBaselineResult: PlaybackServerNetworkBaseline.Result?
    ) {
        let routeMarkedFragile = Self.isDirectPlayRouteMarkedFragile(
            route: selection.decision.route,
            source: selection.source
        )

        if let preheatTask, let serverBaselineTask {
            return await resolveRacedPrestartEvidence(
                selection: selection,
                preheatTask: preheatTask,
                serverBaselineTask: serverBaselineTask,
                routeMarkedFragile: routeMarkedFragile
            )
        }

        if let preheatResult = await preheatTask?.value {
            return (preheatResult, nil)
        }

        let serverBaselineResult = await serverBaselineTask?.value
        if shouldUseServerBaselineEvidence(
            serverBaselineResult,
            selection: selection,
            routeMarkedFragile: routeMarkedFragile
        ) {
            return (nil, serverBaselineResult)
        }
        return (nil, routeMarkedFragile ? nil : serverBaselineResult)
    }

    private func resolveRacedPrestartEvidence(
        selection: PlaybackAssetSelection,
        preheatTask: Task<PlaybackStartupPreheater.Result?, Never>,
        serverBaselineTask: Task<PlaybackServerNetworkBaseline.Result?, Never>,
        routeMarkedFragile: Bool
    ) async -> (
        preheatResult: PlaybackStartupPreheater.Result?,
        serverBaselineResult: PlaybackServerNetworkBaseline.Result?
    ) {
        await withTaskGroup(of: PrestartEvidenceEvent.self) { group in
            group.addTask { .preheat(await preheatTask.value) }
            group.addTask { .serverBaseline(await serverBaselineTask.value) }

            var pendingPreheat = true
            var pendingBaseline = true
            var latestBaselineResult: PlaybackServerNetworkBaseline.Result?

            while let event = await group.next() {
                switch event {
                case let .preheat(preheatResult):
                    pendingPreheat = false
                    if let preheatResult {
                        group.cancelAll()
                        return (preheatResult, nil)
                    }
                    if !pendingBaseline {
                        return (nil, routeMarkedFragile ? nil : latestBaselineResult)
                    }

                case let .serverBaseline(serverBaselineResult):
                    pendingBaseline = false
                    latestBaselineResult = serverBaselineResult
                    if shouldUseServerBaselineEvidence(
                        serverBaselineResult,
                        selection: selection,
                        routeMarkedFragile: routeMarkedFragile
                    ) {
                        preheatTask.cancel()
                        group.cancelAll()
                        return (nil, serverBaselineResult)
                    }
                    if !pendingPreheat {
                        return (nil, routeMarkedFragile ? nil : serverBaselineResult)
                    }
                }
            }

            return (nil, routeMarkedFragile ? nil : latestBaselineResult)
        }
    }

    private func shouldUseServerBaselineEvidence(
        _ serverBaselineResult: PlaybackServerNetworkBaseline.Result?,
        selection: PlaybackAssetSelection,
        routeMarkedFragile: Bool
    ) -> Bool {
        guard let serverBaselineResult, !routeMarkedFragile else {
            return false
        }

        let decision = Self.directPlayStartupDecision(
            route: selection.decision.route,
            sourceBitrate: selection.source.bitrate,
            sourceIsHDRorDV: selection.source.isLikelyHDRorDV,
            preheatResult: nil,
            serverBaselineResult: serverBaselineResult,
            isTVOS: Self.isTvOSPlatform
        )
        return decision.failureReason == nil
    }

    private enum PrestartEvidenceEvent: Sendable {
        case preheat(PlaybackStartupPreheater.Result?)
        case serverBaseline(PlaybackServerNetworkBaseline.Result?)
    }

    private func applyNativePlayerSnapshot(_ snapshot: NativePlayerPlaybackSnapshot) {
        isNativePlayerActive = true
        nativePlayerPlaybackSurface = snapshot.surface
        nativePlayerDiagnosticsOverlayLines = snapshot.overlayLines
        nativePlayerPlaybackURL = snapshot.playbackURL
        nativePlayerPlaybackHeaders = snapshot.playbackHeaders
        nativePlayerStartTimeSeconds = snapshot.startTimeSeconds
        routeDescription = snapshot.routeDescription
        playbackErrorMessage = snapshot.playbackErrorMessage
        availableAudioTracks = snapshot.audioTracks
        availableSubtitleTracks = snapshot.subtitleTracks
        selectedAudioTrackID = snapshot.selectedAudioTrackID
        selectedSubtitleTrackID = snapshot.selectedSubtitleTrackID
        playMethodForReporting = "NativeEngine"
        debugInfo = PlaybackDebugInfo(
            container: "local-original",
            videoCodec: "see diagnostics",
            videoBitDepth: nil,
            hdrMode: .unknown,
            audioMode: "see diagnostics",
            bitrate: nil,
            playMethod: "NativeEngine"
        )
        endTransportStateSnapshotBatch(commitNow: true)
    }

    private func prepareAndLoadSelection(_ selection: PlaybackAssetSelection, resumeSeconds: Double?) {
        // Adaptive fallback: a `.transcode` selection IS the intended escape when direct play can't
        // be sustained (connection below the original bitrate). Allow it through the native-engine
        // route guard — that's how the player stays reliable without ever freezing. The guard still
        // blocks non-transcode routes that would wrongly bypass the native engine.
        let isAdaptiveTranscodeFallback: Bool = {
            guard AdaptiveFallbackPolicy.isEnabled else { return false }
            if case .transcode = selection.decision.route { return true }
            return false
        }()
        if isAdaptiveTranscodeFallback {
            // We are intentionally leaving native-engine mode for a transcode fallback.
            isNativePlayerActive = false
            AppLog.playback.notice(
                "playback.adaptive.fallback.allowed — \(self.playbackLogScope(), privacy: .public) route=transcode reason=connection_cannot_sustain_direct"
            )
        }
        if !isAdaptiveTranscodeFallback, Self.shouldBlockLegacyCoordinatorRecovery(
            isNativePlayerActive: isNativePlayerActive,
            nativeSurface: nativePlayerPlaybackSurface
        ) {
            let proof = NativePlayerRouteProof(
                usedLegacyPlaybackCoordinator: true,
                createdAVPlayerItem: true,
                usedAVPlayerViewController: true,
                transcodeProfile: activeTranscodeProfile.rawValue,
                selectedURL: selection.assetURL
            )
            let reason = NativePlayerRouteGuard.firstViolationDescription(for: proof)
                ?? "Native engine route guard blocked a legacy playback selection."
            AppLog.playback.error("nativeplayer.route.guard.blocked — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public)")
            playbackErrorMessage = reason
            return
        }
        guard isActivePlaybackTarget(itemID: selection.source.itemID) else {
            AppLog.playback.warning(
                "playback.asset.stale_prepare_skipped — \(Self.playbackLogScope(sessionID: self.playbackLogSessionID, itemID: selection.source.itemID), privacy: .public) activeItem=\(self.currentItemID.map { AppLogFormat.shortIdentifier($0) } ?? "none", privacy: .public)"
            )
            return
        }
        switch selection.decision.route {
        case .directPlay:
            break
        case .remux, .transcode, .nativeBridge:
            stopLocalMediaGateway(reason: "prepare_non_direct_route")
        }

        trickplayRefreshTask?.cancel()
        lastPreparedSelection = selection
        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
        decodedFrameWatchdogTask?.cancel()
        decodedFrameWatchdogTask = nil
        videoOutputPollTask?.cancel()
        videoOutputPollTask = nil
        remoteProgressReportTask?.cancel()
        remoteProgressReportTask = nil
        pendingRemoteProgressUpdate = nil
        startupSubtitleSelectionTask?.cancel()
        startupSubtitleSelectionTask = nil
        videoValidationTask?.cancel()
        videoValidationTask = nil
        videoOutput = nil
        videoFormatSnapshotTask?.cancel()
        videoFormatSnapshotTask = nil
        cachedVideoFormatSnapshot = nil
        activeTranscodeProfile = inferredActiveProfile(for: selection, fallback: activeTranscodeProfile)
        currentSource = selection.source
        // Keep runtime quality mode tied to explicit policy/user settings.
        debugInfo = selection.debugInfo
        let resolvedRouteGuarantees = resolvedRouteGuarantees(for: selection)
        routeGuarantees = resolvedRouteGuarantees
        playbackDiagnostics.recordRouteGuarantees(resolvedRouteGuarantees)
        publishFallbackIfNeededForDestructiveRoute(selection: selection, guarantees: resolvedRouteGuarantees)
        currentPlaybackPlan = selection.playbackPlan ?? selection.decision.playbackPlan
        if let plan = currentPlaybackPlan {
            playbackDiagnostics.recordPlan(plan)
        }
        runtimeHDRMode = selection.debugInfo.hdrMode
        playMethodForReporting = selection.decision.playMethod
        let selectionRoute = routeLabel(for: selection.decision.route)
        let resumeLabel = resumeSeconds.map { String(format: "%.1fs", $0) } ?? "none"
        AppLog.playback.notice(
            "playback.load.selection — \(self.playbackLogScope(), privacy: .public) route=\(selectionRoute, privacy: .public) method=\(selection.decision.playMethod, privacy: .public) profile=\(self.activeTranscodeProfile.rawValue, privacy: .public) resume=\(resumeLabel, privacy: .public) guarantee=\(resolvedRouteGuarantees.userVisibleSummary, privacy: .public) url=\(selection.assetURL.reelfinCompactLogString, privacy: .public)"
        )
        let deviceCaps = DeviceCapabilityFingerprint.current()
        let routeIsNativeApple = Self.isAppleNativePlaybackPath(
            playMethod: playMethodForReporting,
            assetURL: selection.assetURL
        )
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
            selectedMasterPlaylistURL: selectedMasterPlaylistURL?.reelfinCompactLogString,
            selectedVariantURL: selectedVariantInfo?.resolvedURL.reelfinCompactLogString,
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
            recoverySuggestion: lastRecoverySuggestion,
            routeGuaranteeSummary: resolvedRouteGuarantees.userVisibleSummary,
            videoIntegrity: resolvedRouteGuarantees.videoIntegrity.rawValue,
            hdrIntegrity: resolvedRouteGuarantees.hdrIntegrity.rawValue,
            startupClass: resolvedRouteGuarantees.startupClass.rawValue,
            preservesOriginalVideo: resolvedRouteGuarantees.preservesOriginalVideo,
            preservesDolbyVision: resolvedRouteGuarantees.preservesDolbyVision,
            preservesHDR: resolvedRouteGuarantees.preservesHDR,
            healthState: playbackHealth.state.rawValue,
            observedSafetyRatio: playbackHealth.safetyRatio,
            requiredBitrate: playbackHealth.requiredBitrate,
            localMediaGatewayEnabled: Self.isLocalMediaGatewayURL(selection.assetURL),
            finalURL: selection.assetURL.reelfinCompactLogString
        )

        availableAudioTracks = selection.source.audioTracks
        availableSubtitleTracks = selection.source.subtitleTracks
        playbackTimeOffsetSeconds = transcodeStartOffset
        activeTrickplayManifest = nil
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
        let selectedAudioTitle = preferredAudioTrack?.title ?? "none"
        let selectedAudioLanguage = preferredAudioTrack?.language ?? "?"
        let selectedAudioDefault = preferredAudioTrack?.isDefault ?? false
        PlayerDeepEvidenceSink.append(
            "playback.audio.selection — \(playbackLogScope()) track='\(selectedAudioTitle)' lang='\(selectedAudioLanguage)' codec=\(audioSelection.selectedCodec) default=\(selectedAudioDefault) reason=\(audioSelection.reason)"
        )
        AppLog.playback.info(
            "playback.audio.selection — \(self.playbackLogScope(), privacy: .public) track='\(preferredAudioTrack?.title ?? "none", privacy: .public)' lang='\(preferredAudioTrack?.language ?? "?", privacy: .public)' codec=\(audioSelection.selectedCodec, privacy: .public) default=\(preferredAudioTrack?.isDefault ?? false, privacy: .public) reason=\(audioSelection.reason, privacy: .public)"
        )
        if audioSelection.trueHDWasDeprioritized {
            AppLog.playback.notice("\(PlaybackFailureReason.trueHDDeprioritizedForNativePath.localizedDescription, privacy: .public)")
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
            if subtitlePolicy.shouldBlockSubtitleSelection(
                track: track,
                strictMode: strictQualityIsActive,
                sourceIsHDRorDV: selection.source.isLikelyHDRorDV,
                sourceIs4K: selection.source.isLikely4K
            ) {
                selectedSubtitleTrackID = nil
                fallbackRecommendation = PlaybackFallbackRecommendationFactory.subtitleBurnInRecommendation(
                    source: selection.source,
                    subtitleTrack: track
                )
                AppLog.playback.warning(
                    "playback.subtitle.auto_blocked — \(self.playbackLogScope(), privacy: .public) track='\(track.title, privacy: .public)' guarantee=\(self.routeGuarantees.userVisibleSummary, privacy: .public)"
                )
            } else {
                AppLog.playback.info(
                    "playback.subtitle.selection — \(self.playbackLogScope(), privacy: .public) track='\(track.title, privacy: .public)' lang='\(track.language ?? "?", privacy: .public)' default=\(track.isDefault, privacy: .public) forced=\(track.isForced, privacy: .public)"
                )
            }
        }
        endTransportStateSnapshotBatch(commitNow: true)
        refreshTrickplayManifest(for: selection)

        routeDescription = resolvedRouteGuarantees.userVisibleSummary

        // ── HDR / DV expectation log ─────────────────────────────────────────────
        // Emit an honest single-line summary of what dynamic range this session
        // expects to deliver, and why.  This makes "did DV survive the pipeline?"
        // answerable from logs without a full diagnostics session.
        emitDynamicRangeExpectationLog(selection: selection)

        let startupPolicy = PlaybackStartupPolicy.configuration(for: resolvedRouteGuarantees.startupClass)
        var forwardBuffer = startupPolicy.preferredForwardBufferDuration
        var waitsToMinimize = startupPolicy.automaticallyWaitsToMinimizeStalling

        forwardBuffer = PlaybackTVOSCachingPolicy.startupForwardBufferDuration(
            baseBufferDuration: forwardBuffer,
            route: selection.decision.route,
            runtimeSeconds: currentMediaItem?.runtimeTicks.map { Double($0) / 10_000_000 },
            isTVOS: Self.isTvOSPlatform
        )

        let directPlayPolicy = Self.directPlayStabilityPolicy(
            route: selection.decision.route,
            source: selection.source,
            defaultForwardBufferDuration: forwardBuffer,
            defaultWaitsToMinimizeStalling: waitsToMinimize,
            maxStreamingBitrate: currentMaxStreamingBitrate,
            isTVOS: Self.isTvOSPlatform
        )
        if directPlayPolicy.forwardBufferDuration != forwardBuffer
            || directPlayPolicy.waitsToMinimizeStalling != waitsToMinimize {
            let reason = directPlayPolicy.reason ?? "directplay_buffering_override"
            AppLog.playback.notice(
                "playback.directplay.buffering_override — \(self.playbackLogScope(), privacy: .public) buffer=\(directPlayPolicy.forwardBufferDuration, format: .fixed(precision: 1)) waits=\(directPlayPolicy.waitsToMinimizeStalling, privacy: .public) reason=\(reason, privacy: .public)"
            )
        }
        forwardBuffer = directPlayPolicy.forwardBufferDuration
        waitsToMinimize = directPlayPolicy.waitsToMinimizeStalling

        if isLocalSyntheticHLSURL(selection.assetURL) {
            // NativeBridge local HLS startup: bias for earliest first frame.
            forwardBuffer = min(forwardBuffer, 0.25)
            waitsToMinimize = false
        }

        player.automaticallyWaitsToMinimizeStalling = waitsToMinimize

        if let urlValidationError = assetURLValidator.validate(url: selection.assetURL) {
            AppLog.playback.error("playback.asset.invalid — \(self.playbackLogScope(), privacy: .public) reason=\(urlValidationError.localizedDescription, privacy: .public)")
            playbackErrorMessage = urlValidationError.localizedDescription
            return
        }
        AppLog.playback.notice("playback.asset.prepare — \(self.playbackLogScope(), privacy: .public) url=\(selection.assetURL.reelfinCompactLogString, privacy: .public)")

        let asset: AVURLAsset
        if let bridgeSession = self.nativeBridgeSession {
            asset = bridgeSession.makeAsset()
        } else {
            if isLocalSyntheticHLSURL(selection.assetURL) {
                guard let localHLSServer else {
                    AppLog.nativeBridge.error("[NB-DIAG] hls.server.missing-before-avasset — url=\(selection.assetURL.reelfinLogString, privacy: .public)")
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
            let assetOptions = Self.avURLAssetOptions(for: selection)
            if let overrideMIMEType = assetOptions[AVURLAssetOverrideMIMETypeKey] as? String {
                AppLog.playback.notice(
                    "playback.asset.mime_override — \(self.playbackLogScope(), privacy: .public) mime=\(overrideMIMEType, privacy: .public) reason=extensionless_directplay"
                )
            }
            if !selection.headers.isEmpty {
                AppLog.playback.notice(
                    "playback.asset.headers_ignored — \(self.playbackLogScope(), privacy: .public) headerCount=\(selection.headers.count, privacy: .public)"
                )
            }
            if let store = mediaGatewayStore,
               LocalCacheProxyRoutePolicy.shouldUseProxy(
                   route: selection.decision.route,
                   source: selection.source,
                   assetURL: selection.assetURL,
                   isTVOS: Self.isTvOSPlatform,
                   hasStore: true
               ) {
                // Infuse-class never-cut: AVPlayer reads the deep local cache over http://127.0.0.1
                // (DV renders — unlike the custom reelfin-cache scheme), while the parallel
                // downloader fills ahead of the playhead. Origin dropouts can't drain AVPlayer's
                // buffer because it is fed from disk. Same proven OriginDownloader + MediaGatewayStore
                // as the cache loader; only the DELIVERY differs (localhost HTTP vs custom scheme).
                let overrideMIME = assetOptions[AVURLAssetOverrideMIMETypeKey] as? String
                let key = cacheLoaderKey(for: selection)
                let downloader = OriginDownloader(
                    remoteURL: selection.assetURL,
                    headers: selection.headers,
                    key: key,
                    store: store,
                    overrideContentType: overrideMIME,
                    sessionConfiguration: MediaOriginTransport.makeConfiguration()
                )
                let server = LocalCacheHTTPServer(
                    store: store,
                    downloader: downloader,
                    key: key,
                    remoteURL: selection.assetURL,
                    headers: selection.headers,
                    overrideMIMEType: overrideMIME
                )
                do {
                    let localURL = try server.start()
                    cacheOriginDownloader = downloader
                    cacheProxyServer = server
                    asset = AVURLAsset(url: localURL, options: assetOptions)
                    Task { await downloader.primeStart() }
                    AppLog.playback.notice(
                        "playback.cachehttp.asset.created — \(self.playbackLogScope(), privacy: .public) local=\(localURL.reelfinCompactLogString, privacy: .public) origin=\(selection.assetURL.reelfinCompactLogString, privacy: .public) overrideMIME=\(overrideMIME ?? "-", privacy: .public)"
                    )
                } catch {
                    // Listener failed to start — fall back to plain direct play (origin URL).
                    server.stop(reason: "listener_start_failed")
                    asset = AVURLAsset(url: selection.assetURL, options: assetOptions)
                    AppLog.playback.warning(
                        "playback.cachehttp.start_failed — \(self.playbackLogScope(), privacy: .public) reason=\(error.localizedDescription, privacy: .public) fallback=direct_play"
                    )
                }
            } else if let store = mediaGatewayStore,
               CacheLoaderRoutePolicy.shouldUseCacheLoader(
                   route: selection.decision.route,
                   source: selection.source,
                   assetURL: selection.assetURL,
                   isTVOS: Self.isTvOSPlatform,
                   hasStore: true
               ) {
                // Raw original bytes served from the app cache; one keep-alive downloader fills
                // ahead and resumes through drops. No HLS → Dolby Vision preserved. The override
                // MIME (extensionless DV originals) is replicated into the loader's content type.
                let overrideMIME = assetOptions[AVURLAssetOverrideMIMETypeKey] as? String
                let key = cacheLoaderKey(for: selection)
                let downloader = OriginDownloader(
                    remoteURL: selection.assetURL,
                    headers: selection.headers,
                    key: key,
                    store: store,
                    overrideContentType: overrideMIME,
                    sessionConfiguration: MediaOriginTransport.makeConfiguration()
                )
                let loader = CacheResourceLoaderDelegate(
                    store: store,
                    downloader: downloader,
                    key: key,
                    overrideMIMEType: overrideMIME
                )
                cacheOriginDownloader = downloader
                cacheResourceLoader = loader
                asset = loader.makeAsset(for: selection.source.itemID)
                Task { await downloader.primeStart() }
                AppLog.playback.notice(
                    "playback.cacheloader.asset.created — \(self.playbackLogScope(), privacy: .public) url=\(selection.assetURL.reelfinCompactLogString, privacy: .public) overrideMIME=\(overrideMIME ?? "-", privacy: .public)"
                )
            } else {
                asset = AVURLAsset(url: selection.assetURL, options: assetOptions)
                AppLog.nativeBridge.notice("[NB-DIAG] avasset.created — \(self.playbackLogScope(), privacy: .public) url=\(selection.assetURL.reelfinCompactLogString, privacy: .public)")
            }
        }
        startupTrace.assetCreatedAt = Date()

        let playerItem = AVPlayerItem(asset: asset)
        startupTrace.itemCreatedAt = Date()
        AppLog.nativeBridge.notice("[NB-DIAG] avplayeritem.created — \(self.playbackLogScope(), privacy: .public) method=\(self.playMethodForReporting, privacy: .public)")
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        Self.applyMultichannelAudioSpatializationPolicy(to: playerItem)
        installVideoOutputProbeIfNeeded(
            on: playerItem,
            route: selection.decision.route,
            source: selection.source
        )
        playerItem.preferredForwardBufferDuration = forwardBuffer
        currentForwardBufferDuration = forwardBuffer

        readyInterval = SignpostInterval(signposter: Signpost.playerLifecycle, name: "avplayer_item_ready")
        firstFrameInterval = SignpostInterval(signposter: Signpost.playerLifecycle, name: "avplayer_first_frame")
        hasMarkedFirstFrame = false
        firstFrameDate = nil
        lastDeepPlaybackEvidenceLogDate = nil
        lastDeepPlaybackEvidencePlaybackTime = nil
        hasDecodedVideoFrame = false
        avkitReadyForDisplay = false
        didApplyStartupSubtitleSelection = false
        startDate = Date()

        player.pause()
        player.replaceCurrentItem(with: playerItem)
        configureObservers(for: playerItem)
        scheduleVideoFormatSnapshotLoad(for: playerItem)
        updatePlaybackProof(from: playerItem)
        startVideoOutputPolling(for: playerItem)

        pendingResumeSeconds = resumeSeconds.flatMap { $0 > 0 ? $0 : nil }
    }

    private func resolvedRouteGuarantees(for selection: PlaybackAssetSelection) -> PlaybackRouteGuarantees {
        let evidence = PlaybackRouteEvidence(
            selectedVariantAllowsVideoCopy: selectedVariantInfo?.allowsVideoCopy,
            selectedVariantIsDolbyVisionSignaled: selectedVariantInfo?.isDolbyVisionSignaled ?? false,
            selectedVariantIsHDRSignaled: selectedVariantInfo?.isHDRSignaled ?? false,
            selectedVariantUsesFMP4: selectedVariantInfo?.usesFMP4Transport,
            selectedVariantCodec: selectedVariantInfo?.normalizedCodec,
            initHasHvcC: selectedInitSegmentInspection?.hasHvcC ?? false,
            initHasDvcC: selectedInitSegmentInspection?.hasDvcC ?? false,
            initHasDvvC: selectedInitSegmentInspection?.hasDvvC ?? false,
            localGatewayEnabled: Self.isLocalMediaGatewayURL(selection.assetURL),
            localGatewayObservedBitrate: playbackHealth.observedBitrate
        )
        return PlaybackRouteGuaranteeResolver.resolve(
            source: selection.source,
            route: selection.decision.route,
            finalURL: selection.assetURL,
            evidence: evidence,
            selectedSubtitleTrack: selectedSubtitleTrack(for: selection)
        )
    }

    private func selectedSubtitleTrack(for selection: PlaybackAssetSelection) -> MediaTrack? {
        guard let selectedSubtitleTrackID else { return nil }
        return selection.source.subtitleTracks.first { $0.id == selectedSubtitleTrackID }
    }

    private func publishFallbackIfNeededForDestructiveRoute(
        selection: PlaybackAssetSelection,
        guarantees: PlaybackRouteGuarantees
    ) {
        guard Self.shouldBlockAutomaticDestructiveFallback(source: selection.source, guarantees: guarantees) else { return }
        fallbackRecommendation = PlaybackFallbackRecommendationFactory.qualityRecommendation(
            sourceDescription: sourceQualityDescription(selection.source),
            routeGuarantees: guarantees,
            mediaBitrate: selection.source.bitrate
        )
    }

    private func blockAutomaticDestructiveFallbackIfNeeded(
        selection: PlaybackAssetSelection,
        guarantees: PlaybackRouteGuarantees,
        reason: String
    ) -> Bool {
        // Adaptive: the user chose "never freeze" over "never drop quality" — let the automatic
        // quality fallback proceed instead of blocking it and waiting for a manual choice.
        guard !AdaptiveFallbackPolicy.isEnabled else { return false }
        guard Self.shouldBlockAutomaticDestructiveFallback(source: selection.source, guarantees: guarantees) else { return false }
        routeGuarantees = guarantees
        playbackDiagnostics.recordRouteGuarantees(guarantees)
        playbackHealth = playbackHealthMonitor.markRouteFailed()
        playbackDiagnostics.recordHealth(playbackHealth)
        publishFallbackIfNeededForDestructiveRoute(selection: selection, guarantees: guarantees)
        playbackErrorMessage = "\(sourceQualityDescription(selection.source)) needs a quality fallback choice before video transcoding."
        AppLog.playback.warning(
            "playback.quality_fallback.blocked — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public) guarantee=\(guarantees.userVisibleSummary, privacy: .public)"
        )
        return true
    }

    private func publishHealthFallbackIfNeeded() {
        guard let source = currentSource else { return }
        guard let recommendation = PlaybackFallbackRecommendationFactory.healthRecommendation(
            sourceDescription: sourceQualityDescription(source),
            routeGuarantees: routeGuarantees,
            health: playbackHealth,
            mediaBitrate: source.bitrate
        ) else {
            return
        }
        fallbackRecommendation = recommendation
        playbackDiagnostics.recordHealth(playbackHealth)
    }

    private func sourceQualityDescription(_ source: MediaSource) -> String {
        if DolbyVisionClass.classify(source: source).isDolbyVision {
            return source.isLikely4K ? "Original 4K Dolby Vision" : "Original Dolby Vision"
        }
        if source.isLikelyHDRorDV {
            return source.isLikely4K ? "Original 4K HDR" : "Original HDR"
        }
        return source.isLikely4K ? "Original 4K" : "Original Quality"
    }

    private func scheduleVideoFormatSnapshotLoad(for item: AVPlayerItem) {
        videoFormatSnapshotTask?.cancel()
        videoFormatSnapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await self.loadVideoFormatSnapshot(for: item)
            guard !Task.isCancelled else { return }
            guard self.player.currentItem === item else { return }
            self.cachedVideoFormatSnapshot = snapshot
            guard let snapshot else { return }
            if snapshot.hdrMode != .unknown {
                self.runtimeHDRMode = snapshot.hdrMode
            }
            self.updatePlaybackProof(from: item)
        }
    }

    private func loadVideoFormatSnapshot(for item: AVPlayerItem) async -> VideoFormatSnapshot? {
        do {
            let tracks = try await item.asset.loadTracks(withMediaType: .video)
            for track in tracks {
                let formats = try await track.load(.formatDescriptions)
                for format in formats {
                    return Self.videoFormatSnapshot(
                        from: format,
                        fallbackBitDepth: debugInfo?.videoBitDepth
                    )
                }
            }
        } catch {
            AppLog.playback.debug(
                "playback.proof.async_format_load_failed — \(self.playbackLogScope(), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
        return nil
    }

    private func refreshTrickplayManifest(for selection: PlaybackAssetSelection) {
        let itemID = selection.source.itemID
        let sourceID = selection.source.id

        trickplayRefreshTask = Task { [weak self] in
            guard let self else { return }
            let manifest = try? await self.apiClient.fetchTrickplayManifest(
                itemID: itemID,
                mediaSourceID: sourceID
            )
            guard !Task.isCancelled else { return }

            if let manifest {
                let widths = manifest.variants.map(\.width).map(String.init).joined(separator: ",")
                AppLog.playback.info(
                    "playback.trickplay.loaded — \(self.playbackLogScope(), privacy: .public) source=\(manifest.sourceID ?? "item", privacy: .public) widths=[\(widths, privacy: .public)]"
                )
            } else {
                AppLog.playback.info(
                    "playback.trickplay.unavailable — \(self.playbackLogScope(), privacy: .public) requestedSource=\(sourceID, privacy: .public)"
                )
            }

            await MainActor.run {
                guard self.currentItemID == itemID else { return }
                guard self.currentSource?.id == sourceID else { return }
                self.activeTrickplayManifest = manifest
            }
        }
    }

    /// Multichannel audio (e.g. AC3 5.1) defaults to iOS binaural Spatial-Audio rendering, whose
    /// per-cycle cost can overrun the Core Audio IO deadline under the decode pressure of a 4K
    /// HDR/DV stream — surfacing as "HALC_ProxyIOContext IOWorkLoop: skipping cycle due to
    /// overload" and stalling playback. Restrict spatialization to mono/stereo so multichannel
    /// plays through the lighter standard (downmix/passthrough) path. Stereo/mono content is
    /// unaffected (still eligible for spatialization); only ≥3-channel audio changes.
    private static func applyMultichannelAudioSpatializationPolicy(to item: AVPlayerItem) {
        item.allowedAudioSpatializationFormats = .monoAndStereo
    }

    private func makeVideoOutput() -> AVPlayerItemVideoOutput {
        AVPlayerItemVideoOutput(
            pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
            ]
        )
    }

    private func installVideoOutputProbeIfNeeded(
        on item: AVPlayerItem,
        route: PlaybackRoute?,
        source: MediaSource?
    ) {
        videoOutput = nil
        guard let route else {
            let output = makeVideoOutput()
            item.add(output)
            videoOutput = output
            return
        }

        guard Self.shouldAttachVideoOutputProbe(
            route: route,
            source: source,
            isTVOS: Self.isTvOSPlatform
        ) else {
            AppLog.playback.notice(
                "playback.video_output.skipped — \(self.playbackLogScope(), privacy: .public) reason=tvos_hdr_directplay_owns_render_pipeline"
            )
            return
        }

        let output = makeVideoOutput()
        item.add(output)
        videoOutput = output
    }

    @discardableResult
    public func stop() -> PlaybackProgress? {
        let progressSnapshot = makeProgressSnapshot(isPaused: true, didFinish: false)
        let bridgeSession = nativeBridgeSession
        let repository = self.repository
        let apiClient = self.apiClient

        pause()
        tearDownCurrentItemObservers()
        player.replaceCurrentItem(with: nil)

        transportStateCommitter.cancel()
        transportState = .empty
        beginTransportStateSnapshotBatch()
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
        isNativePlayerActive = false
        nativePlayerDiagnosticsOverlayLines = []
        nativePlayerPlaybackURL = nil
        nativePlayerPlaybackHeaders = [:]
        nativePlayerStartTimeSeconds = nil
        playbackProof = PlaybackProofSnapshot()
        currentMediaItem = nil
        nextEpisodeQueue = []
        mediaSegments = []
        activeSkipSuggestion = nil
        activeTrickplayManifest = nil
        playbackTimeOffsetSeconds = 0
        endTransportStateSnapshotBatch(commitNow: true)

        currentItemID = nil
        currentItemHasDolbyVision = false
        currentSource = nil
        pendingResumeSeconds = nil
        lastKnownPlaybackPositionSeconds = nil
        pendingPlaybackPositionOverrideSeconds = nil
        transcodeStartOffset = 0
        sessionInitialResumeSeconds = 0
        trickplayRefreshTask?.cancel()
        currentForwardBufferDuration = 0
        tvosHealthyAccessLogSamples = 0
        didResumeAfterForeground = false
        videoFormatSnapshotTask?.cancel()
        videoFormatSnapshotTask = nil
        cachedVideoFormatSnapshot = nil
        recentStallTimestamps.removeAll()
        didAttemptDirectPlayStallRecovery = false
        hasMarkedFirstFrame = false
        firstFrameDate = nil
        lastDeepPlaybackEvidenceLogDate = nil
        lastDeepPlaybackEvidencePlaybackTime = nil
        hasDecodedVideoFrame = false
        avkitReadyForDisplay = false
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
        remoteProgressReportTask?.cancel()
        remoteProgressReportTask = nil
        pendingRemoteProgressUpdate = nil
        startupSubtitleSelectionTask?.cancel()
        startupSubtitleSelectionTask = nil
        videoValidationTask?.cancel()
        videoValidationTask = nil
        markerRefreshTask?.cancel()
        markerRefreshTask = nil

        nativeBridgeSession = nil
        syntheticHLSSession = nil
        localHLSServer?.stop(reason: "session_stopped")
        localHLSServer = nil

        if progressPersistenceEnabled, let progressSnapshot {
            Task {
                await Self.persistProgress(
                    snapshot: progressSnapshot,
                    repository: repository,
                    apiClient: apiClient,
                    sendStopped: true
                )
            }
        }

        if let bridgeSession {
            Task {
                await bridgeSession.invalidate()
            }
        }

        return progressSnapshot?.local
    }

    public func play() {
        guard !ignorePlayRequestAfterUnsafeDirectPlayStartup(trigger: "manual_play") else {
            return
        }

        startupTrace.playbackStartedAt = Date()
        let policy = PlaybackStartupPolicy.configuration(for: routeGuarantees.startupClass)
        if policy.usePlayImmediatelyWhenReady,
           pendingResumeSeconds == nil,
           player.currentItem?.status == .readyToPlay {
            player.playImmediately(atRate: 1.0)
        } else {
            player.play()
        }
    }

    public func updateNativePlayerPlaybackTime(_ seconds: Double) {
        guard seconds.isFinite else { return }
        currentTime = max(0, seconds)
        recordObservedPlaybackPosition(currentTime)
    }

    public func markAVKitReadyForDisplay() {
        guard let item = player.currentItem else { return }
        guard Self.shouldAcceptAVKitReadyForDisplay(itemStatus: item.status) else {
            AppLog.nativeBridge.debug("[NB-DIAG] avkit.readyForDisplay.ignored — \(self.playbackLogScope(), privacy: .public) reason=item_not_ready status=\(self.lastPlayerItemStatus, privacy: .public)")
            return
        }
        avkitReadyForDisplay = true
        AppLog.nativeBridge.notice("[NB-DIAG] avkit.readyForDisplay.accepted — \(self.playbackLogScope(), privacy: .public) status=\(self.lastPlayerItemStatus, privacy: .public)")
        refreshDecodedVideoFrameState()

        let playerSeconds = player.currentTime().seconds
        let displaySeconds = playerSeconds.isFinite ? max(0, playerSeconds) : max(0, currentTime)
        markFirstFrameIfNeeded(currentSeconds: displaySeconds, allowZeroTime: true)
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
        recordRequestedPlaybackPosition(newTime + transcodeStartOffset)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        handleSyntheticSeekInvalidation(target: target)
    }

    public func seek(to seconds: Double) {
        // `seconds` is in movie-absolute time; convert to HLS-stream-relative position.
        let hlsPosition = max(0, seconds - transcodeStartOffset)
        let target = CMTime(seconds: hlsPosition, preferredTimescale: 600)
        recordRequestedPlaybackPosition(max(0, seconds))
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

        Task { @MainActor [weak self] in
            await self?.selectAudioTrack(track)
        }
    }

    private func selectAudioTrack(_ track: MediaTrack) async {
        if isNativePlayerActive && nativePlayerPlaybackSurface == .sampleBuffer {
            selectedAudioTrackID = track.id
            AppLog.playback.info("nativeplayer.audio.selection_changed — status=requested")
            return
        }

        // 1. Try native AVMediaSelectionGroup first (works for multi-track containers).
        if let item = player.currentItem,
           let group = await loadMediaSelectionGroup(for: .audible, in: item) {
            let options = group.options
            let descriptors = makeSelectionDescriptors(options: options)
            if let optionIndex = PlaybackTrackMatcher.bestOptionIndex(for: track, options: descriptors) {
                item.select(options[optionIndex], in: group)
                selectedAudioTrackID = track.id
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
        await reloadForAudioTrack(track)
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
        let shouldResumePlayback = Self.shouldResumePlaybackAfterTrackReload(
            wasPlayingBeforeReplacement: isPlaying,
            playerRate: player.rate,
            timeControlStatus: player.timeControlStatus
        )
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

        replaceCurrentItemForTrackReload(newItem)
        lastPreparedSelection?.assetURL = newURL
        selectedAudioTrackID = track.id

        if currentSeconds > 0 {
            let seekTarget = CMTime(seconds: currentSeconds, preferredTimescale: 600)
            let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
            recordRequestedPlaybackPosition(currentSeconds + transcodeStartOffset)
            await player.seek(to: seekTarget, toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
        if shouldResumePlayback { player.play() }
    }

    public func selectSubtitleTrack(id: String?) {
        Task { @MainActor [weak self] in
            await self?.selectSubtitleTrackAsync(id: id)
        }
    }

    private func selectSubtitleTrackAsync(id: String?) async {
        if isNativePlayerActive && nativePlayerPlaybackSurface == .sampleBuffer {
            selectedSubtitleTrackID = id
            AppLog.playback.info(
                "nativeplayer.subtitle.selection_changed — status=\(id == nil ? "disabled" : "requested", privacy: .public)"
            )
            return
        }

        if let id, let track = availableSubtitleTracks.first(where: { $0.id == id }) {
            // Guard: block bitmap subtitles in strict HDR mode (they force destructive transcode).
            if subtitlePolicy.shouldBlockSubtitleSelection(
                track: track,
                strictMode: strictQualityIsActive,
                sourceIsHDRorDV: currentSource?.isLikelyHDRorDV == true,
                sourceIs4K: currentSource?.isLikely4K == true
            ) {
                AppLog.playback.warning(
                    "\(PlaybackFailureReason.subtitleWouldForceDestructiveTranscode.localizedDescription, privacy: .public) subtitle=\(track.title, privacy: .public)"
                )
                if let currentSource {
                    fallbackRecommendation = PlaybackFallbackRecommendationFactory.subtitleBurnInRecommendation(
                        source: currentSource,
                        subtitleTrack: track
                    )
                }
                playbackErrorMessage = "This subtitle track requires video transcoding. Keep original video without these subtitles, or switch to compatible playback."
                return
            }

            // 1. Try native AVMediaSelectionGroup (works for embedded subtitle tracks).
            if let item = player.currentItem,
               let group = await loadMediaSelectionGroup(for: .legible, in: item) {
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
            await reloadForSubtitleTrack(track)
        } else {
            // Disable subtitles.
            selectedSubtitleTrackID = nil
            if let item = player.currentItem,
               let group = await loadMediaSelectionGroup(for: .legible, in: item) {
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
        let shouldResumePlayback = Self.shouldResumePlaybackAfterTrackReload(
            wasPlayingBeforeReplacement: isPlaying,
            playerRate: player.rate,
            timeControlStatus: player.timeControlStatus
        )

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

        replaceCurrentItemForTrackReload(newItem)
        lastPreparedSelection?.assetURL = hlsURL
        selectedSubtitleTrackID = track.id

        // Resume from the same timestamp after the reload.
        if currentSeconds > 0 {
            let target = CMTime(seconds: currentSeconds, preferredTimescale: 600)
            let tolerance = CMTime(seconds: 2.0, preferredTimescale: 600)
            recordRequestedPlaybackPosition(currentSeconds + transcodeStartOffset)
            await player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
        if shouldResumePlayback { player.play() }
    }

    private func replaceCurrentItemForTrackReload(_ item: AVPlayerItem) {
        videoOutputPollTask?.cancel()
        startupSubtitleSelectionTask?.cancel()
        videoValidationTask?.cancel()
        installVideoOutputProbeIfNeeded(
            on: item,
            route: lastPreparedSelection?.decision.route,
            source: currentSource ?? lastPreparedSelection?.source
        )
        hasDecodedVideoFrame = false
        avkitReadyForDisplay = false
        lastPlayerItemStatus = "unknown"
        playbackProof.playerItemStatus = "unknown"
        player.replaceCurrentItem(with: item)
        configureObservers(for: item)
        updatePlaybackProof(from: item)
        startVideoOutputPolling(for: item)
    }

    /// Log the expected dynamic range outcome for the current playback session.
    ///
    /// This is intentionally pessimistic: it reports the *worst-case* expected
    /// outcome given the chosen route, not the best-case hope.
    ///
    /// Examples:
    ///  • MKV DV 8.1 → fMP4 video-copy remux → expected: Dolby Vision or HDR10 fallback
    ///    Reason: DV is only promised when HLS/init evidence carries DV signaling.
    ///  • MP4 DV 5 → directPlay → expected: Dolby Vision
    ///  • MKV HDR10 → video transcode → expected: SDR
    ///    Reason: destructive fallback drops original HDR metadata.
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
            "playback.hdr.expectation — \(self.playbackLogScope(), privacy: .public) expected=\(expected, privacy: .public) source=\(sourceDV ? "DV" : (sourceHDR10Plus ? "HDR10+" : "HDR10"), privacy: .public) route=\(selection.decision.playMethod, privacy: .public) reason=\(reason, privacy: .public)"
        )
        if sourceDV && expected.contains("HDR10") {
            AppLog.playback.warning(
                "playback.hdr.downgrade — \(self.playbackLogScope(), privacy: .public) from=DolbyVision to=HDR10 reason=route_limitations"
            )
        }
        if sourceHDR10Plus && !expected.contains("HDR10+") {
            AppLog.playback.info(
                "playback.hdr10plus.lost — \(self.playbackLogScope(), privacy: .public) reason=route_drops_dynamic_metadata"
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
        let is4KSource = currentSource?.isLikely4K == true

        // Helper: is this track selectable given current quality mode?
        func isSelectable(_ track: MediaTrack) -> Bool {
            !subtitlePolicy.shouldBlockSubtitleSelection(
                track: track,
                strictMode: strictQualityIsActive,
                sourceIsHDRorDV: isHDRSource,
                sourceIs4K: is4KSource
            )
        }

        // Helper: does the track language match a preferred language tag?
        func matchesPreferred(_ track: MediaTrack, _ preferred: String?) -> Bool {
            guard let preferred, let lang = track.language else { return false }
            return AudioTrackLanguageNormalizer.matches(lang, preferred)
        }

        // 1. Explicit default track — mirrors what the encoder/muxer intended.
        let startupRoute = lastPreparedSelection?.decision.route
        let startupSource = currentSource
        if let defaultTrack = tracks.first(where: {
            $0.isDefault
                && isSelectable($0)
                && Self.shouldAutoSelectDefaultSubtitleAtStartup(
                    track: $0,
                    route: startupRoute,
                    source: startupSource,
                    isTVOS: Self.isTvOSPlatform
                )
        }) {
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
        // Configure the audio session OFF the main thread. `AVAudioSession.setActive(_:)` is
        // synchronous and can briefly block the caller — on the main thread this trips the
        // "This method can lead to UI unresponsiveness if called on the main thread" warning
        // (AVAudioSession_iOS.mm). Apple's async `activate(options:completionHandler:)` is
        // watchOS-only (per AVFAudio docs), so on iOS the correct fix is to run the synchronous
        // category/activation calls on a background queue. AVPlayer activates the session
        // implicitly on play(), so a few ms of activation latency here is harmless.
        DispatchQueue.global(qos: .userInitiated).async {
            let activated = PlaybackAudioSessionPolicy.activate()
            if !activated {
                AppLog.playback.warning("Audio session setup failed")
            }
        }
#endif

        externalPlaybackObserver = player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            Task { @MainActor in
                self.isExternalPlaybackActive = player.isExternalPlaybackActive
            }
        }
    }

    private func loadMediaSelectionGroup(
        for characteristic: AVMediaCharacteristic,
        in item: AVPlayerItem
    ) async -> AVMediaSelectionGroup? {
        try? await item.asset.loadMediaSelectionGroup(for: characteristic)
    }

    /// Check if a subtitle track is available as an embedded option in the AVPlayer item.
    /// Embedded tracks can be selected instantly; external tracks (SRT/ASS) require an HLS reload.
    private func isSubtitleEmbedded(id: String, in item: AVPlayerItem) async -> Bool {
        guard let group = await loadMediaSelectionGroup(for: .legible, in: item),
              let track = availableSubtitleTracks.first(where: { $0.id == id }) else {
            return false
        }
        let descriptors = makeSelectionDescriptors(options: group.options)
        return PlaybackTrackMatcher.bestOptionIndex(for: track, options: descriptors) != nil
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
                guard self.player.currentItem === item else { return }
                self.currentTime = max(0, time.seconds) + self.transcodeStartOffset
                self.recordObservedPlaybackPosition(self.currentTime)
                let hlsDuration = self.player.currentItem?.duration.seconds ?? 0
                self.duration = max(self.currentTime, hlsDuration + self.transcodeStartOffset)
                self.refreshDecodedVideoFrameState()
                self.markFirstFrameIfNeeded(currentSeconds: self.currentTime)
                self.emitDeepPlaybackEvidenceIfNeeded(for: item, currentSeconds: self.currentTime)
                self.updateActiveSkipSuggestion()
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
                guard self.player.currentItem === item else { return }
                self.isPlaying = false
                await self.finishCurrentPlayback()
            }
        }

        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.player.currentItem === item else { return }
                self.metrics.stallCount += 1
                let now = Date()
                self.playbackHealth = self.playbackHealthMonitor.recordStall(at: now)
                self.playbackProof.healthState = self.playbackHealth.state.rawValue
                if self.startupTrace.firstStallAt == nil {
                    self.startupTrace.firstStallAt = now
                }
                self.publishHealthFallbackIfNeeded()
                self.activeStallInterval = SignpostInterval(signposter: Signpost.playbackStalls, name: "playback_stall")
                AppLog.playback.warning("Playback stalled.")

                self.recentStallTimestamps = self.recentStallTimestamps.filter {
                    now.timeIntervalSince($0) <= 12
                }
                self.recentStallTimestamps.append(now)
                let elapsedSinceFirstFrame = self.firstFrameDate.map { now.timeIntervalSince($0) }

                guard
                    !self.didAttemptDirectPlayStallRecovery,
                    let route = self.lastPreparedSelection?.decision.route,
                    Self.shouldAttemptDirectPlayStallRecovery(
                        route: route,
                        source: self.currentSource,
                        recentStallCount: self.recentStallTimestamps.count,
                        elapsedSecondsSinceLoad: now.timeIntervalSince(self.startDate),
                        elapsedSecondsSinceFirstFrame: elapsedSinceFirstFrame,
                        isTVOS: Self.isTvOSPlatform
                    )
                else {
                    if let elapsedSinceFirstFrame,
                       let route = self.lastPreparedSelection?.decision.route,
                       Self.shouldKeepCurrentDirectPlayItemAfterPostStartStall(
                        route: route,
                        source: self.currentSource,
                        isTVOS: Self.isTvOSPlatform
                       ) {
                        if Self.shouldMarkDirectPlayRouteFragileAfterPostStartStall(
                            route: route,
                            source: self.currentSource,
                            recentStallCount: self.recentStallTimestamps.count,
                            elapsedSecondsSinceFirstFrame: elapsedSinceFirstFrame
                        ) {
                            Self.markDirectPlayRouteFragile(route: route, source: self.currentSource, at: now)
                            AppLog.playback.warning(
                                "playback.directplay.route_fragile — \(self.playbackLogScope(), privacy: .public) recentStalls=\(self.recentStallTimestamps.count, privacy: .public) firstFrameElapsed=\(elapsedSinceFirstFrame, format: .fixed(precision: 1))s action=baseline_disabled"
                            )
                            // A direct-play route that keeps stalling post-start is on a connection
                            // that can't sustain the original bitrate — intermittent drops/timeouts
                            // (NSURLError -1005/-1001). Waiting on the current item won't self-heal:
                            // progressive direct play has no segment retry, so a dropped connection
                            // re-buffers repeatedly. Escalate ONCE to the server's transcode/HLS
                            // route — segment-based (survives connection drops) and able to fit a
                            // lower bitrate to the live link — for continuous playback instead of a
                            // stall loop. Bounded by maxRecoveryAttempts; skipped under strict
                            // quality (which forbids any downgrade). Full-quality direct play is
                            // preserved for healthy / transient-blip conditions (fragile requires
                            // repeated stalls, not one).
                            if !self.strictQualityIsActive,
                               !self.isRecoveryInProgress,
                               self.recoveryAttemptCount < self.maxRecoveryAttempts {
                                AppLog.playback.warning(
                                    "playback.directplay.escalate_adaptive_transcode — \(self.playbackLogScope(), privacy: .public) recentStalls=\(self.recentStallTimestamps.count, privacy: .public) reason=repeated_poststart_stall"
                                )
                                if await self.attemptRecovery(
                                    reason: StartupFailureReason.directPlayStall.rawValue,
                                    userMessage: "Adapting to your connection…"
                                ) {
                                    return
                                }
                            }
                        }
                        self.handlePostStartDirectPlayStallOnCurrentItem(
                            item: item,
                            recentStallCount: self.recentStallTimestamps.count,
                            stallDate: now,
                            elapsedSinceFirstFrame: elapsedSinceFirstFrame
                        )
                        // Ride the stall out on the original (DV) stream, but arm a watchdog: if it
                        // is still stuck after the grace window it is not a transient blip — escalate
                        // to the watchable adaptive transcode instead of freezing.
                        self.scheduleDirectPlayStallEscalationWatchdog(item: item, stallPosition: item.currentTime().seconds)
                    }
                    return
                }

                AppLog.playback.warning(
                    "playback.directplay.stall_reload — \(self.playbackLogScope(), privacy: .public) recentStalls=\(self.recentStallTimestamps.count, privacy: .public) elapsed=\(now.timeIntervalSince(self.startDate), format: .fixed(precision: 1))s"
                )
                if !(await self.attemptDirectPlaySameRouteRecoveryIfAvailable(reason: StartupFailureReason.directPlayStall.rawValue)) {
                    self.playbackErrorMessage = "Direct Play stalled repeatedly."
                }
            }
        }

        accessLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.player.currentItem === item else { return }
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
                self.playbackHealth = self.playbackHealthMonitor.recordBitrate(
                    observedBitrate: event.observedBitrate > 0 ? Int(event.observedBitrate) : nil,
                    mediaBitrate: self.currentSource?.bitrate,
                    at: Date()
                )
                self.playbackProof.healthState = self.playbackHealth.state.rawValue
                self.playbackProof.observedSafetyRatio = self.playbackHealth.safetyRatio
                self.playbackProof.requiredBitrate = self.playbackHealth.requiredBitrate
                self.publishHealthFallbackIfNeeded()
                await self.updateTVOSAdaptiveCachingIfNeeded(
                    item: item,
                    observedBitrate: event.observedBitrate,
                    indicatedBitrate: event.indicatedBitrate
                )
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
                AppLog.nativeBridge.notice("[NB-DIAG] avplayeritem.status — \(self.playbackLogScope(), privacy: .public) status=\(statusText, privacy: .public)")

                if observedItem.status == .readyToPlay {
                    self.startupTrace.itemReadyAt = Date()
                    self.readyInterval?.end(name: "avplayer_item_ready", message: "ready_to_play")
                    self.readyInterval = nil
                    self.ttffReadyMs = Date().timeIntervalSince(self.startDate) * 1000
                    if let snapshot = self.cachedVideoFormatSnapshot, snapshot.hdrMode != .unknown {
                        self.runtimeHDRMode = snapshot.hdrMode
                    }
                    self.updatePlaybackProof(from: observedItem)
                    let shouldApplyResumeSeek = Self.shouldApplyPendingDirectPlayResumeSeekOnReady(
                        route: self.lastPreparedSelection?.decision.route,
                        pendingResumeSeconds: self.pendingResumeSeconds,
                        currentTime: self.player.currentTime().seconds,
                        itemStatus: observedItem.status,
                        transcodeStartOffset: self.transcodeStartOffset,
                        directPlayAutoplayStartupGateActive: self.directPlayAutoplayStartupGateOwnsResumeSeek
                    )
                    if shouldApplyResumeSeek {
                        _ = await self.applyPendingDirectPlayResumeSeekIfNeeded(phase: "item_ready")
                    } else if self.directPlayAutoplayStartupGateOwnsResumeSeek, self.pendingResumeSeconds != nil {
                        AppLog.playback.info(
                            "playback.directplay.resume_seek.deferred — \(self.playbackLogScope(), privacy: .public) phase=item_ready reason=autoplay_startup_gate"
                        )
                    }
                    self.scheduleVideoValidation(for: observedItem)
                    self.emitLocalHLSStartupSummary(avplayerResult: "readyToPlay")
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
                            "playback.avplayer.error — \(self.playbackLogScope(), privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code) message=\(message, privacy: .public)"
                        )
                        if let reason = nsError.localizedFailureReason {
                            AppLog.playback.error("playback.avplayer.failure_reason — \(self.playbackLogScope(), privacy: .public) value=\(reason, privacy: .public)")
                        }
                        if let suggestion = nsError.localizedRecoverySuggestion {
                            AppLog.playback.error("playback.avplayer.recovery_suggestion — \(self.playbackLogScope(), privacy: .public) value=\(suggestion, privacy: .public)")
                        }
                    }
                    AppLog.playback.error("playback.avplayer.failed — \(self.playbackLogScope(), privacy: .public) message=\(message, privacy: .public)")
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
                    guard !self.ignorePlayRequestAfterUnsafeDirectPlayStartup(trigger: "time_control_playing") else {
                        return
                    }
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

    private func markFirstFrameIfNeeded(currentSeconds: Double, allowZeroTime: Bool = false) {
        guard !hasMarkedFirstFrame else { return }
        guard allowZeroTime || currentSeconds > 0 else { return }
        guard !Self.shouldDelayFirstFrameUntilResumePosition(
            route: lastPreparedSelection?.decision.route,
            pendingResumeSeconds: pendingResumeSeconds,
            currentTime: currentSeconds,
            transcodeStartOffset: transcodeStartOffset
        ) else {
            AppLog.playback.debug(
                "playback.directplay.first_frame.deferred_until_resume — \(self.playbackLogScope(), privacy: .public) current=\(currentSeconds, format: .fixed(precision: 3)) target=\(self.pendingResumeSeconds ?? 0, format: .fixed(precision: 3))"
            )
            return
        }
        guard let currentItem = player.currentItem else { return }
        let size = currentItem.presentationSize
        guard hasDecodedVideoFrame else { return }
        if !avkitReadyForDisplay {
            guard size.width > 1, size.height > 1 else { return }
        }
        let firstFrameDate = Date()
        hasMarkedFirstFrame = true
        self.firstFrameDate = firstFrameDate
        playbackErrorMessage = nil
        startupWatchdogTask?.cancel()
        decodedFrameWatchdogTask?.cancel()
        videoOutputPollTask?.cancel()
        videoValidationTask?.cancel()
        videoValidationTask = nil
        let playerStartupMs = firstFrameDate.timeIntervalSince(startDate) * 1000
        let totalTTFFMs = firstFrameDate.timeIntervalSince(loadStartDate) * 1000
        metrics.timeToFirstFrameMs = totalTTFFMs
        playbackHealth = playbackHealthMonitor.recordStartup(firstFrameMs: totalTTFFMs)
        playbackProof.healthState = playbackHealth.state.rawValue
        startupTrace.firstFrameAt = firstFrameDate
        publishHealthFallbackIfNeeded()
        playbackDiagnostics.recordStartupTrace(startupTrace, guarantees: routeGuarantees)
        PlayerDeepEvidenceSink.append(
            "avplayer.first-frame — \(playbackLogScope()) elapsedMs=\(String(format: "%.1f", playerStartupMs)) currentTime=\(String(format: "%.3f", currentSeconds))"
        )
        AppLog.nativeBridge.notice("[NB-DIAG] avplayer.first-frame — \(self.playbackLogScope(), privacy: .public) elapsedMs=\(playerStartupMs, format: .fixed(precision: 1)) currentTime=\(currentSeconds, format: .fixed(precision: 3))")
        emitLocalHLSStartupSummary(avplayerResult: "firstFrame")
        firstFrameInterval?.end(name: "avplayer_first_frame", message: "first_frame_rendered")
        firstFrameInterval = nil
        ttffPipelineInterval?.end(name: "ttff_total", message: "complete")
        ttffPipelineInterval = nil
        applyDeferredResumeSeekIfNeeded()
        rememberWorkingProfileForCurrentItem()
        applyDirectPlaySteadyStateBufferingIfNeeded()

        // Structured TTFF pipeline summary
        let method = playMethodForReporting
        let profile = activeTranscodeProfile.rawValue
        PlayerDeepEvidenceSink.append(
            "playback.ttff — \(playbackLogScope()) totalMs=\(String(format: "%.1f", totalTTFFMs)) infoMs=\(String(format: "%.1f", ttffInfoMs)) resolveMs=\(String(format: "%.1f", ttffResolveMs)) readyMs=\(String(format: "%.1f", ttffReadyMs)) playerMs=\(String(format: "%.1f", playerStartupMs)) method=\(method) profile=\(profile) route=\(routeGuarantees.startupClass.rawValue) videoIntegrity=\(routeGuarantees.videoIntegrity.rawValue) hdrIntegrity=\(routeGuarantees.hdrIntegrity.rawValue)"
        )
        AppLog.playback.info(
            "playback.ttff — \(self.playbackLogScope(), privacy: .public) totalMs=\(totalTTFFMs, format: .fixed(precision: 1)) infoMs=\(self.ttffInfoMs, format: .fixed(precision: 1)) resolveMs=\(self.ttffResolveMs, format: .fixed(precision: 1)) readyMs=\(self.ttffReadyMs, format: .fixed(precision: 1)) playerMs=\(playerStartupMs, format: .fixed(precision: 1)) method=\(method, privacy: .public) profile=\(profile, privacy: .public) route=\(self.routeGuarantees.startupClass.rawValue, privacy: .public) videoIntegrity=\(self.routeGuarantees.videoIntegrity.rawValue, privacy: .public) hdrIntegrity=\(self.routeGuarantees.hdrIntegrity.rawValue, privacy: .public)"
        )

        if playMethodForReporting == "NativeBridge", let itemID = currentItemID {
            NativeBridgeFailureCache.clearFailure(itemID: itemID)
        }

        applyStartupSubtitleSelectionAfterFirstFrameIfNeeded(for: currentItem)
    }

    private func applyStartupSubtitleSelectionAfterFirstFrameIfNeeded(for item: AVPlayerItem) {
        guard !didApplyStartupSubtitleSelection else { return }
        guard let selectedSubtitleTrackID else { return }
        didApplyStartupSubtitleSelection = true

        startupSubtitleSelectionTask?.cancel()
        startupSubtitleSelectionTask = Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            guard self.player.currentItem === item else { return }

            let isEmbedded = await self.isSubtitleEmbedded(id: selectedSubtitleTrackID, in: item)
            switch Self.startupSubtitleLoadAction(
                autoSelectedTrackID: selectedSubtitleTrackID,
                isEmbedded: isEmbedded
            ) {
            case .applyEmbedded(let trackID):
                await self.selectSubtitleTrackAsync(id: trackID)
                await self.reassertDirectPlayResumePositionAfterStartupSelectionIfNeeded(for: item)
            case .skipExternal(let trackID):
                if let track = self.availableSubtitleTracks.first(where: { $0.id == trackID }) {
                    AppLog.playback.info(
                        "playback.subtitle.reload_skipped — \(self.playbackLogScope(), privacy: .public) track='\(track.title, privacy: .public)' reason=external_startup_reload_after_first_frame"
                    )
                }
            case .none:
                break
            }
        }
    }

    private func reassertDirectPlayResumePositionAfterStartupSelectionIfNeeded(for item: AVPlayerItem) async {
        guard player.currentItem === item else { return }
        let resumeSeconds = pendingResumeSeconds ?? (sessionInitialResumeSeconds > 0 ? sessionInitialResumeSeconds : nil)
        let current = player.currentTime().seconds
        guard Self.shouldReassertDirectPlayResumePositionAfterStartupSelection(
            route: lastPreparedSelection?.decision.route,
            resumeSeconds: resumeSeconds,
            currentTime: current,
            transcodeStartOffset: transcodeStartOffset
        ) else { return }
        guard let resumeSeconds, item.status == .readyToPlay else { return }

        let shouldResumePlayback = Self.shouldResumePlaybackAfterTrackReload(
            wasPlayingBeforeReplacement: isPlaying,
            playerRate: player.rate,
            timeControlStatus: player.timeControlStatus
        )
        _ = await seekToDirectPlayResumePosition(
            phase: "startup_subtitle",
            targetSeconds: resumeSeconds,
            resumePlaybackWhenDone: shouldResumePlayback,
            retryCancelledSeek: true
        )
    }

    private func scheduleVideoValidation(for item: AVPlayerItem) {
        videoValidationTask?.cancel()
        videoValidationTask = Task { @MainActor [weak self, weak item] in
            guard let self else { return }
            guard let item else { return }
            let validationDelay = self.videoValidationDelayNanoseconds()
            try? await Task.sleep(nanoseconds: validationDelay)
            guard !Task.isCancelled else { return }
            guard self.player.currentItem === item else { return }
            guard !self.hasMarkedFirstFrame else { return }
            self.refreshDecodedVideoFrameState()

            if self.isRiskyServerDefaultHEVCTranscode(item: item) {
                AppLog.playback.warning("Server default HEVC stream-copy detected before first frame. Switching to Apple optimized profile.")
                if !(await self.attemptRecoveryPreservingDirectPlay(
                    reason: "risky_hevc_stream_copy",
                    userMessage: "Optimizing HEVC playback path to avoid black screen."
                )) {
                    self.playbackErrorMessage = "Could not stabilize HEVC playback automatically."
                }
                return
            }

            if self.currentTime >= 3.0, !self.hasDecodedVideoFrame {
                AppLog.playback.warning("Playback advanced without decoded video frame. Trying playback recovery.")
                if !(await self.attemptRecoveryPreservingDirectPlay(
                    reason: StartupFailureReason.audioOnlyNoVideo.rawValue,
                    userMessage: "Audio is playing without video. Retrying playback."
                )) {
                    self.playbackErrorMessage = "Audio is playing but no video frame is decoding."
                }
                return
            }

            let size = item.presentationSize
            guard size.width <= 1 || size.height <= 1 else { return }

            AppLog.playback.error("Ready item has no video presentation size. Trying playback recovery.")
            if !(await self.attemptRecoveryPreservingDirectPlay(
                reason: "video_presentation_size_zero",
                userMessage: "No video frame decoded. Retrying playback."
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
            "[NB-DIAG] hls.startup.summary — \(self.playbackLogScope(), privacy: .public) lane=nativeBridge host=\(summary.host, privacy: .public) port=\(summary.port, privacy: .public) master=\(summary.masterURL.reelfinCompactLogString, privacy: .public) initBytes=\(summary.initBytes, privacy: .public) firstSegBytes=\(summary.firstSegmentBytes, privacy: .public) firstSegDuration=\(summary.firstSegmentDurationSeconds, format: .fixed(precision: 3)) keyframe=\(keyframeValue, privacy: .public) preflight=pass avplayer=\(avplayerResult, privacy: .public)"
        )
    }

    private func attemptDirectPlayStallRecovery(reason: String) async -> Bool {
        guard let preparedSelection = lastPreparedSelection else { return false }
        guard case .directPlay = preparedSelection.decision.route else { return false }
        let selection = Self.directPlayRecoverySelection(
            preparedSelection: preparedSelection,
            gatewayRemoteSelection: localMediaGatewayRemoteSelection
        )
        if Self.shouldDisableLocalGatewayForDirectPlayRecovery(
            reason: reason,
            preparedSelection: preparedSelection,
            hasMarkedFirstFrame: hasMarkedFirstFrame
        ) {
            localMediaGatewayDisabledSourceIDs.insert(preparedSelection.source.id)
            stopLocalMediaGateway(reason: "directplay_recovery_transport_failure")
            AppLog.playback.warning(
                "playback.cache.gateway.bypassed — \(self.playbackLogScope(), privacy: .public) source=\(preparedSelection.source.id, privacy: .public) reason=directplay_recovery_transport_failure"
            )
        }

        let resumeSeconds = Self.directPlaySameRouteRecoveryResumeSeconds(
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            playerSeconds: player.currentTime().seconds,
            sessionInitialResumeSeconds: sessionInitialResumeSeconds,
            transcodeStartOffset: transcodeStartOffset
        )
        recentStallTimestamps.removeAll()
        await loadDirectPlaySelectionAtResumePosition(selection, resumeSeconds: resumeSeconds)
        routeDescription = "Direct Play (stability recovery)"
        playbackErrorMessage = nil
        guard await startRecoveredDirectPlayWhenReady(
            selection: selection,
            resumeSeconds: resumeSeconds,
            reason: reason
        ) else {
            return false
        }
        let resumeLabel = resumeSeconds.map { String(format: "%.3f", $0) } ?? "none"
        let loadedURL = lastPreparedSelection?.assetURL ?? selection.assetURL
        AppLog.playback.notice(
            "playback.directplay.recovery_reloaded — \(self.playbackLogScope(), privacy: .public) resume=\(resumeLabel, privacy: .public) url=\(loadedURL.reelfinCompactLogString, privacy: .public)"
        )
        return true
    }

    private func startRecoveredDirectPlayWhenReady(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double?,
        reason: String
    ) async -> Bool {
        let sanitizedResumeSeconds = max(0, resumeSeconds ?? 0)
        let runtimeSeconds = currentMediaItem?.runtimeTicks.map { Double($0) / 10_000_000 }
        let startupReady = await performStartupReadinessGateIfNeeded(
            selection: selection,
            resumeSeconds: sanitizedResumeSeconds,
            runtimeSeconds: runtimeSeconds,
            preheatResult: nil,
            serverBaselineResult: nil,
            maxStreamingBitrate: currentMaxStreamingBitrate
        )
        if !startupReady,
           Self.shouldBlockAutoplayAfterUnsafeStartup(
            route: selection.decision.route,
            source: selection.source,
            runtimeSeconds: runtimeSeconds,
            resumeSeconds: sanitizedResumeSeconds,
            isTVOS: Self.isTvOSPlatform
           ) {
            logStartupRecoveryUnavailable(
                reason: "\(reason)_recovery_readiness_timeout",
                action: "block_autoplay"
            )
            blockUnsafeDirectPlayStartupPlayback(
                reason: "\(reason)_recovery_readiness_timeout",
                userMessage: "Playback did not build a safe buffer. Try again or use a lower quality profile."
            )
            return false
        }

        let resumeReady = await ensureDirectPlayResumePositionBeforeAutoplayIfNeeded(
            selection: selection,
            resumeSeconds: resumeSeconds
        )
        if !resumeReady,
           Self.shouldBlockAutoplayAfterUnsafeStartup(
            route: selection.decision.route,
            source: selection.source,
            runtimeSeconds: runtimeSeconds,
            resumeSeconds: sanitizedResumeSeconds,
            isTVOS: Self.isTvOSPlatform
           ) {
            logStartupRecoveryUnavailable(
                reason: "\(reason)_recovery_resume_not_ready",
                action: "block_autoplay"
            )
            blockUnsafeDirectPlayStartupPlayback(
                reason: "\(reason)_recovery_resume_not_ready",
                userMessage: "Playback could not resume safely. Try again or use a lower quality profile."
            )
            return false
        }

        directPlayStartupPlaybackBlocked = false
        player.play()
        scheduleDecodedFrameWatchdog()
        scheduleStartupWatchdog()
        return true
    }

    private func loadDirectPlaySelectionAtResumePosition(
        _ selection: PlaybackAssetSelection,
        resumeSeconds: Double?
    ) async {
        let selection = await prepareLocalMediaGatewayIfNeeded(selection, resumeSeconds: resumeSeconds)
        prepareAndLoadSelection(selection, resumeSeconds: resumeSeconds)
        guard isActivePlaybackTarget(itemID: selection.source.itemID), player.currentItem != nil else {
            return
        }
        guard let resumeSeconds, resumeSeconds > 0 else { return }
        if Self.shouldDeferInitialDirectPlayResumeSeek(
            route: selection.decision.route,
            resumeSeconds: resumeSeconds
        ) {
            recordRequestedPlaybackPosition(resumeSeconds)
            AppLog.playback.info(
                "playback.directplay.resume_seek.deferred — \(self.playbackLogScope(), privacy: .public) phase=initial target=\(resumeSeconds, format: .fixed(precision: 3)) reason=item_not_ready"
            )
            return
        }

        let seekTime = CMTime(seconds: resumeSeconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
        recordRequestedPlaybackPosition(resumeSeconds)
        let completed = await player.seek(to: seekTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
        logDirectPlayResumeSeekResult(
            phase: "initial",
            target: resumeSeconds,
            completed: completed
        )
        player.pause()
    }

    private func prepareLocalMediaGatewayIfNeeded(
        _ selection: PlaybackAssetSelection,
        resumeSeconds: Double?
    ) async -> PlaybackAssetSelection {
        guard case .directPlay = selection.decision.route else {
            stopLocalMediaGateway(reason: "non_direct_route")
            return selection
        }
        if Self.isLocalMediaGatewayURL(selection.assetURL) {
            let remoteSelection = Self.directPlayRecoverySelection(
                preparedSelection: selection,
                gatewayRemoteSelection: localMediaGatewayRemoteSelection
            )
            stopLocalMediaGateway(reason: "gateway_wrap_prevented")
            AppLog.playback.error(
                "playback.cache.gateway.wrap_prevented — \(self.playbackLogScope(), privacy: .public) source=\(selection.source.id, privacy: .public) reason=local_gateway_upstream"
            )
            return remoteSelection
        }
        guard LocalMediaGatewayURLPolicy.isSupportedRemoteURL(selection.assetURL) else {
            stopLocalMediaGateway(reason: "gateway_local_asset_skip")
            return selection
        }
        guard !localMediaGatewayDisabledSourceIDs.contains(selection.source.id) else {
            stopLocalMediaGateway(reason: "gateway_session_disabled")
            AppLog.playback.info(
                "playback.cache.gateway.skipped — \(self.playbackLogScope(), privacy: .public) source=\(selection.source.id, privacy: .public) reason=session_disabled"
            )
            return selection
        }
        guard let store = mediaGatewayStore,
              let configuration = await apiClient.currentConfiguration(),
              let session = await apiClient.currentSession()
        else {
            stopLocalMediaGateway(reason: "gateway_unavailable")
            return selection
        }

        let key = mediaGatewayKey(
            selection: selection,
            configuration: configuration,
            session: session
        )
        let cachedBytes = ((try? await store.coveredRanges(key: key)) ?? [])
            .reduce(0) { $0 + Int64($1.length) }
        guard LocalMediaGatewayRoutePolicy.shouldUseGateway(
            route: selection.decision.route,
            source: selection.source,
            mediaCacheMode: configuration.mediaCacheMode,
            isTVOS: Self.isTvOSPlatform,
            resumeSeconds: resumeSeconds,
            hasCachedBytes: cachedBytes > 0,
            cachedBytes: cachedBytes
        ) else {
            stopLocalMediaGateway(reason: "gateway_policy_skip")
            return selection
        }

        return startLocalMediaGateway(
            selection: selection,
            key: key,
            store: store,
            configuration: configuration,
            cachedBytes: cachedBytes
        )
    }

    private func startLocalMediaGateway(
        selection: PlaybackAssetSelection,
        key: MediaGatewayCacheKey,
        store: MediaGatewayStore,
        configuration: ServerConfiguration,
        cachedBytes: Int64
    ) -> PlaybackAssetSelection {
        guard LocalMediaGatewayURLPolicy.isSupportedRemoteURL(selection.assetURL) else {
            AppLog.playback.error(
                "playback.cache.gateway.wrap_prevented — \(self.playbackLogScope(), privacy: .public) source=\(selection.source.id, privacy: .public) reason=unsupported_upstream"
            )
            return selection
        }
        do {
            stopLocalMediaGateway(reason: "gateway_replace")
            let gatewaySession = LocalMediaGatewaySession(
                remoteURL: selection.assetURL,
                headers: selection.headers,
                key: key,
                store: store,
                prefetchConfiguration: localGatewayPrefetchConfiguration(selection: selection, configuration: configuration),
                sessionConfiguration: MediaOriginTransport.makeConfiguration()
            )
            let gatewayLogScope = playbackLogScope()
            let server = LocalMediaGatewayServer(session: gatewaySession) { method, range in
                AppLog.playback.debug(
                    "playback.cache.gateway.request — \(gatewayLogScope, privacy: .public) method=\(method, privacy: .public) range=\(range, privacy: .public)"
                )
            }
            let localURL = try server.start()
            localMediaGatewaySession = gatewaySession
            localMediaGatewayServer = server
            var updated = selection
            updated.assetURL = localURL
            updated.headers = [:]
            localMediaGatewayRemoteSelection = selection
            localMediaGatewayLocalSelection = updated
            AppLog.playback.notice(
                "playback.cache.gateway.selected — \(self.playbackLogScope(), privacy: .public) source=\(selection.source.id, privacy: .public) mode=\(configuration.mediaCacheMode.rawValue, privacy: .public) cachedBytes=\(cachedBytes, privacy: .public) host=127.0.0.1"
            )
            updated.routeGuarantees = resolvedRouteGuarantees(for: updated)
            return updated
        } catch {
            stopLocalMediaGateway(reason: "gateway_start_failed")
            AppLog.playback.warning(
                "playback.cache.gateway.unavailable — \(self.playbackLogScope(), privacy: .public) source=\(selection.source.id, privacy: .public) reason=\(error.localizedDescription, privacy: .public)"
            )
            return selection
        }
    }

    private func localGatewayPrefetchConfiguration(
        selection: PlaybackAssetSelection,
        configuration: ServerConfiguration
    ) -> LocalMediaGatewayPrefetchConfiguration {
        LocalMediaGatewayPrefetchConfiguration(
            mediaCacheMode: configuration.mediaCacheMode,
            isTVOS: Self.isTvOSPlatform,
            routeKind: .directPlayOriginal,
            sourceBitrate: selection.source.bitrate ?? 0,
            runtimeSeconds: Double(currentMediaItem?.runtimeTicks ?? 0) / 10_000_000,
            isExpensiveNetwork: false,
            isConstrainedNetwork: false
        )
    }

    private func mediaGatewayKey(
        selection: PlaybackAssetSelection,
        configuration: ServerConfiguration,
        session: UserSession
    ) -> MediaGatewayCacheKey {
        MediaGatewayCacheKey(
            scope: "directplay-original",
            userID: session.userID,
            serverID: configuration.serverURL.host ?? configuration.serverURL.absoluteString,
            itemID: selection.source.itemID,
            sourceID: selection.source.id,
            routeURL: selection.assetURL,
            routeHeaders: selection.headers,
            audioSignature: selectedAudioTrackID ?? "default",
            subtitleSignature: selectedSubtitleTrackID ?? "default",
            resumeSeconds: nil
        )
    }

    private func stopLocalMediaGateway(reason: String) {
        localMediaGatewayServer?.stop(reason: reason)
        localMediaGatewayServer = nil
        localMediaGatewaySession = nil
        localMediaGatewayRemoteSelection = nil
        localMediaGatewayLocalSelection = nil
        cacheResourceLoader?.invalidate()
        cacheResourceLoader = nil
        cacheProxyServer?.stop(reason: reason)
        cacheProxyServer = nil
        cacheOriginDownloader = nil
    }

    /// Synchronous cache key for the cache-loader path. `prepareAndLoadSelection` is not async, so
    /// (unlike `mediaGatewayKey`) this derives `serverID` from the origin host instead of awaiting
    /// the resolved configuration. itemID/sourceID/routeURL/headers + audio/subtitle signatures
    /// make the key self-consistent and stable across resumes of the same source.
    private func cacheLoaderKey(for selection: PlaybackAssetSelection) -> MediaGatewayCacheKey {
        MediaGatewayCacheKey(
            scope: "directplay-original",
            userID: nil,
            serverID: selection.assetURL.host,
            itemID: selection.source.itemID,
            sourceID: selection.source.id,
            routeURL: selection.assetURL,
            routeHeaders: selection.headers,
            audioSignature: selectedAudioTrackID ?? "default",
            subtitleSignature: selectedSubtitleTrackID ?? "default",
            resumeSeconds: nil
        )
    }

    private func ensureDirectPlayResumePositionBeforeAutoplayIfNeeded(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double?,
        phase: String = "preplay",
        waitForItemReady: Bool = false
    ) async -> Bool {
        guard case .directPlay = selection.decision.route else { return true }
        guard let resumeSeconds, resumeSeconds > 0 else { return true }
        guard !Self.isResumePositionSatisfied(
            currentTime: player.currentTime().seconds,
            resumeSeconds: resumeSeconds
        ) else {
            pendingResumeSeconds = nil
            return true
        }
        if waitForItemReady {
            let itemReady = await waitForCurrentItemReadyBeforeAutoplayAfterStartupSkip(
                route: selection.decision.route,
                reason: "directplay_resume_\(phase)",
                timeout: 6
            )
            guard itemReady else { return false }
            guard !Self.isResumePositionSatisfied(
                currentTime: player.currentTime().seconds,
                resumeSeconds: resumeSeconds
            ) else {
                pendingResumeSeconds = nil
                return true
            }
            if await waitForMaterializedDirectPlayResumePositionBeforeStartupSeekIfNeeded(
                selection: selection,
                resumeSeconds: resumeSeconds,
                phase: phase
            ) {
                return true
            }
        }
        guard let item = player.currentItem, item.status == .readyToPlay else {
            return false
        }

        if pendingResumeSeconds == resumeSeconds {
            return await applyPendingDirectPlayResumeSeekIfNeeded(phase: phase)
        }

        let completed = await seekToDirectPlayResumePosition(
            phase: phase,
            targetSeconds: resumeSeconds,
            resumePlaybackWhenDone: false,
            retryCancelledSeek: false
        )
        return completed
    }

    private func waitForMaterializedDirectPlayResumePositionBeforeStartupSeekIfNeeded(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        phase: String,
        timeout: TimeInterval = DirectPlaySessionPolicy.materializedResumePositionStartupWaitTimeout
    ) async -> Bool {
        guard let item = player.currentItem else { return false }
        guard Self.shouldWaitForMaterializedDirectPlayResumePositionBeforeStartupSeek(
            route: selection.decision.route,
            pendingResumeSeconds: pendingResumeSeconds,
            currentTime: player.currentTime().seconds,
            itemStatus: item.status,
            transcodeStartOffset: transcodeStartOffset,
            directPlayAutoplayStartupGateActive: directPlayAutoplayStartupGateOwnsResumeSeek
        ) else {
            return false
        }

        let startedAt = Date()
        AppLog.playback.info(
            "playback.directplay.resume_seek.materialize_wait — \(self.playbackLogScope(), privacy: .public) phase=\(phase, privacy: .public) target=\(resumeSeconds, format: .fixed(precision: 3)) timeout=\(timeout, format: .fixed(precision: 2)) current=\(self.player.currentTime().seconds, format: .fixed(precision: 3))"
        )
        while !Task.isCancelled {
            guard player.currentItem === item else { return false }
            let current = player.currentTime().seconds
            if Self.isResumePositionSatisfied(currentTime: current, resumeSeconds: resumeSeconds) {
                pendingResumeSeconds = nil
                AppLog.playback.info(
                    "playback.directplay.resume_seek.materialized — \(self.playbackLogScope(), privacy: .public) phase=\(phase, privacy: .public) target=\(resumeSeconds, format: .fixed(precision: 3)) current=\(current, format: .fixed(precision: 3)) elapsed=\(Date().timeIntervalSince(startedAt), format: .fixed(precision: 2))"
                )
                return true
            }
            guard Date().timeIntervalSince(startedAt) < timeout else {
                AppLog.playback.info(
                    "playback.directplay.resume_seek.materialize_timeout — \(self.playbackLogScope(), privacy: .public) phase=\(phase, privacy: .public) target=\(resumeSeconds, format: .fixed(precision: 3)) current=\(current, format: .fixed(precision: 3))"
                )
                return false
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private func applyPendingDirectPlayResumeSeekIfNeeded(phase: String) async -> Bool {
        guard let item = player.currentItem else { return true }
        let current = player.currentTime().seconds
        if let pendingResumeSeconds,
           Self.isResumePositionSatisfied(currentTime: current, resumeSeconds: pendingResumeSeconds) {
            self.pendingResumeSeconds = nil
            return true
        }

        guard Self.shouldApplyPendingDirectPlayResumeSeekOnReady(
            route: lastPreparedSelection?.decision.route,
            pendingResumeSeconds: pendingResumeSeconds,
            currentTime: current,
            itemStatus: item.status,
            transcodeStartOffset: transcodeStartOffset
        ) else {
            return true
        }

        guard let targetSeconds = pendingResumeSeconds else { return true }
        let shouldResumePlayback = Self.shouldResumePlaybackAfterTrackReload(
            wasPlayingBeforeReplacement: isPlaying,
            playerRate: player.rate,
            timeControlStatus: player.timeControlStatus
        )
        return await seekToDirectPlayResumePosition(
            phase: phase,
            targetSeconds: targetSeconds,
            resumePlaybackWhenDone: shouldResumePlayback,
            retryCancelledSeek: true
        )
    }

    private func seekToDirectPlayResumePosition(
        phase: String,
        targetSeconds: Double,
        resumePlaybackWhenDone: Bool,
        retryCancelledSeek: Bool
    ) async -> Bool {
        player.pause()
        var completed = await performDirectPlayResumeSeek(phase: phase, targetSeconds: targetSeconds)
        var satisfied = Self.isResumePositionSatisfied(currentTime: player.currentTime().seconds, resumeSeconds: targetSeconds)
        if retryCancelledSeek, !completed, !satisfied, player.currentItem?.status == .readyToPlay {
            await Task.yield()
            completed = await performDirectPlayResumeSeek(phase: "\(phase)_retry", targetSeconds: targetSeconds)
            satisfied = Self.isResumePositionSatisfied(currentTime: player.currentTime().seconds, resumeSeconds: targetSeconds)
        }
        if satisfied {
            pendingResumeSeconds = nil
            if resumePlaybackWhenDone {
                player.play()
            } else {
                player.pause()
            }
        } else {
            pendingResumeSeconds = targetSeconds
            player.pause()
        }
        return satisfied
    }

    private func performDirectPlayResumeSeek(phase: String, targetSeconds: Double) async -> Bool {
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
        recordRequestedPlaybackPosition(targetSeconds)
        var completion: Bool?
        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { finished in
            Task { @MainActor in
                completion = finished
            }
        }

        let startedAt = Date()
        let timeout = DirectPlaySessionPolicy.materializedResumePositionStartupWaitTimeout
        while !Task.isCancelled {
            if let completion {
                logDirectPlayResumeSeekResult(
                    phase: phase,
                    target: targetSeconds,
                    completed: completion
                )
                return completion
            }

            if let item = player.currentItem,
               Self.shouldAcceptMaterializedDirectPlayResumeSeek(
                currentTime: player.currentTime().seconds,
                resumeSeconds: targetSeconds,
                itemStatus: item.status,
                hasMarkedFirstFrame: hasMarkedFirstFrame
               ) {
                logDirectPlayResumeSeekResult(
                    phase: phase,
                    target: targetSeconds,
                    completed: false
                )
                return true
            }

            guard Date().timeIntervalSince(startedAt) < timeout else {
                logDirectPlayResumeSeekResult(
                    phase: phase,
                    target: targetSeconds,
                    completed: false
                )
                return false
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private func logDirectPlayResumeSeekResult(
        phase: String,
        target: Double,
        completed: Bool
    ) {
        let current = player.currentTime().seconds
        let satisfied = Self.isResumePositionSatisfied(
            currentTime: current,
            resumeSeconds: target
        )
        AppLog.playback.info(
            "playback.directplay.resume_seek — \(self.playbackLogScope(), privacy: .public) phase=\(phase, privacy: .public) target=\(target, format: .fixed(precision: 3)) current=\(current, format: .fixed(precision: 3)) completed=\(completed, privacy: .public) satisfied=\(satisfied, privacy: .public)"
        )
    }

    private func recoveryResumeSeconds() -> Double? {
        Self.directPlaySameRouteRecoveryResumeSeconds(
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            playerSeconds: player.currentTime().seconds,
            sessionInitialResumeSeconds: sessionInitialResumeSeconds,
            transcodeStartOffset: transcodeStartOffset
        )
    }

    private var isPlaybackActivelyRequestedForStartupReadiness: Bool {
        PlaybackResumePolicy.shouldResumeAfterControllerReattach(
            playerRate: player.rate,
            timeControlStatus: player.timeControlStatus
        )
    }

    private func performStartupReadinessGateIfNeeded(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        preheatResult: PlaybackStartupPreheater.Result?,
        serverBaselineResult: PlaybackServerNetworkBaseline.Result?,
        maxStreamingBitrate: Int
    ) async -> Bool {
        if Self.shouldUseFastDirectPlayStartup(
            route: selection.decision.route,
            source: selection.source,
            maxStreamingBitrate: maxStreamingBitrate,
            isTVOS: Self.isTvOSPlatform
        ) {
            AppLog.playback.info(
                "playback.startup.readiness.skipped — \(self.playbackLogScope(), privacy: .public) reason=directplay_network_headroom sourceBitrate=\(selection.source.bitrate ?? 0, privacy: .public) maxStreamingBitrate=\(maxStreamingBitrate, privacy: .public)"
            )
            return await waitForCurrentItemReadyBeforeAutoplayAfterStartupSkip(
                route: selection.decision.route,
                reason: "directplay_network_headroom"
            )
        }

        if case .directPlay = selection.decision.route {
            let decision = Self.directPlayStartupDecision(
                route: selection.decision.route,
                sourceBitrate: selection.source.bitrate,
                sourceIsHDRorDV: selection.source.isLikelyHDRorDV,
                preheatResult: preheatResult,
                serverBaselineResult: serverBaselineResult,
                isTVOS: Self.isTvOSPlatform
            )
            if decision.mode == .fast {
                let baselineBitrate = Int(serverBaselineResult?.observedBitrate ?? 0)
                let preheatBitrate = Int(preheatResult?.observedBitrate ?? 0)
                AppLog.playback.info(
                    "playback.startup.readiness.skipped — \(self.playbackLogScope(), privacy: .public) reason=directplay_measured_headroom preheatBitrate=\(preheatBitrate, privacy: .public) baselineBitrate=\(baselineBitrate, privacy: .public)"
                )
                applyMeasuredHeadroomDirectPlayStartupPolicyIfNeeded()
                return await waitForCurrentItemReadyBeforeAutoplayAfterStartupSkip(
                    route: selection.decision.route,
                    reason: "directplay_measured_headroom"
                )
            }
        }

        guard let requirement = PlaybackStartupReadinessPolicy.requirement(
            route: selection.decision.route,
            sourceBitrate: selection.source.bitrate,
            sourceIsHDRorDV: selection.source.isLikelyHDRorDV,
            runtimeSeconds: runtimeSeconds,
            resumeSeconds: resumeSeconds,
            isTVOS: Self.isTvOSPlatform
        ) else { return true }
        guard let item = player.currentItem else { return true }
        let loadedReadinessSelection = Self.startupReadinessLoadedSelection(
            requestedSelection: selection,
            preparedSelection: lastPreparedSelection
        )
        let usesLocalGatewayForReadiness = Self.isLocalMediaGatewayURL(loadedReadinessSelection.assetURL)
        let localGatewayReadinessSession = usesLocalGatewayForReadiness ? localMediaGatewaySession : nil
        let startupBufferPlaybackPosition = resumeSeconds > 0 ? resumeSeconds : nil

        let allowsPausedDirectPlayFirstFrame = Self.shouldReleasePausedStartupAfterFirstFrame(
            route: selection.decision.route,
            source: selection.source,
            resumeSeconds: resumeSeconds,
            preheatResult: preheatResult,
            serverBaselineResult: serverBaselineResult,
            isTVOS: Self.isTvOSPlatform
        )
        let allowsFirstFrameStartupReadiness = PlaybackStartupReadinessPolicy.allowsFirstFrameStartupReadiness(
            requirement: requirement
        ) || allowsPausedDirectPlayFirstFrame
        let firstFrameReadinessSource = allowsPausedDirectPlayFirstFrame ? "first_frame_preheat" : "first_frame"

        if allowsFirstFrameStartupReadiness, Self.shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
            route: selection.decision.route,
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            pendingResumeSeconds: pendingResumeSeconds,
            currentTime: player.currentTime().seconds,
            itemStatus: item.status,
            transcodeStartOffset: transcodeStartOffset,
            isPlaybackActive: isPlaybackActivelyRequestedForStartupReadiness,
            allowPausedDirectPlayFirstFrame: allowsPausedDirectPlayFirstFrame
        ) {
            AppLog.playback.info(
                "playback.startup.readiness.ready — \(self.playbackLogScope(), privacy: .public) elapsed=0.00 buffered=\(self.bufferedDurationAhead(for: item, playbackPositionOverride: startupBufferPlaybackPosition), format: .fixed(precision: 1)) likely=\(item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull, privacy: .public) status=\(self.lastPlayerItemStatus, privacy: .public) early=false reason=\(requirement.reason, privacy: .public) source=\(firstFrameReadinessSource, privacy: .public)"
            )
            return true
        }

        let initialAccessEvent = item.accessLog()?.events.last
        let initialBufferedDuration = bufferedDurationAhead(
            for: item,
            playbackPositionOverride: startupBufferPlaybackPosition
        )
        if Self.shouldReleaseSparseResumedDirectPlayStartup(
            route: selection.decision.route,
            source: selection.source,
            resumeSeconds: resumeSeconds,
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            currentTime: player.currentTime().seconds,
            itemStatus: item.status,
            transcodeStartOffset: transcodeStartOffset,
            likelyToKeepUp: item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull,
            bufferedDuration: initialBufferedDuration,
            bufferStableDuration: 0,
            preheatResult: preheatResult,
            accessObservedBitrate: initialAccessEvent?.observedBitrate,
            accessStallCount: initialAccessEvent.map { Int($0.numberOfStalls) },
            selectedAudioTrackID: selectedAudioTrackID,
            isTVOS: Self.isTvOSPlatform
        ) {
            AppLog.playback.info(
                "playback.startup.readiness.ready — \(self.playbackLogScope(), privacy: .public) elapsed=0.00 buffered=\(initialBufferedDuration, format: .fixed(precision: 1)) likely=\(item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull, privacy: .public) status=\(self.lastPlayerItemStatus, privacy: .public) early=false reason=\(requirement.reason, privacy: .public) source=sparse_directplay_evidence preheatBitrate=\(Int(preheatResult?.observedBitrate ?? 0), privacy: .public) accessObservedBitrate=\(Int(initialAccessEvent?.observedBitrate ?? 0), privacy: .public)"
            )
            return true
        }

        player.pause()
        let didRequestStartupPreroll = beginStartupReadinessPrerollIfNeeded(
            item: item,
            selection: selection,
            requirement: requirement,
            playbackPositionOverride: startupBufferPlaybackPosition
        )
        let startedAt = Date()
        let observedPreheatBitrate = preheatResult?.observedBitrate ?? 0
        let preheatRangeStart = preheatResult?.rangeStart.map(String.init) ?? "none"
        AppLog.playback.info(
            "playback.startup.readiness.begin — \(self.playbackLogScope(), privacy: .public) reason=\(requirement.reason, privacy: .public) min=\(requirement.minimumBufferDuration, format: .fixed(precision: 1)) preferred=\(requirement.preferredBufferDuration, format: .fixed(precision: 1)) timeout=\(requirement.timeout, format: .fixed(precision: 1)) preheatBitrate=\(Int(observedPreheatBitrate), privacy: .public) preheatRangeStart=\(preheatRangeStart, privacy: .public)"
        )

        let requiresStableBuffer = Self.requiresStableStartupReadinessBuffer(
            route: selection.decision.route,
            source: selection.source,
            requirement: requirement,
            isTVOS: Self.isTvOSPlatform
        )
        var bufferReadySince: Date?
        var localGatewayPrimingStartTime: Double?
        var localGatewayPrimingPulseStartTime: Double?
        var localGatewayPrimingPulseCount = 0
        var didStartLocalGatewayPrimingPlayback = false
        let maxLocalGatewayPrimingPulseCount = 16
        while !Task.isCancelled {
            guard player.currentItem === item else { return false }

            let elapsed = Date().timeIntervalSince(startedAt)
            let bufferedDuration = bufferedDurationAhead(
                for: item,
                playbackPositionOverride: startupBufferPlaybackPosition
            )
            let likelyToKeepUp = item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull
            let now = Date()
            let rawBufferReady = PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: bufferedDuration,
                likelyToKeepUp: likelyToKeepUp,
                elapsedSeconds: elapsed,
                requirement: requirement
            )
            if rawBufferReady {
                bufferReadySince = bufferReadySince ?? now
            } else {
                bufferReadySince = nil
            }
            let bufferStableDuration = bufferReadySince.map { now.timeIntervalSince($0) } ?? 0

            if allowsFirstFrameStartupReadiness, Self.shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
                route: selection.decision.route,
                hasMarkedFirstFrame: hasMarkedFirstFrame,
                pendingResumeSeconds: pendingResumeSeconds,
                currentTime: player.currentTime().seconds,
                itemStatus: item.status,
                transcodeStartOffset: transcodeStartOffset,
                isPlaybackActive: isPlaybackActivelyRequestedForStartupReadiness,
                allowPausedDirectPlayFirstFrame: allowsPausedDirectPlayFirstFrame
            ) {
                AppLog.playback.info(
                    "playback.startup.readiness.ready — \(self.playbackLogScope(), privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2)) buffered=\(bufferedDuration, format: .fixed(precision: 1)) likely=\(likelyToKeepUp, privacy: .public) status=\(self.lastPlayerItemStatus, privacy: .public) early=false reason=\(requirement.reason, privacy: .public) source=\(firstFrameReadinessSource, privacy: .public)"
                )
                return true
            }

            let accessEvent = item.accessLog()?.events.last
            let gatewayDiagnostics = usesLocalGatewayForReadiness
                ? await localGatewayReadinessSession?.diagnostics()
                : nil

            if let primingPulseStartTime = localGatewayPrimingPulseStartTime,
               Self.shouldPauseLocalGatewayPrimingPlayback(
                route: selection.decision.route,
                source: selection.source,
                primingStartTime: primingPulseStartTime,
                currentTime: player.currentTime().seconds,
                bufferedDuration: bufferedDuration,
                gatewayDiagnostics: gatewayDiagnostics,
                isTVOS: Self.isTvOSPlatform
               ) {
                let totalProgress = player.currentTime().seconds - (localGatewayPrimingStartTime ?? primingPulseStartTime)
                let pulseProgress = player.currentTime().seconds - primingPulseStartTime
                AppLog.playback.notice(
                    "playback.startup.readiness.priming_pause — \(self.playbackLogScope(), privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2)) progress=\(totalProgress, format: .fixed(precision: 2)) pulse=\(pulseProgress, format: .fixed(precision: 2)) buffered=\(bufferedDuration, format: .fixed(precision: 1)) reason=\(requirement.reason, privacy: .public) source=local_gateway_cache"
                )
                localGatewayPrimingPulseStartTime = nil
                player.pause()
            }

            if Self.shouldReleaseSparseResumedDirectPlayStartup(
                route: selection.decision.route,
                source: selection.source,
                resumeSeconds: resumeSeconds,
                hasMarkedFirstFrame: hasMarkedFirstFrame,
                currentTime: player.currentTime().seconds,
                itemStatus: item.status,
                transcodeStartOffset: transcodeStartOffset,
                likelyToKeepUp: likelyToKeepUp,
                bufferedDuration: bufferedDuration,
                bufferStableDuration: bufferStableDuration,
                preheatResult: preheatResult,
                accessObservedBitrate: accessEvent?.observedBitrate,
                accessStallCount: accessEvent.map { Int($0.numberOfStalls) },
                selectedAudioTrackID: selectedAudioTrackID,
                isTVOS: Self.isTvOSPlatform
            ) {
                AppLog.playback.info(
                    "playback.startup.readiness.ready — \(self.playbackLogScope(), privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2)) buffered=\(bufferedDuration, format: .fixed(precision: 1)) likely=\(likelyToKeepUp, privacy: .public) status=\(self.lastPlayerItemStatus, privacy: .public) early=false reason=\(requirement.reason, privacy: .public) source=sparse_directplay_evidence preheatBitrate=\(Int(preheatResult?.observedBitrate ?? 0), privacy: .public) accessObservedBitrate=\(Int(accessEvent?.observedBitrate ?? 0), privacy: .public)"
                )
                if didRequestStartupPreroll {
                    player.cancelPendingPrerolls()
                }
                return true
            }

            if !didStartLocalGatewayPrimingPlayback,
               Self.shouldPrimeLocalGatewayResumedDirectPlayStartup(
                route: selection.decision.route,
                source: selection.source,
                resumeSeconds: resumeSeconds,
                hasMarkedFirstFrame: hasMarkedFirstFrame,
                currentTime: player.currentTime().seconds,
                itemStatus: item.status,
                transcodeStartOffset: transcodeStartOffset,
                preheatResult: preheatResult,
                bufferedDuration: bufferedDuration,
                accessStallCount: accessEvent.map { Int($0.numberOfStalls) },
                selectedAudioTrackID: selectedAudioTrackID,
                gatewayDiagnostics: gatewayDiagnostics,
                requirement: requirement,
                isTVOS: Self.isTvOSPlatform
               ) {
                let primingStart = player.currentTime().seconds
                localGatewayPrimingStartTime = primingStart
                localGatewayPrimingPulseStartTime = primingStart
                localGatewayPrimingPulseCount += 1
                didStartLocalGatewayPrimingPlayback = true
                let gatewayActiveStart = gatewayDiagnostics?.activePrefetchStartOffset ?? -1
                let gatewayActiveEnd = gatewayDiagnostics?.activePrefetchEndOffset ?? -1
                AppLog.playback.notice(
                    "playback.startup.readiness.priming_play — \(self.playbackLogScope(), privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2)) current=\(primingStart, format: .fixed(precision: 3)) buffered=\(bufferedDuration, format: .fixed(precision: 1)) reason=\(requirement.reason, privacy: .public) source=local_gateway_cache gatewayCachedBytes=\(gatewayDiagnostics?.cachedBytes ?? 0, privacy: .public) gatewayActiveStart=\(gatewayActiveStart, privacy: .public) gatewayActiveEnd=\(gatewayActiveEnd, privacy: .public) gatewayActiveStreaming=\(gatewayDiagnostics?.activePrefetchIsStreamingPlayback ?? false, privacy: .public)"
                )
                player.play()
            }

            if let localGatewayPrimingStartTime,
               localGatewayPrimingPulseStartTime == nil,
               localGatewayPrimingPulseCount < maxLocalGatewayPrimingPulseCount,
               Self.shouldResumeLocalGatewayPrimingPlayback(
                route: selection.decision.route,
                source: selection.source,
                resumeSeconds: resumeSeconds,
                currentTime: player.currentTime().seconds,
                preheatResult: preheatResult,
                accessStallCount: accessEvent.map { Int($0.numberOfStalls) },
                selectedAudioTrackID: selectedAudioTrackID,
                gatewayDiagnostics: gatewayDiagnostics,
                requirement: requirement,
                isTVOS: Self.isTvOSPlatform
               ) {
                let pulseStart = player.currentTime().seconds
                localGatewayPrimingPulseStartTime = pulseStart
                localGatewayPrimingPulseCount += 1
                let progress = pulseStart - localGatewayPrimingStartTime
                let gatewayActiveStart = gatewayDiagnostics?.activePrefetchStartOffset ?? -1
                let gatewayActiveEnd = gatewayDiagnostics?.activePrefetchEndOffset ?? -1
                AppLog.playback.notice(
                    "playback.startup.readiness.priming_resume — \(self.playbackLogScope(), privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2)) progress=\(progress, format: .fixed(precision: 2)) buffered=\(bufferedDuration, format: .fixed(precision: 1)) pulse=\(localGatewayPrimingPulseCount, privacy: .public) reason=\(requirement.reason, privacy: .public) source=local_gateway_cache gatewayCachedBytes=\(gatewayDiagnostics?.cachedBytes ?? 0, privacy: .public) gatewayActiveStart=\(gatewayActiveStart, privacy: .public) gatewayActiveEnd=\(gatewayActiveEnd, privacy: .public) gatewayActiveStreaming=\(gatewayDiagnostics?.activePrefetchIsStreamingPlayback ?? false, privacy: .public)"
                )
                player.play()
            }

            if let localGatewayPrimingStartTime,
               Self.shouldReleasePrimedLocalGatewayResumedDirectPlayStartup(
                route: selection.decision.route,
                source: selection.source,
                resumeSeconds: resumeSeconds,
                primingStartTime: localGatewayPrimingStartTime,
                hasMarkedFirstFrame: hasMarkedFirstFrame,
                currentTime: player.currentTime().seconds,
                itemStatus: item.status,
                transcodeStartOffset: transcodeStartOffset,
                preheatResult: preheatResult,
                likelyToKeepUp: likelyToKeepUp,
                bufferedDuration: bufferedDuration,
                accessObservedBitrate: accessEvent?.observedBitrate,
                accessStallCount: accessEvent.map { Int($0.numberOfStalls) },
                selectedAudioTrackID: selectedAudioTrackID,
                gatewayDiagnostics: gatewayDiagnostics,
                requirement: requirement,
                isTVOS: Self.isTvOSPlatform
               ) {
                let progress = player.currentTime().seconds - localGatewayPrimingStartTime
                let gatewayActiveStart = gatewayDiagnostics?.activePrefetchStartOffset ?? -1
                let gatewayActiveEnd = gatewayDiagnostics?.activePrefetchEndOffset ?? -1
                AppLog.playback.info(
                    "playback.startup.readiness.ready — \(self.playbackLogScope(), privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2)) buffered=\(bufferedDuration, format: .fixed(precision: 1)) likely=\(likelyToKeepUp, privacy: .public) status=\(self.lastPlayerItemStatus, privacy: .public) early=false reason=\(requirement.reason, privacy: .public) source=local_gateway_primed_playback progress=\(progress, format: .fixed(precision: 1)) gatewayBitrate=\(gatewayDiagnostics?.observedBitrate ?? 0, privacy: .public) gatewayActiveStart=\(gatewayActiveStart, privacy: .public) gatewayActiveEnd=\(gatewayActiveEnd, privacy: .public) gatewayActiveStreaming=\(gatewayDiagnostics?.activePrefetchIsStreamingPlayback ?? false, privacy: .public)"
                )
                if didRequestStartupPreroll {
                    player.cancelPendingPrerolls()
                }
                return true
            }

            if Self.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: selection.decision.route,
                source: selection.source,
                resumeSeconds: resumeSeconds,
                hasMarkedFirstFrame: hasMarkedFirstFrame,
                currentTime: player.currentTime().seconds,
                itemStatus: item.status,
                transcodeStartOffset: transcodeStartOffset,
                preheatResult: preheatResult,
                likelyToKeepUp: likelyToKeepUp,
                bufferedDuration: bufferedDuration,
                bufferStableDuration: bufferStableDuration,
                accessObservedBitrate: accessEvent?.observedBitrate,
                accessStallCount: accessEvent.map { Int($0.numberOfStalls) },
                selectedAudioTrackID: selectedAudioTrackID,
                gatewayDiagnostics: gatewayDiagnostics,
                requirement: requirement,
                isTVOS: Self.isTvOSPlatform
            ) {
                let cachedLength = max(
                    gatewayDiagnostics?.latestNonZeroCachedRangeLength ?? 0,
                    gatewayDiagnostics?.largestNonZeroCachedRangeLength ?? 0
                )
                let gatewayLargestOffset = gatewayDiagnostics?.largestNonZeroCachedOffset ?? 0
                let gatewayLatestOffset = gatewayDiagnostics?.latestNonZeroCachedOffset ?? 0
                let gatewayActiveStart = gatewayDiagnostics?.activePrefetchStartOffset ?? -1
                let gatewayActiveEnd = gatewayDiagnostics?.activePrefetchEndOffset ?? -1
                AppLog.playback.info(
                    "playback.startup.readiness.ready — \(self.playbackLogScope(), privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2)) buffered=\(bufferedDuration, format: .fixed(precision: 1)) likely=\(likelyToKeepUp, privacy: .public) status=\(self.lastPlayerItemStatus, privacy: .public) early=false reason=\(requirement.reason, privacy: .public) source=local_gateway_cache cachedBytes=\(cachedLength, privacy: .public) gatewayLargestOffset=\(gatewayLargestOffset, privacy: .public) gatewayLatestOffset=\(gatewayLatestOffset, privacy: .public) gatewayBitrate=\(gatewayDiagnostics?.observedBitrate ?? 0, privacy: .public) gatewayActiveStart=\(gatewayActiveStart, privacy: .public) gatewayActiveEnd=\(gatewayActiveEnd, privacy: .public) gatewayActiveStreaming=\(gatewayDiagnostics?.activePrefetchIsStreamingPlayback ?? false, privacy: .public)"
                )
                if didRequestStartupPreroll {
                    player.cancelPendingPrerolls()
                }
                return true
            }

            let bufferReady = rawBufferReady && (
                !requiresStableBuffer || Self.hasStableStartupReadinessBuffer(
                    bufferedDuration: bufferedDuration,
                    likelyToKeepUp: likelyToKeepUp,
                    stableDuration: bufferStableDuration
                )
            )
            let canStartBeforeReady = PlaybackStartupReadinessPolicy.allowsImmediateStartBeforeReadyToPlay(
                requirement: requirement
            )
            if bufferReady, item.status == .readyToPlay || canStartBeforeReady {
                AppLog.playback.info(
                    "playback.startup.readiness.ready — \(self.playbackLogScope(), privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2)) buffered=\(bufferedDuration, format: .fixed(precision: 1)) likely=\(likelyToKeepUp, privacy: .public) status=\(self.lastPlayerItemStatus, privacy: .public) early=\(canStartBeforeReady, privacy: .public) reason=\(requirement.reason, privacy: .public)"
                )
                return true
            }

            guard elapsed < requirement.timeout else {
                let gatewayCachedBytes = gatewayDiagnostics?.cachedBytes ?? 0
                let gatewayLargestOffset = gatewayDiagnostics?.largestNonZeroCachedOffset ?? 0
                let gatewayLargestNonZero = gatewayDiagnostics?.largestNonZeroCachedRangeLength ?? 0
                let gatewayLatestNonZero = gatewayDiagnostics?.latestNonZeroCachedRangeLength ?? 0
                let gatewayLatestOffset = gatewayDiagnostics?.latestNonZeroCachedOffset ?? 0
                let gatewayBitrate = gatewayDiagnostics?.observedBitrate ?? 0
                let gatewayActiveStart = gatewayDiagnostics?.activePrefetchStartOffset ?? -1
                let gatewayActiveEnd = gatewayDiagnostics?.activePrefetchEndOffset ?? -1
                let accessObservedBitrate = Int(accessEvent?.observedBitrate ?? 0)
                let accessStalls = accessEvent.map { Int($0.numberOfStalls) } ?? -1
                AppLog.playback.warning(
                    "playback.startup.readiness.timeout — \(self.playbackLogScope(), privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2)) buffered=\(bufferedDuration, format: .fixed(precision: 1)) likely=\(likelyToKeepUp, privacy: .public) status=\(self.lastPlayerItemStatus, privacy: .public) timeoutStart=\(requirement.allowsTimeoutStart, privacy: .public) reason=\(requirement.reason, privacy: .public) gatewayLoaded=\(usesLocalGatewayForReadiness, privacy: .public) gatewaySession=\(localGatewayReadinessSession != nil, privacy: .public) gatewayDiagnostics=\(gatewayDiagnostics != nil, privacy: .public) gatewayCachedBytes=\(gatewayCachedBytes, privacy: .public) gatewayLargestOffset=\(gatewayLargestOffset, privacy: .public) gatewayLargestNonZero=\(gatewayLargestNonZero, privacy: .public) gatewayLatestOffset=\(gatewayLatestOffset, privacy: .public) gatewayLatestNonZero=\(gatewayLatestNonZero, privacy: .public) gatewayBitrate=\(gatewayBitrate, privacy: .public) gatewayActiveStart=\(gatewayActiveStart, privacy: .public) gatewayActiveEnd=\(gatewayActiveEnd, privacy: .public) gatewayActiveStreaming=\(gatewayDiagnostics?.activePrefetchIsStreamingPlayback ?? false, privacy: .public) accessObservedBitrate=\(accessObservedBitrate, privacy: .public) accessStalls=\(accessStalls, privacy: .public)"
                )
                if didRequestStartupPreroll {
                    player.cancelPendingPrerolls()
                }
                return requirement.allowsTimeoutStart
            }
            let sleepNanoseconds = UInt64(max(0.05, requirement.pollInterval) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: sleepNanoseconds)
        }

        return false
    }

    @discardableResult
    private func beginStartupReadinessPrerollIfNeeded(
        item: AVPlayerItem,
        selection: PlaybackAssetSelection,
        requirement: PlaybackStartupReadinessPolicy.Requirement,
        playbackPositionOverride: Double?
    ) -> Bool {
        guard Self.shouldPrerollDuringStartupReadinessGate(
            route: selection.decision.route,
            source: selection.source,
            requirement: requirement,
            isTVOS: Self.isTvOSPlatform
        ) else {
            return false
        }
        guard player.currentItem === item else { return false }
        // AVPlayer.preroll raises NSInvalidArgumentException unless the item is already
        // readyToPlay. The readiness loop below proceeds without preroll and starts playback once
        // the status observer reports ready, so skipping here is safe (matches the video_preroll
        // guard). Without this, a slow-to-ready item (e.g. cache-loader cold start) crashes.
        guard item.status == .readyToPlay else {
            AppLog.playback.notice(
                "playback.startup.preroll.skipped — \(self.playbackLogScope(), privacy: .public) reason=item_not_ready status=\(self.lastPlayerItemStatus, privacy: .public)"
            )
            return false
        }

        AppLog.playback.info(
            "playback.startup.preroll.begin — \(self.playbackLogScope(), privacy: .public) reason=\(requirement.reason, privacy: .public) current=\(self.player.currentTime().seconds, format: .fixed(precision: 3)) buffered=\(self.bufferedDurationAhead(for: item, playbackPositionOverride: playbackPositionOverride), format: .fixed(precision: 1)) status=\(self.lastPlayerItemStatus, privacy: .public)"
        )
        player.preroll(atRate: 1.0) { [weak self, weak item] finished in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                AppLog.playback.info(
                    "playback.startup.preroll.done — \(self.playbackLogScope(), privacy: .public) finished=\(finished, privacy: .public) current=\(self.player.currentTime().seconds, format: .fixed(precision: 3)) buffered=\(self.bufferedDurationAhead(for: item, playbackPositionOverride: playbackPositionOverride), format: .fixed(precision: 1)) status=\(self.lastPlayerItemStatus, privacy: .public)"
                )
            }
        }
        return true
    }

    private func applyMeasuredHeadroomDirectPlayStartupPolicyIfNeeded() {
        guard let item = player.currentItem else { return }
        let policy = Self.measuredHeadroomDirectPlayStartupPolicy(
            startupClass: routeGuarantees.startupClass
        )
        if currentForwardBufferDuration != policy.forwardBufferDuration
            || player.automaticallyWaitsToMinimizeStalling != policy.waitsToMinimizeStalling {
            AppLog.playback.notice(
                "playback.directplay.buffering_override — \(self.playbackLogScope(), privacy: .public) buffer=\(policy.forwardBufferDuration, format: .fixed(precision: 1)) waits=\(policy.waitsToMinimizeStalling, privacy: .public) reason=\(policy.reason ?? "directplay_measured_headroom_fast_start", privacy: .public)"
            )
        }
        item.preferredForwardBufferDuration = policy.forwardBufferDuration
        currentForwardBufferDuration = policy.forwardBufferDuration
        player.automaticallyWaitsToMinimizeStalling = policy.waitsToMinimizeStalling
    }

    /// Switches direct play from its latency-biased startup buffer to a stability-biased
    /// steady-state buffer once the first frame has rendered. This is the proactive
    /// counterpart to `handlePostStartDirectPlayStallOnCurrentItem`, which only fired
    /// *after* the first stall (i.e. after the user already saw a freeze). Applying the
    /// cushion up front is what keeps playback from cutting to rebuffer after ~1 min.
    private func applyDirectPlaySteadyStateBufferingIfNeeded() {
        guard let item = player.currentItem else { return }
        guard let route = lastPreparedSelection?.decision.route else { return }
        guard let policy = DirectPlaySessionPolicy.steadyStateBuffering(
            route: route,
            source: currentSource,
            currentForwardBufferDuration: currentForwardBufferDuration,
            isTVOS: Self.isTvOSPlatform
        ) else { return }
        guard currentForwardBufferDuration != policy.forwardBufferDuration
            || player.automaticallyWaitsToMinimizeStalling != policy.waitsToMinimizeStalling else { return }
        AppLog.playback.notice(
            "playback.directplay.steady_state_buffering — \(self.playbackLogScope(), privacy: .public) buffer=\(policy.forwardBufferDuration, format: .fixed(precision: 1)) waits=\(policy.waitsToMinimizeStalling, privacy: .public) reason=post_first_frame_stability"
        )
        item.preferredForwardBufferDuration = policy.forwardBufferDuration
        currentForwardBufferDuration = policy.forwardBufferDuration
        player.automaticallyWaitsToMinimizeStalling = policy.waitsToMinimizeStalling
    }

    private func waitForCurrentItemReadyBeforeAutoplayAfterStartupSkip(
        route: PlaybackRoute,
        reason: String,
        timeout: TimeInterval = 6
    ) async -> Bool {
        guard let item = player.currentItem else { return true }
        guard Self.shouldWaitForItemReadyBeforeAutoplayAfterStartupSkip(
            route: route,
            itemStatus: item.status
        ) else {
            return item.status != .failed
        }

        let startedAt = Date()
        AppLog.playback.info(
            "playback.startup.item_ready.wait — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public) timeout=\(timeout, format: .fixed(precision: 1)) status=\(self.lastPlayerItemStatus, privacy: .public)"
        )

        while !Task.isCancelled {
            guard player.currentItem === item else { return false }
            switch item.status {
            case .readyToPlay:
                let elapsed = Date().timeIntervalSince(startedAt)
                AppLog.playback.info(
                    "playback.startup.item_ready.ready — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2))"
                )
                return true
            case .failed:
                AppLog.playback.warning(
                    "playback.startup.item_ready.failed — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public)"
                )
                return false
            default:
                break
            }

            let elapsed = Date().timeIntervalSince(startedAt)
            guard elapsed < timeout else {
                AppLog.playback.warning(
                    "playback.startup.item_ready.timeout — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2)) status=\(self.lastPlayerItemStatus, privacy: .public)"
                )
                return false
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return false
    }

    private func handlePostStartDirectPlayStallOnCurrentItem(
        item: AVPlayerItem,
        recentStallCount: Int,
        stallDate: Date,
        elapsedSinceFirstFrame: TimeInterval
    ) {
        let bufferDuration = Self.postStartDirectPlayStallBufferDuration(
            currentForwardBufferDuration: currentForwardBufferDuration,
            recentStallCount: recentStallCount,
            isTVOS: Self.isTvOSPlatform
        )
        let waitsToMinimizeStalling = DirectPlaySessionPolicy.postStartStallWaitsToMinimizeStalling(
            isTVOS: Self.isTvOSPlatform
        )
        item.preferredForwardBufferDuration = bufferDuration
        currentForwardBufferDuration = bufferDuration
        player.automaticallyWaitsToMinimizeStalling = waitsToMinimizeStalling

        guard DirectPlaySessionPolicy.shouldPauseForPostStartStallRebuffer(isTVOS: Self.isTvOSPlatform) else {
            player.play()
            AppLog.playback.warning(
                "playback.directplay.poststart_stall_wait — \(self.playbackLogScope(), privacy: .public) recentStalls=\(recentStallCount, privacy: .public) elapsed=\(stallDate.timeIntervalSince(self.startDate), format: .fixed(precision: 1))s firstFrameElapsed=\(elapsedSinceFirstFrame, format: .fixed(precision: 1))s buffer=\(bufferDuration, format: .fixed(precision: 1)) waits=\(waitsToMinimizeStalling, privacy: .public) action=keep_current_item"
            )
            return
        }

        player.pause()
        directPlayPostStartRebufferTask?.cancel()
        let buffered = bufferedDurationAhead(for: item)
        let timeout = DirectPlaySessionPolicy.postStartStallRebufferTimeout(
            recentStallCount: recentStallCount,
            isTVOS: Self.isTvOSPlatform
        )
        AppLog.playback.warning(
            "playback.directplay.poststart_rebuffer.wait — \(self.playbackLogScope(), privacy: .public) recentStalls=\(recentStallCount, privacy: .public) elapsed=\(stallDate.timeIntervalSince(self.startDate), format: .fixed(precision: 1))s firstFrameElapsed=\(elapsedSinceFirstFrame, format: .fixed(precision: 1))s buffered=\(buffered, format: .fixed(precision: 1)) target=\(bufferDuration, format: .fixed(precision: 1)) timeout=\(timeout, format: .fixed(precision: 1)) waits=\(waitsToMinimizeStalling, privacy: .public) action=pause_current_item"
        )
        directPlayPostStartRebufferTask = Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            let ready = await self.waitForPostStartDirectPlayRebuffer(
                item: item,
                targetBufferDuration: bufferDuration,
                timeout: timeout
            )
            guard self.player.currentItem === item else { return }
            guard ready else {
                AppLog.playback.error(
                    "playback.directplay.poststart_rebuffer.timeout — \(self.playbackLogScope(), privacy: .public) recentStalls=\(recentStallCount, privacy: .public) buffered=\(self.bufferedDurationAhead(for: item), format: .fixed(precision: 1)) target=\(bufferDuration, format: .fixed(precision: 1)) action=hold_current_item"
                )
                self.playbackErrorMessage = "Direct Play is still buffering."
                return
            }

            AppLog.playback.notice(
                "playback.directplay.poststart_rebuffer.ready — \(self.playbackLogScope(), privacy: .public) recentStalls=\(recentStallCount, privacy: .public) buffered=\(self.bufferedDurationAhead(for: item), format: .fixed(precision: 1)) target=\(bufferDuration, format: .fixed(precision: 1)) action=resume_current_item"
            )
            self.playbackErrorMessage = nil
            self.player.play()
        }
    }

    /// Arm the sustained-stall watchdog after a post-start direct-play stall that we chose to ride
    /// out on the original (Dolby Vision) stream rather than escalate immediately. If playback has
    /// progressed past `stallPosition` by the time the grace window elapses, it was a transient blip
    /// AVPlayer re-buffered — keep full-quality DV and do nothing. If it is still stuck, the
    /// connection genuinely can't carry the original bitrate right now: escalate ONCE to the
    /// watchable adaptive transcode (`directPlayStall` → forceH264Transcode SDR) so playback
    /// continues instead of freezing. Recovery-scoped; only runs when the adaptive backstop is on
    /// and a quality drop is permitted.
    private func scheduleDirectPlayStallEscalationWatchdog(item: AVPlayerItem, stallPosition: Double) {
        directPlayStallEscalationTask?.cancel()
        guard AdaptiveFallbackPolicy.isEnabled, !strictQualityIsActive else { return }
        let grace = DirectPlaySessionPolicy.sustainedStallEscalationGraceSeconds
        directPlayStallEscalationTask = Task { @MainActor [weak self, weak item] in
            try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
            guard !Task.isCancelled, let self, let item else { return }
            guard self.player.currentItem === item else { return }
            // Progressed past the stall point → transient blip recovered on DV. Keep full quality.
            let nowPosition = item.currentTime().seconds
            if nowPosition.isFinite, stallPosition.isFinite, nowPosition - stallPosition > 1.0 {
                return
            }
            guard !self.strictQualityIsActive,
                  !self.isRecoveryInProgress,
                  self.recoveryAttemptCount < self.maxRecoveryAttempts,
                  let route = self.lastPreparedSelection?.decision.route,
                  Self.shouldKeepCurrentDirectPlayItemAfterPostStartStall(
                    route: route,
                    source: self.currentSource,
                    isTVOS: Self.isTvOSPlatform
                  )
            else { return }
            AppLog.playback.warning(
                "playback.directplay.escalate_adaptive_transcode — \(self.playbackLogScope(), privacy: .public) recentStalls=\(self.recentStallTimestamps.count, privacy: .public) reason=sustained_stall graceSeconds=\(grace, format: .fixed(precision: 0))"
            )
            // Detach before recovery: attemptRecovery tears down the current item (which cancels
            // this task). Clearing the handle first keeps that teardown from cancelling the
            // in-flight escalation we are currently running.
            self.directPlayStallEscalationTask = nil
            _ = await self.attemptRecovery(
                reason: StartupFailureReason.directPlayStall.rawValue,
                userMessage: "Adapting to your connection…"
            )
        }
    }

    private func waitForPostStartDirectPlayRebuffer(
        item: AVPlayerItem,
        targetBufferDuration: TimeInterval,
        timeout: TimeInterval
    ) async -> Bool {
        let startedAt = Date()
        while !Task.isCancelled {
            guard player.currentItem === item else { return false }
            guard item.status != .failed else { return false }
            if bufferedDurationAhead(for: item) >= targetBufferDuration {
                return true
            }
            guard Date().timeIntervalSince(startedAt) < timeout else {
                return false
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return false
    }

    private func logUnsafeDirectPlayStartupHeadroomIfNeeded(
        selection: PlaybackAssetSelection,
        preheatResult: PlaybackStartupPreheater.Result?,
        serverBaselineResult: PlaybackServerNetworkBaseline.Result?
    ) {
        guard preheatResult != nil || serverBaselineResult != nil else { return }
        guard let reason = Self.directPlayPrestartRecoveryReason(
            route: selection.decision.route,
            sourceBitrate: selection.source.bitrate,
            sourceIsHDRorDV: selection.source.isLikelyHDRorDV,
            preheatResult: preheatResult,
            serverBaselineResult: serverBaselineResult,
            isTVOS: Self.isTvOSPlatform
        ) else {
            return
        }

        logDirectPlayPrestartHeadroom(
            selection: selection,
            preheatResult: preheatResult,
            serverBaselineResult: serverBaselineResult,
            reason: reason,
            action: "keep_directplay"
        )
    }

    private func logDirectPlayPrestartHeadroom(
        selection: PlaybackAssetSelection,
        preheatResult: PlaybackStartupPreheater.Result?,
        serverBaselineResult: PlaybackServerNetworkBaseline.Result?,
        reason: StartupFailureReason,
        action: String
    ) {
        let sourceBitrate = selection.source.bitrate ?? 0
        let observedBitrate = Int(preheatResult?.observedBitrate ?? 0)
        let baselineBitrate = Int(serverBaselineResult?.observedBitrate ?? 0)
        let rangeStart = preheatResult?.rangeStart.map(String.init) ?? "none"
        AppLog.playback.warning(
            "playback.directplay.prestart_headroom — \(self.playbackLogScope(), privacy: .public) reason=\(reason.rawValue, privacy: .public) action=\(action, privacy: .public) sourceBitrate=\(sourceBitrate, privacy: .public) preheatBitrate=\(observedBitrate, privacy: .public) baselineBitrate=\(baselineBitrate, privacy: .public) rangeStart=\(rangeStart, privacy: .public)"
        )
    }

    private func attemptStartupRecoveryIfAvailable(
        reason: String,
        userMessage: String
    ) async -> Bool {
        if Self.shouldAttemptSameRouteDirectPlayRecovery(reason: reason),
           await attemptDirectPlaySameRouteRecoveryIfAvailable(reason: reason) {
            return true
        }
        guard Self.hasStartupRecoveryCandidate(
            after: activeTranscodeProfile,
            playbackPolicy: playbackPolicy,
            allowSDRFallback: allowSDRFallback,
            usesDirectRemuxOnly: usesDirectRemuxOnly
        ) else {
            return false
        }

        return await attemptRecovery(reason: reason, userMessage: userMessage)
    }

    private func logStartupRecoveryUnavailable(reason: String, action: String) {
        AppLog.playback.warning(
            "playback.startup.recovery_unavailable — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public) profile=\(self.activeTranscodeProfile.rawValue, privacy: .public) status=\(self.lastPlayerItemStatus, privacy: .public) action=\(action, privacy: .public)"
        )
    }

    private func blockUnsafeDirectPlayStartupPlayback(reason: String, userMessage: String) {
        directPlayStartupPlaybackBlocked = true
        directPlayPostStartRebufferTask?.cancel()
        directPlayPostStartRebufferTask = nil
        player.pause()
        playbackErrorMessage = userMessage
        AppLog.playback.warning(
            "playback.startup.playback_blocked — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public) action=hold_current_item"
        )
    }

    private func ignorePlayRequestAfterUnsafeDirectPlayStartup(trigger: String) -> Bool {
        guard Self.shouldIgnorePlayRequestAfterUnsafeDirectPlayStartup(
            startupPlaybackBlocked: directPlayStartupPlaybackBlocked,
            route: lastPreparedSelection?.decision.route
        ) else {
            return false
        }

        player.pause()
        isPlaying = false
        AppLog.playback.warning(
            "playback.startup.blocked_play_ignored — \(self.playbackLogScope(), privacy: .public) trigger=\(trigger, privacy: .public)"
        )
        return true
    }

    private func prepareSynchronizedStartupFrameIfNeeded(
        selection: PlaybackAssetSelection
    ) async -> Bool {
        guard Self.shouldPrerollVideoBeforeAudioStart(
            route: selection.decision.route,
            source: selection.source,
            isTVOS: Self.isTvOSPlatform
        ) else {
            if case .directPlay = selection.decision.route {
                AppLog.playback.debug(
                    "playback.startup.video_preroll.skipped — \(self.playbackLogScope(), privacy: .public) reason=policy_not_required bitrate=\(selection.source.bitrate ?? 0, privacy: .public)"
                )
            }
            return true
        }
        guard let item = player.currentItem else { return true }
        guard item.status == .readyToPlay else { return false }
        guard player.currentItem === item else { return false }

        player.pause()
        refreshDecodedVideoFrameState()
        if hasDecodedVideoFrame {
            AppLog.playback.info(
                "playback.startup.video_preroll.ready — \(self.playbackLogScope(), privacy: .public) elapsed=0.00 reason=directplay_audio_video_sync source=decoded_frame_already_available"
            )
            return true
        }

        let timeout: TimeInterval = 6
        let startedAt = Date()
        AppLog.playback.info(
            "playback.startup.video_preroll.begin — \(self.playbackLogScope(), privacy: .public) timeout=\(timeout, format: .fixed(precision: 1)) reason=directplay_audio_video_sync"
        )
        player.preroll(atRate: 1.0, completionHandler: nil)

        while !Task.isCancelled {
            guard player.currentItem === item else { return false }
            refreshDecodedVideoFrameState()
            if hasDecodedVideoFrame {
                let elapsed = Date().timeIntervalSince(startedAt)
                AppLog.playback.info(
                    "playback.startup.video_preroll.ready — \(self.playbackLogScope(), privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2)) reason=directplay_audio_video_sync"
                )
                return true
            }

            let elapsed = Date().timeIntervalSince(startedAt)
            guard elapsed < timeout else {
                player.cancelPendingPrerolls()
                AppLog.playback.warning(
                    "playback.startup.video_preroll.timeout — \(self.playbackLogScope(), privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2)) reason=directplay_audio_video_sync"
                )
                return false
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return false
    }

    private func bufferedDurationAhead(
        for item: AVPlayerItem,
        playbackPositionOverride: Double? = nil
    ) -> Double {
        let currentSeconds = playbackPositionOverride ?? player.currentTime().seconds
        let playbackPosition = currentSeconds.isFinite ? max(0, currentSeconds) : 0

        return Self.bufferedDurationAhead(
            playbackPosition: playbackPosition,
            loadedTimeRanges: item.loadedTimeRanges.map(\.timeRangeValue)
        )
    }

    private func emitDeepPlaybackEvidenceIfNeeded(
        for item: AVPlayerItem,
        currentSeconds: Double
    ) {
        guard Self.isDeepPlaybackEvidenceEnabled else { return }
        guard hasMarkedFirstFrame, currentSeconds.isFinite else { return }

        let now = Date()
        if let lastLogDate = lastDeepPlaybackEvidenceLogDate,
           now.timeIntervalSince(lastLogDate) < Self.deepPlaybackEvidenceIntervalSeconds {
            return
        }

        let delta = lastDeepPlaybackEvidencePlaybackTime.map { currentSeconds - $0 } ?? 0
        lastDeepPlaybackEvidenceLogDate = now
        lastDeepPlaybackEvidencePlaybackTime = currentSeconds

        let status = Self.timeControlStatusLabel(player.timeControlStatus)
        let waitingReason = Self.compactLogValue(player.reasonForWaitingToPlay?.rawValue ?? "none")
        let likely = item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull
        let buffered = bufferedDurationAhead(for: item)
        let ranges = Self.loadedRangesSummary(for: item, playbackPosition: currentSeconds)
        let event = item.accessLog()?.events.last
        let audioTrack = selectedAudioTrackForEvidence()
        let audioCodec = audioTrack?.codec ?? currentSource?.audioCodec ?? "unknown"
        let audioID = audioTrack?.id ?? selectedAudioTrackID ?? "none"
        let audioTitle = audioTrack?.title ?? "none"
        PlayerDeepEvidenceSink.append(
            "playback.deep.tick — \(playbackLogScope()) current=\(String(format: "%.3f", currentSeconds)) delta=\(String(format: "%.3f", delta)) rate=\(player.rate) timeControl=\(status) waitingReason=\(waitingReason) itemStatus=\(lastPlayerItemStatus) likely=\(likely) buffered=\(String(format: "%.1f", buffered)) ranges=\(ranges) droppedFrames=\(metrics.droppedFrames) observedBitrate=\(playbackProof.observedBitrate ?? 0) accessObservedBitrate=\(Int(event?.observedBitrate ?? 0)) accessIndicatedBitrate=\(Int(event?.indicatedBitrate ?? 0)) accessStalls=\(event?.numberOfStalls ?? 0) accessTransferDuration=\(String(format: "%.3f", event?.transferDuration ?? 0)) audioID=\(audioID) audioCodec=\(audioCodec) audioTrack='\(audioTitle)' method=\(playMethodForReporting)"
        )
        AppLog.playback.info(
            "playback.deep.tick — \(self.playbackLogScope(), privacy: .public) current=\(currentSeconds, format: .fixed(precision: 3)) delta=\(delta, format: .fixed(precision: 3)) rate=\(self.player.rate, privacy: .public) timeControl=\(status, privacy: .public) waitingReason=\(waitingReason, privacy: .public) itemStatus=\(self.lastPlayerItemStatus, privacy: .public) likely=\(likely, privacy: .public) buffered=\(buffered, format: .fixed(precision: 1)) ranges=\(ranges, privacy: .public) droppedFrames=\(self.metrics.droppedFrames, privacy: .public) observedBitrate=\(self.playbackProof.observedBitrate ?? 0, privacy: .public) accessObservedBitrate=\(Int(event?.observedBitrate ?? 0), privacy: .public) accessIndicatedBitrate=\(Int(event?.indicatedBitrate ?? 0), privacy: .public) accessStalls=\(event?.numberOfStalls ?? 0, privacy: .public) accessTransferDuration=\(event?.transferDuration ?? 0, format: .fixed(precision: 3)) audioID=\(audioID, privacy: .public) audioCodec=\(audioCodec, privacy: .public) audioTrack='\(audioTitle, privacy: .public)' method=\(self.playMethodForReporting, privacy: .public)"
        )
    }

    private func selectedAudioTrackForEvidence() -> MediaTrack? {
        if let selectedAudioTrackID,
           let selected = availableAudioTracks.first(where: { $0.id == selectedAudioTrackID }) {
            return selected
        }
        return availableAudioTracks.first(where: { $0.isDefault }) ?? availableAudioTracks.first
    }

    nonisolated private static func loadedRangesSummary(
        for item: AVPlayerItem,
        playbackPosition: Double
    ) -> String {
        let ranges = item.loadedTimeRanges.prefix(3).map(\.timeRangeValue).map { range in
            let start = range.start.seconds
            let end = CMTimeRangeGetEnd(range).seconds
            guard start.isFinite, end.isFinite else { return "invalid" }
            let ahead = max(0, end - max(0, playbackPosition))
            return "\(String(format: "%.1f", start))-\(String(format: "%.1f", end))+\(String(format: "%.1f", ahead))"
        }
        return ranges.isEmpty ? "none" : ranges.joined(separator: ",")
    }

    nonisolated private static func compactLogValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\t", with: "_")
    }

    private func scheduleStartupWatchdog() {
        startupWatchdogTask?.cancel()
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
                    "playback.startup.failure — \(self.playbackLogScope(), privacy: .public) reason=\(reason.rawValue, privacy: .public) profile=\(self.activeTranscodeProfile.rawValue, privacy: .public) hardDeadline=\(totalDelay, format: .fixed(precision: 1))s status=readyToPlay decodedFrame=false"
                )
                if !(await self.attemptRecoveryPreservingDirectPlay(
                    reason: reason.rawValue,
                    userMessage: "No video frame after readyToPlay. Retrying playback."
                )), self.playbackErrorMessage == nil {
                    self.playbackErrorMessage = "No video frame received. Try changing quality or source."
                }
                return
            }

            AppLog.playback.warning("playback.watchdog.startup — \(self.playbackLogScope(), privacy: .public) elapsed=\(delaySeconds, format: .fixed(precision: 1))s decodedFrame=false")
            if !(await self.attemptRecoveryPreservingDirectPlay(
                reason: StartupFailureReason.startupWatchdogExpired.rawValue,
                userMessage: "Startup was too slow. Retrying playback."
            )), self.playbackErrorMessage == nil {
                self.playbackErrorMessage = "No video frame received. Try changing quality or source."
            }
        }
    }

    private func scheduleDecodedFrameWatchdog() {
        decodedFrameWatchdogTask?.cancel()
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
            let playbackHasStarted = Self.decodedFrameWatchdogPlaybackHasStarted(
                playerSeconds: playerSeconds,
                absolutePlaybackSeconds: playbackSeconds,
                transcodeStartOffset: self.transcodeStartOffset
            )
            guard playbackHasStarted else { return }

            let delaySeconds = Double(delay) / 1_000_000_000
            AppLog.playback.warning("playback.watchdog.decoded_frame — \(self.playbackLogScope(), privacy: .public) elapsed=\(delaySeconds, format: .fixed(precision: 1))s playbackTime=\(playbackSeconds, format: .fixed(precision: 2)) profile=\(self.activeTranscodeProfile.rawValue, privacy: .public)")
            if !(await self.attemptRecoveryPreservingDirectPlay(
                reason: StartupFailureReason.decodedFrameWatchdog.rawValue,
                userMessage: "Video decoding did not start quickly enough. Retrying playback."
            )), self.playbackErrorMessage == nil {
                self.playbackErrorMessage = "Video decoding did not start."
            }
        }
    }

    private func decodedFrameWatchdogDelayNanoseconds() -> UInt64 {
        Self.decodedFrameWatchdogDelayNanoseconds(
            activeProfile: activeTranscodeProfile,
            isHEVCStreamCopyTranscode: isCurrentHEVCStreamCopyTranscode(),
            isStallResistantDirectPlay: isCurrentStallResistantDirectPlay()
        )
    }

    nonisolated static func decodedFrameWatchdogDelayNanoseconds(
        activeProfile: TranscodeURLProfile,
        isHEVCStreamCopyTranscode: Bool,
        isStallResistantDirectPlay: Bool
    ) -> UInt64 {
        if isStallResistantDirectPlay {
            return 30_000_000_000
        }

        switch activeProfile {
        case .serverDefault:
            return isHEVCStreamCopyTranscode ? 3_000_000_000 : 5_000_000_000
        case .appleOptimizedHEVC:
            return 5_000_000_000
        case .conservativeCompatibility:
            return 5_000_000_000
        case .forceH264Transcode:
            return 4_000_000_000
        }
    }

    private func startupWatchdogDelayNanoseconds() -> UInt64 {
        let base = Self.startupWatchdogDelayNanoseconds(
            activeProfile: activeTranscodeProfile,
            currentItemHasDolbyVision: currentItemHasDolbyVision,
            isHEVCStreamCopyTranscode: isCurrentHEVCStreamCopyTranscode(),
            isStallResistantDirectPlay: isCurrentStallResistantDirectPlay()
        )
        // The cache loader / localhost cache proxy's first range request to an idle origin item can
        // cold-start for ~15s (server/CF warm up the file). Give it the same grace as stall-resistant
        // direct play so the watchdog doesn't tear it down mid-warm-up before it reaches readyToPlay.
        if cacheResourceLoader != nil || cacheProxyServer != nil {
            return max(base, 30_000_000_000)
        }
        return base
    }

    nonisolated static func startupWatchdogDelayNanoseconds(
        activeProfile: TranscodeURLProfile,
        currentItemHasDolbyVision: Bool,
        isHEVCStreamCopyTranscode: Bool,
        isStallResistantDirectPlay: Bool
    ) -> UInt64 {
        if isStallResistantDirectPlay {
            return 30_000_000_000
        }

        switch activeProfile {
        case .serverDefault:
            return isHEVCStreamCopyTranscode ? 6_000_000_000 : 8_000_000_000
        case .appleOptimizedHEVC:
            // HEVC startup on large HDR/DV assets can legitimately exceed 8s.
            // Give more room before switching to an SDR fallback profile.
            return currentItemHasDolbyVision ? 14_000_000_000 : 10_000_000_000
        case .conservativeCompatibility:
            // Stream-copy DV/HDR content may take longer for AVPlayer to parse
            // the init segment and produce the first decoded frame.
            return currentItemHasDolbyVision ? 12_000_000_000 : 8_000_000_000
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
        if !AdaptiveFallbackPolicy.isEnabled, Self.shouldBlockLegacyCoordinatorRecovery(
            isNativePlayerActive: isNativePlayerActive,
            nativeSurface: nativePlayerPlaybackSurface
        ) {
            let message = NativePlayerRouteViolation.serverTranscodeBlockedByConfig.localizedDescription
            AppLog.playback.error(
                "nativeplayer.route.guard.blocked — \(self.playbackLogScope(), privacy: .public) reason=\(message, privacy: .public) trigger=\(reason, privacy: .public)"
            )
            playbackErrorMessage = message
            return false
        }
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
            AppLog.playback.notice("playback.fallback.step — \(self.playbackLogScope(attempt: attempt), privacy: .public) action=\(action.rawValue, privacy: .public)")
        }
        let elapsed = Date().timeIntervalSince(startDate) * 1000
        AppLog.playback.warning(
            "playback.fallback.triggered — \(self.playbackLogScope(attempt: attempt), privacy: .public) reason=\(reason, privacy: .public) fromProfile=\(self.activeTranscodeProfile.rawValue, privacy: .public) elapsedMs=\(elapsed, format: .fixed(precision: 1)) maxAttempts=\(self.maxRecoveryAttempts, privacy: .public)"
        )
        if nativeModeCoordinatorFallbackRootReason == nil,
           Self.shouldStartNativeModeCoordinatorFallbackChain(reason: reason) {
            nativeModeCoordinatorFallbackRootReason = reason
        }
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

    private func attemptRecoveryPreservingDirectPlay(
        reason: String,
        userMessage: String,
        retryDelayNanoseconds: UInt64 = 0
    ) async -> Bool {
        if Self.shouldAttemptSameRouteDirectPlayRecovery(reason: reason),
           Self.shouldPreserveDirectPlayRecovery(route: lastPreparedSelection?.decision.route) {
            if let selection = lastPreparedSelection,
               Self.shouldBypassSameRouteDirectPlayRecovery(
                reason: reason,
                preparedSelection: selection,
                hasMarkedFirstFrame: hasMarkedFirstFrame,
                failureDomain: lastFailureDomain,
                failureCode: lastFailureCode
               ) {
                localMediaGatewayDisabledSourceIDs.insert(selection.source.id)
                stopLocalMediaGateway(reason: "directplay_recovery_transport_failure")
                AppLog.playback.warning(
                    "playback.cache.gateway.bypassed — \(self.playbackLogScope(), privacy: .public) source=\(selection.source.id, privacy: .public) reason=directplay_avfoundation_transport_failure"
                )
                AppLog.playback.warning(
                    "playback.directplay.same_route_recovery_skipped — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public) failureDomain=\(self.lastFailureDomain ?? "unknown", privacy: .public) failureCode=\(self.lastFailureCode ?? 0, privacy: .public)"
                )
                return await attemptRecovery(
                    reason: reason,
                    userMessage: userMessage,
                    retryDelayNanoseconds: retryDelayNanoseconds
                )
            }
            if await attemptDirectPlaySameRouteRecoveryIfAvailable(reason: reason) {
                return true
            }
            if Self.shouldUseProfileFallbackAfterSameRouteDirectPlayRecoveryFailure(reason: reason) {
                AppLog.playback.warning(
                    "playback.directplay.profile_fallback_after_same_route_failed — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public)"
                )
                return await attemptRecovery(
                    reason: reason,
                    userMessage: userMessage,
                    retryDelayNanoseconds: retryDelayNanoseconds
                )
            }
            AppLog.playback.warning(
                "playback.directplay.profile_fallback_suppressed — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public)"
            )
            return false
        }

        return await attemptRecovery(
            reason: reason,
            userMessage: userMessage,
            retryDelayNanoseconds: retryDelayNanoseconds
        )
    }

    private func attemptDirectPlaySameRouteRecoveryIfAvailable(reason: String) async -> Bool {
        guard !didAttemptDirectPlayStallRecovery else { return false }
        guard let selection = lastPreparedSelection else { return false }
        guard case .directPlay = selection.decision.route else { return false }
        guard Self.canAttemptSameRouteDirectPlayRecovery(
            preparedSelection: selection,
            gatewayRemoteSelection: localMediaGatewayRemoteSelection
        ) else {
            AppLog.playback.warning(
                "playback.directplay.same_route_recovery_skipped — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public) detail=local_gateway_remote_unavailable"
            )
            return false
        }

        didAttemptDirectPlayStallRecovery = true
        AppLog.playback.warning(
            "playback.directplay.same_route_recovery — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public)"
        )
        return await attemptDirectPlayStallRecovery(reason: reason)
    }

    private func handlePlaybackFailure(message: String, error: NSError?) async -> Bool {
        if Self.shouldSuppressPlaybackFailureRecoveryAfterFirstFrame(
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            route: lastPreparedSelection?.decision.route
        ) {
            AppLog.playback.error(
                "playback.poststart.recovery_suppressed — \(self.playbackLogScope(), privacy: .public) message=\(message, privacy: .public)"
            )
            return false
        }

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
            return await attemptRecoveryPreservingDirectPlay(
                reason: StartupFailureReason.playerItemFailedTransient.rawValue,
                userMessage: "Network hiccup detected. Retrying playback…",
                retryDelayNanoseconds: delay
            )
        }

        if recoveryAttemptCount < maxRecoveryAttempts {
            return await attemptRecoveryPreservingDirectPlay(
                reason: StartupFailureReason.playerItemFailed.rawValue,
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
        let resumeSeconds = recoveryResumeSeconds()
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
            let probeURL: URL
            if let cachedProbeURL = cachedPreflightProbeURL(for: selection) {
                probeURL = cachedProbeURL
            } else {
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

    private func cachedPreflightProbeURL(for selection: PlaybackAssetSelection) -> URL? {
        guard selection.assetURL == selectedVariantInfo?.resolvedURL else { return nil }
        guard let firstSegmentURI = selectedVariantPlaylistInspection?.firstSegmentURI else { return nil }
        guard let probeURL = resolveSegmentURL(
            firstSegmentLine: firstSegmentURI,
            masterURL: selection.assetURL
        ) else {
            return nil
        }

        AppLog.playback.notice(
            "Preflight reusing pinned variant inspection url=\(selection.assetURL.reelfinLogString, privacy: .public)"
        )
        return probeURL
    }

    private func repairInitialSelectionIfNeeded(
        itemID: String,
        selection: PlaybackAssetSelection,
        mode: PlaybackMode,
        startTimeTicks: Int64?,
        itemPrefersDolbyVision: Bool
    ) async throws -> PlaybackAssetSelection {
        guard case .transcode = selection.decision.route else { return selection }
        guard !(await preflightSelection(selection)) else { return selection }

        AppLog.playback.error(
            "Initial playback preflight failed profile=\(self.activeTranscodeProfile.rawValue, privacy: .public). Trying safer source selection."
        )

        for profile in recoveryProfiles(
            for: StartupFailureReason.firstSegmentTimeout.rawValue,
            attempt: max(recoveryAttemptCount, 1)
        ) {
            do {
                var candidate = try await coordinator.resolvePlayback(
                    itemID: itemID,
                    mode: mode,
                    allowTranscodingFallbackInPerformance: !usesDirectRemuxOnly,
                    transcodeProfile: profile,
                    startTimeTicks: startTimeTicks
                )
                candidate = try await pinPreferredVariantIfNeeded(
                    selection: candidate,
                    itemPrefersDolbyVision: itemPrefersDolbyVision,
                    profileOverride: Self.variantPinningProfile(
                        from: candidate.assetURL,
                        requestedProfile: profile
                    )
                )
                candidate = try await stabilizeInitialSelectionIfNeeded(
                    itemID: itemID,
                    selection: candidate,
                    startTimeTicks: startTimeTicks,
                    itemPrefersDolbyVision: itemPrefersDolbyVision
                )
                candidate = try await upgradeRiskyInitialSelectionIfNeeded(
                    itemID: itemID,
                    selection: candidate,
                    startTimeTicks: startTimeTicks,
                    itemPrefersDolbyVision: itemPrefersDolbyVision
                )

                let candidateProfile = inferredTranscodeProfile(from: candidate.assetURL, fallback: profile)
                guard registerAttempt(selection: candidate, profile: candidateProfile) else {
                    continue
                }
                guard await preflightSelection(candidate) else {
                    AppLog.playback.warning(
                        "Initial playback preflight also failed for recovery profile=\(candidateProfile.rawValue, privacy: .public)."
                    )
                    continue
                }

                activeTranscodeProfile = candidateProfile
                return candidate
            } catch {
                AppLog.playback.warning(
                    "Initial preflight recovery failed profile=\(profile.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        throw AppError.network("The server returned a playlist, but the first media segment could not be loaded.")
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

        if let variant = selectedVariantInfo,
           Self.isDegradedStartupVariant(width: variant.width, bandwidth: variant.bandwidth) {
            return true
        }

        do {
            let manifest = try await fetchPlaylist(url: selection.assetURL, headers: selection.headers)
            guard let streamInfLine = manifest.split(whereSeparator: \.isNewline).map(String.init).first(where: {
                $0.hasPrefix("#EXT-X-STREAM-INF:")
            }) else {
                return false
            }

            let bandwidth = parseIntAttribute("BANDWIDTH", from: streamInfLine)
            let (width, _) = parseResolution(from: streamInfLine)

            return Self.isDegradedStartupVariant(width: width, bandwidth: bandwidth)
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
        AppLog.playback.notice("playback.hls.fetch.start — \(self.playbackLogScope(), privacy: .public) kind=playlist url=\(url.reelfinCompactLogString, privacy: .public)")
        let request = makeProbeRequest(url: url, headers: headers, range: nil)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw AppError.network("Playlist request failed.")
        }

        guard let manifest = String(data: data, encoding: .utf8), manifest.contains("#EXTM3U") else {
            throw AppError.network("Invalid HLS playlist.")
        }
        AppLog.playback.notice("playback.hls.fetch.ok — \(self.playbackLogScope(), privacy: .public) kind=playlist status=\(http.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) url=\(url.reelfinCompactLogString, privacy: .public)")
        return manifest
    }

    private func fetchInitSegmentData(url: URL, headers: [String: String]) async throws -> Data {
        AppLog.playback.notice("playback.hls.fetch.start — \(self.playbackLogScope(), privacy: .public) kind=init_segment url=\(url.reelfinCompactLogString, privacy: .public)")
        let request = makeProbeRequest(url: url, headers: headers, range: "bytes=0-524287")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) || http.statusCode == 206 else {
            throw AppError.network("Failed to fetch init segment.")
        }
        guard !data.isEmpty else {
            throw AppError.network("Init segment is empty.")
        }
        AppLog.playback.notice("playback.hls.fetch.ok — \(self.playbackLogScope(), privacy: .public) kind=init_segment status=\(http.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) url=\(url.reelfinCompactLogString, privacy: .public)")
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
        preferredSubtitleLanguage: String?,
        maxStreamingBitrate: Int,
        nativePlayerConfig: NativePlayerConfig
    ) {
        guard let configuration = await apiClient.currentConfiguration() else {
            return (.auto, true, true, nil, nil, QualityPreference.auto.maxStreamingBitrate, NativePlayerConfig())
        }
        let nativeConfig = configuration.nativePlayerConfig.applyingRuntimeOverride()
        return (
            configuration.playbackPolicy,
            configuration.allowSDRFallback,
            configuration.preferAudioTranscodeOnly,
            configuration.preferredAudioLanguage,
            configuration.preferredSubtitleLanguage,
            configuration.effectiveMaxStreamingBitrate,
            nativeConfig
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

    nonisolated static func variantPinningProfile(
        from url: URL?,
        requestedProfile: TranscodeURLProfile
    ) -> TranscodeURLProfile {
        guard let url else { return requestedProfile }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return requestedProfile
        }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            query[item.name.lowercased()] = value.lowercased()
        }

        let allowVideoCopy = query["allowvideostreamcopy"] == "true"
        let codec = query["videocodec"] ?? ""
        if codec == "h264", !allowVideoCopy {
            return .forceH264Transcode
        }
        if codec == "hevc", !allowVideoCopy {
            return .appleOptimizedHEVC
        }
        if allowVideoCopy {
            return requestedProfile == .conservativeCompatibility ? .conservativeCompatibility : .serverDefault
        }

        return requestedProfile
    }

    nonisolated static func isDegradedStartupVariant(width: Int, bandwidth: Int) -> Bool {
        let isDegradedBandwidth = bandwidth > 0 && bandwidth < 2_000_000
        let isLowResolutionVariant = width > 0 && width < 960
        return isDegradedBandwidth || isLowResolutionVariant
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
        let variantURL = selectedVariantInfo?.resolvedURL.reelfinCacheKey ?? selection.assetURL.reelfinCacheKey
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
                    "playback.hls.variant.candidate — \(self.playbackLogScope(), privacy: .public) url=\(variant.resolvedURL.reelfinCompactLogString, privacy: .public) \(variant.loggingSummary, privacy: .public)"
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
                throw AppError.network(PlaybackFailureReason.strictModeRejectedSDRVariant.localizedDescription)
            }

            if strictQualityIsActive, selection.source.isLikelyHDRorDV, !preferred.usesFMP4Transport {
                throw AppError.network(PlaybackFailureReason.strictModeRequiresFMP4Transport.localizedDescription)
            }

            if strictQualityIsActive, selection.source.isLikelyHDRorDV, preferred.isH264 {
                throw AppError.network(PlaybackFailureReason.strictModeBlockedDestructiveTranscode.localizedDescription)
            }

            selectedVariantInfo = preferred
            var updated = selection
            updated.assetURL = Self.variantURLStrippingResumeQuery(
                masterURL: selection.assetURL,
                variantURL: preferred.resolvedURL
            )
            AppLog.playback.info(
                    "playback.hls.variant.pinned — \(self.playbackLogScope(), privacy: .public) bandwidth=\(preferred.bandwidth, privacy: .public) resolution=\(preferred.width, privacy: .public)x\(preferred.height, privacy: .public) codec=\(preferred.normalizedCodec, privacy: .public) codecs=\(preferred.codecs, privacy: .public) supplemental=\(preferred.supplementalCodecs, privacy: .public) videoRange=\(preferred.videoRange, privacy: .public) allowVideoCopy=\(String(describing: preferred.allowsVideoCopy), privacy: .public)"
            )

            let variantManifest = try await fetchPlaylist(url: updated.assetURL, headers: selection.headers)
            let variantInspection = StreamVariantInspector.inspectVariantPlaylist(
                manifest: variantManifest,
                variantURL: updated.assetURL
            )
            selectedVariantPlaylistInspection = variantInspection
            let transport = StreamVariantInspector.inferTransport(from: preferred, playlist: variantInspection)
            let mapURI = Self.redactedPlaylistURIForLog(variantInspection.mapURI)
            let firstSegmentURI = Self.redactedPlaylistURIForLog(variantInspection.firstSegmentURI)
            AppLog.playback.notice(
                "playback.hls.variant.selected — \(self.playbackLogScope(), privacy: .public) url=\(updated.assetURL.reelfinCompactLogString, privacy: .public) transport=\(transport, privacy: .public) map=\(mapURI, privacy: .public) firstSegment=\(firstSegmentURI, privacy: .public)"
            )

            if strictQualityIsActive, selection.source.isLikelyHDRorDV, transport != "fMP4" {
                throw AppError.network(PlaybackFailureReason.strictModeRequiresFMP4Transport.localizedDescription)
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
                    throw AppError.network(PlaybackFailureReason.strictModeNoHDRCapablePath.localizedDescription)
                }

                if (selection.source.dvProfile ?? 0) > 0, effectiveMode == .hdr10, !(initInspection.hasDvcC || initInspection.hasDvvC) {
                    AppLog.playback.notice(
                        "\(PlaybackFailureReason.missingDolbyVisionBoxesFallingBackToHDR10.localizedDescription, privacy: .public)"
                    )
                }
            } else {
                selectedInitSegmentInspection = nil
                if strictQualityIsActive, selection.source.isLikelyHDRorDV {
                    throw AppError.network(PlaybackFailureReason.strictModeNoHDRCapablePath.localizedDescription)
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
        if !AdaptiveFallbackPolicy.isEnabled, Self.shouldBlockLegacyCoordinatorRecovery(
            isNativePlayerActive: isNativePlayerActive,
            nativeSurface: nativePlayerPlaybackSurface
        ) {
            let message = NativePlayerRouteViolation.serverTranscodeBlockedByConfig.localizedDescription
            AppLog.playback.error(
                "nativeplayer.route.guard.blocked — \(self.playbackLogScope(attempt: attempt), privacy: .public) reason=\(message, privacy: .public) trigger=\(reason, privacy: .public)"
            )
            playbackErrorMessage = message
            return false
        }
        // Compute resume position in movie-absolute time.
        // If we've decoded at least one frame, use current player position + offset.
        // Otherwise, preserve the original start offset (retry from same position).
        let resumeSeconds = recoveryResumeSeconds()
        let resumeTimeTicks: Int64? = resumeSeconds.map { Int64($0 * 10_000_000) }
        guard let itemID = currentItemID else { return false }
        guard isActivePlaybackTarget(itemID: itemID) else { return false }

        if Self.shouldSuspendCurrentItemBeforeProfileRecovery(reason: reason) {
            suspendCurrentItemForProfileRecovery(reason: reason)
        }

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
        let allowDirectRoutes = !Self.shouldDisableDirectRoutesForRecovery(reason: reason)
        let nativeEngineFallbackReason = nativeCoordinatorFallbackReason(forRecoveryReason: reason)

        var lastError: Error?
        for profile in recoveryProfiles(for: reason, attempt: attempt) {
            do {
                var selection = try await coordinator.resolvePlayback(
                    itemID: itemID,
                    mode: mode,
                    allowTranscodingFallbackInPerformance: allowTranscodingFallback,
                    transcodeProfile: profile,
                    startTimeTicks: resumeTimeTicks,
                    allowDirectRoutes: allowDirectRoutes,
                    nativeEngineFallbackReason: nativeEngineFallbackReason
                )
                guard isActivePlaybackTarget(itemID: itemID) else { return false }

                if !allowDirectRoutes {
                    switch selection.decision.route {
                    case .directPlay, .remux, .nativeBridge:
                        AppLog.playback.warning(
                            "playback.fallback.direct_route_skipped — \(self.playbackLogScope(attempt: attempt), privacy: .public) reason=\(reason, privacy: .public) profile=\(profile.rawValue, privacy: .public) route=\(self.routeLabel(for: selection.decision.route), privacy: .public)"
                        )
                        continue
                    case .transcode:
                        break
                    }
                }

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
                        guard isActivePlaybackTarget(itemID: itemID) else { return false }
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
                    ),
                    profileOverride: Self.variantPinningProfile(
                        from: selection.assetURL,
                        requestedProfile: profile
                    )
                )
                guard isActivePlaybackTarget(itemID: itemID) else { return false }
                selection = try await stabilizeInitialSelectionIfNeeded(
                    itemID: itemID,
                    selection: selection,
                    startTimeTicks: resumeTimeTicks,
                    itemPrefersDolbyVision: shouldPreferDolbyVisionVariant(
                        itemPrefersDolbyVision: currentItemHasDolbyVision || (currentSource?.isLikelyHDRorDV ?? false),
                        source: selection.source
                    )
                )
                guard isActivePlaybackTarget(itemID: itemID) else { return false }

                let recoveryGuarantees = resolvedRouteGuarantees(for: selection)
                if blockAutomaticDestructiveFallbackIfNeeded(
                    selection: selection,
                    guarantees: recoveryGuarantees,
                    reason: reason
                ) {
                    continue
                }

                if !registerAttempt(selection: selection, profile: profile) {
                    continue
                }

                if case .transcode = selection.decision.route, !(await preflightSelection(selection)) {
                    AppLog.playback.warning(
                        "Recovery preflight failed for profile=\(profile.rawValue, privacy: .public). Continuing load."
                    )
                }
                guard isActivePlaybackTarget(itemID: itemID) else { return false }

                activeTranscodeProfile = profile
                // Update offset to reflect the new transcode start position.
                if case .directPlay = selection.decision.route {
                    transcodeStartOffset = 0
                } else {
                    transcodeStartOffset = Self.initialTranscodeStartOffset(
                        for: selection,
                        resumeSeconds: resumeSeconds
                    )
                }
                let isDirectPlay: Bool
                if case .directPlay = selection.decision.route { isDirectPlay = true } else { isDirectPlay = false }
                if isDirectPlay {
                    await loadDirectPlaySelectionAtResumePosition(selection, resumeSeconds: resumeSeconds)
                } else {
                    prepareAndLoadSelection(selection, resumeSeconds: resumeSeconds)
                }
                routeDescription = "Recovery #\(attempt): \(routeLabel(for: selection.decision.route)) [\(profile.rawValue)]"
                playbackErrorMessage = nil
                if isDirectPlay {
                    guard await startRecoveredDirectPlayWhenReady(
                        selection: selection,
                        resumeSeconds: resumeSeconds,
                        reason: reason
                    ) else {
                        continue
                    }
                } else {
                    player.play()
                    scheduleDecodedFrameWatchdog()
                    scheduleStartupWatchdog()
                }
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

    private func nativeCoordinatorFallbackReason(forRecoveryReason reason: String) -> String? {
        if Self.shouldAllowNativeModeCoordinatorFallback(
            reason: reason,
            rootReason: nativeModeCoordinatorFallbackRootReason
        ) {
            return reason
        }

        guard Self.shouldAllowAppleNativeCoordinatorFallback(
            reason: reason,
            isNativePlayerActive: isNativePlayerActive,
            nativeSurface: nativePlayerPlaybackSurface
        ) else {
            return nil
        }
        return reason
    }

    private func suspendCurrentItemForProfileRecovery(reason: String) {
        player.pause()
        player.cancelPendingPrerolls()
        tearDownCurrentItemObservers()
        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
        decodedFrameWatchdogTask?.cancel()
        decodedFrameWatchdogTask = nil
        videoOutputPollTask?.cancel()
        videoOutputPollTask = nil
        videoFormatSnapshotTask?.cancel()
        videoFormatSnapshotTask = nil
        startupSubtitleSelectionTask?.cancel()
        startupSubtitleSelectionTask = nil
        videoValidationTask?.cancel()
        videoValidationTask = nil
        videoOutput = nil
        activeStallInterval?.end(name: "playback_stall", message: "recovery")
        activeStallInterval = nil
        player.replaceCurrentItem(with: nil)
        AppLog.playback.notice(
            "playback.fallback.suspended_old_item — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    private func recoveryProfiles(for reason: String, attempt: Int) -> [TranscodeURLProfile] {
        _ = attempt
        if usesDirectRemuxOnly {
            return [.serverDefault]
        }

        let failureReason = StartupFailureReason(rawValue: reason)
        let baseProfiles: [TranscodeURLProfile]

        switch failureReason {
        case .decodedFrameWatchdog, .audioOnlyNoVideo, .readyButNoVideoFrame,
             .decoderStall, .presentationSizeZero, .playerItemFailed:
            // Video decode failure on HEVC: skip to H264 directly when allowed
            if Self.shouldPreferImmediateH264Recovery(
                activeProfile: activeTranscodeProfile,
                allowSDRFallback: allowSDRFallback
            ) {
                baseProfiles = [.forceH264Transcode]
            } else {
                baseProfiles = startupRecoveryProfiles(after: activeTranscodeProfile)
            }
        case .directPlayPreflightInsufficient, .directPlayStall:
            baseProfiles = [.serverDefault]
        case .directPlayPostStartStall:
            baseProfiles = startupRecoveryProfiles(after: activeTranscodeProfile)
        case .startupReadinessTimeout, .startupVideoPrerollTimeout:
            // A startup failure on progressive Direct Play should not reload the
            // same raw file through another copy-friendly profile. Prefer the
            // first profile that forces server-managed HLS/video samples.
            if Self.shouldPreferImmediateH264Recovery(
                activeProfile: activeTranscodeProfile,
                allowSDRFallback: allowSDRFallback
            ) {
                baseProfiles = [.forceH264Transcode]
            } else {
                baseProfiles = startupRecoveryProfiles(after: activeTranscodeProfile)
            }
        default:
            baseProfiles = startupRecoveryProfiles(after: activeTranscodeProfile)
        }

        if let watchable = Self.adaptiveWatchabilityOverride(
            reason: failureReason,
            source: currentSource,
            allowSDRFallback: allowSDRFallback,
            adaptiveEnabled: AdaptiveFallbackPolicy.isEnabled
        ) {
            let profiles = deduplicatedProfiles(watchable)
            AppLog.playback.notice(
                "playback.fallback.profiles — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public) active=\(self.activeTranscodeProfile.rawValue, privacy: .public) candidates=\(profiles.map(\.rawValue).joined(separator: ","), privacy: .public) adaptive=watchable_sdr_drop"
            )
            return profiles
        }

        let qualitySafeProfiles = Self.qualitySafeRecoveryProfiles(baseProfiles, source: currentSource)
        AppLog.playback.notice(
            "playback.fallback.profiles — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public) active=\(self.activeTranscodeProfile.rawValue, privacy: .public) candidates=\(qualitySafeProfiles.map(\.rawValue).joined(separator: ","), privacy: .public)"
        )

        return deduplicatedProfiles(qualitySafeProfiles)
    }

    private func deduplicatedProfiles(_ profiles: [TranscodeURLProfile]) -> [TranscodeURLProfile] {
        var seen = Set<TranscodeURLProfile>()
        return profiles.filter { seen.insert($0).inserted }
    }

    private func startupRecoveryProfiles(after activeProfile: TranscodeURLProfile) -> [TranscodeURLProfile] {
        Self.recoveryPlan(after: activeProfile, policy: playbackPolicy, allowSDRFallback: allowSDRFallback)
    }

    nonisolated static func shouldPreferImmediateH264Recovery(
        activeProfile: TranscodeURLProfile,
        allowSDRFallback: Bool
    ) -> Bool {
        guard allowSDRFallback else { return false }
        switch activeProfile {
        case .serverDefault, .appleOptimizedHEVC:
            // Once startup already failed without producing a decoded frame,
            // a second copy-friendly attempt is usually wasted. Drop straight
            // to H.264, which is the most reliable Apple-native recovery path.
            return true
        case .conservativeCompatibility, .forceH264Transcode:
            return false
        }
    }

    private func refreshDecodedVideoFrameState() {
        guard !hasDecodedVideoFrame else { return }
        guard let item = player.currentItem else { return }

        var copiedPixelBuffer = false
        if let output = videoOutput {
            let itemTime = item.currentTime()
            if output.hasNewPixelBuffer(forItemTime: itemTime) {
                var presentationTime = CMTime.zero
                if let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &presentationTime) {
                    copiedPixelBuffer = true
                    updateHDRModeFromPixelBuffer(pixelBuffer)
                }
            }
        }

        let size = item.presentationSize
        if size.width > 2 && size.height > 2 {
            updatePlaybackProof(from: item)
        }

        guard Self.hasRenderableVideoFrame(
            copiedPixelBuffer: copiedPixelBuffer,
            presentationSize: size,
            videoOutputAttached: videoOutput != nil,
            avkitReadyForDisplay: avkitReadyForDisplay,
            requiresAVKitReadyForDisplay: Self.requiresAVKitReadyForDisplayProof(
                route: lastPreparedSelection?.decision.route,
                source: currentSource ?? lastPreparedSelection?.source,
                isTVOS: Self.isTvOSPlatform
            )
        ) else {
            return
        }

        hasDecodedVideoFrame = true
        updatePlaybackProof(from: item)
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
        let primaries = CVBufferCopyAttachment(
            pixelBuffer,
            kCVImageBufferColorPrimariesKey,
            nil
        ) as? String
        let transfer = CVBufferCopyAttachment(
            pixelBuffer,
            kCVImageBufferTransferFunctionKey,
            nil
        ) as? String

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

    private func updateTVOSAdaptiveCachingIfNeeded(
        item: AVPlayerItem,
        observedBitrate: Double,
        indicatedBitrate: Double
    ) async {
        guard Self.isTvOSPlatform else { return }

        if PlaybackTVOSCachingPolicy.isHealthyAccessLogSample(
            observedBitrate: observedBitrate,
            indicatedBitrate: indicatedBitrate,
            sourceBitrate: currentSource?.bitrate,
            isTVOS: Self.isTvOSPlatform
        ) {
            tvosHealthyAccessLogSamples += 1
        } else {
            tvosHealthyAccessLogSamples = 0
        }

        let runtimeSeconds =
            currentMediaItem?.runtimeTicks.map { Double($0) / 10_000_000 }
            ?? {
                let itemDuration = item.duration.seconds
                guard itemDuration.isFinite, itemDuration > 0 else { return nil }
                return itemDuration + transcodeStartOffset
            }()

        guard let hint = PlaybackTVOSCachingPolicy.adaptiveCachingHint(
            currentBufferDuration: currentForwardBufferDuration,
            observedBitrate: observedBitrate,
            indicatedBitrate: indicatedBitrate,
            sourceBitrate: currentSource?.bitrate,
            currentTime: currentTime,
            playbackElapsedSeconds: playbackElapsedSecondsForCachingRamp(),
            runtimeSeconds: runtimeSeconds,
            healthySampleCount: tvosHealthyAccessLogSamples,
            isTVOS: Self.isTvOSPlatform
        ) else {
            return
        }

        item.preferredForwardBufferDuration = hint.forwardBufferDuration
        currentForwardBufferDuration = hint.forwardBufferDuration
        if let syntheticHLSSession {
            await syntheticHLSSession.promotePrefetch(
                preloadCount: hint.syntheticPreloadCount,
                lookaheadSegments: hint.syntheticLookaheadSegments
            )
        }
        AppLog.playback.info(
            "tvOS caching ramp phase=\(String(describing: hint.phase), privacy: .public) buffer=\(hint.forwardBufferDuration, format: .fixed(precision: 1))s preload=\(hint.syntheticPreloadCount, privacy: .public) lookahead=\(hint.syntheticLookaheadSegments, privacy: .public) headroom=\(hint.headroomRatio, format: .fixed(precision: 2))x"
        )
    }

    private func playbackElapsedSecondsForCachingRamp() -> Double {
        let anchor = firstFrameDate ?? startDate
        return max(0, Date().timeIntervalSince(anchor))
    }

    private func shouldUpgradeInitialTranscodeProfile(_ selection: PlaybackAssetSelection) -> Bool {
        guard case .transcode = selection.decision.route else { return false }
        guard activeTranscodeProfile == .serverDefault else { return false }
        guard !usesDirectRemuxOnly else { return false }
        guard !selection.routeGuarantees.preservesOriginalVideo else { return false }

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
        startTimeTicks: Int64?,
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
            transcodeProfile: saferProfile,
            startTimeTicks: startTimeTicks
        )
        upgraded = try await pinPreferredVariantIfNeeded(
            selection: upgraded,
            itemPrefersDolbyVision: itemPrefersDolbyVision,
            profileOverride: saferProfile
        )
        activeTranscodeProfile = saferProfile
        return upgraded
    }

    private func preemptHighRiskProgressiveDirectPlayIfNeeded(
        itemID: String,
        selection: PlaybackAssetSelection,
        startTimeTicks: Int64?,
        maxStreamingBitrate: Int,
        itemPrefersDolbyVision: Bool
    ) async throws -> PlaybackAssetSelection {
        guard Self.shouldPreemptivelyUseStableHLSForHighRiskDirectPlay(
            route: selection.decision.route,
            source: selection.source,
            playbackPolicy: playbackPolicy,
            allowSDRFallback: allowSDRFallback,
            usesDirectRemuxOnly: usesDirectRemuxOnly,
            maxStreamingBitrate: maxStreamingBitrate,
            isTVOS: Self.isTvOSPlatform
        ) else {
            return selection
        }

        let reason = Self.isTvOSPlatform
            ? "tvos_high_bitrate_progressive_over_budget"
            : "ios_high_risk_progressive_directplay"
        AppLog.playback.notice(
            "playback.directplay.preemptive_fallback — \(self.playbackLogScope(), privacy: .public) reason=\(reason, privacy: .public) sourceBitrate=\(selection.source.bitrate ?? 0, privacy: .public) maxStreamingBitrate=\(maxStreamingBitrate, privacy: .public)"
        )
        await warmupManager?.cancel(itemID: itemID)

        var upgraded = try await coordinator.resolvePlayback(
            itemID: itemID,
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .forceH264Transcode,
            startTimeTicks: startTimeTicks,
            allowDirectRoutes: false,
            nativeEngineFallbackReason: reason
        )
        upgraded = try await pinPreferredVariantIfNeeded(
            selection: upgraded,
            itemPrefersDolbyVision: itemPrefersDolbyVision,
            profileOverride: .forceH264Transcode
        )
        upgraded = try await stabilizeInitialSelectionIfNeeded(
            itemID: itemID,
            selection: upgraded,
            startTimeTicks: startTimeTicks,
            itemPrefersDolbyVision: itemPrefersDolbyVision
        )
        activeTranscodeProfile = inferredActiveProfile(for: upgraded, fallback: .forceH264Transcode)
        return upgraded
    }

    private func stabilizeInitialSelectionIfNeeded(
        itemID: String,
        selection: PlaybackAssetSelection,
        startTimeTicks: Int64?,
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
            transcodeProfile: .forceH264Transcode,
            startTimeTicks: startTimeTicks
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

    private func isCurrentStallResistantDirectPlay() -> Bool {
        guard Self.isTvOSPlatform else { return false }
        guard let selection = lastPreparedSelection else { return false }
        return Self.shouldUseStallResistantDirectPlay(
            route: selection.decision.route,
            source: currentSource ?? selection.source
        )
    }

    private func applyDeferredResumeSeekIfNeeded() {
        guard let seconds = pendingResumeSeconds, seconds > 0 else { return }

        let current = player.currentTime().seconds
        let currentDuration = player.currentItem?.duration.seconds
        let runtimeSeconds = currentMediaItem?.runtimeTicks.map { Double($0) / 10_000_000 }

        if transcodeStartOffset <= 0,
           Self.isServerOffsetEligibleRoute(lastPreparedSelection?.decision.route),
           PlaybackResumeSeekPlanner.streamLooksServerOffset(
               pendingResumeSeconds: seconds,
               currentPlayerTime: current,
               currentItemDuration: currentDuration,
               currentMediaRuntimeSeconds: runtimeSeconds
           ) {
            transcodeStartOffset = seconds
            playbackTimeOffsetSeconds = seconds
            currentTime = max(0, current) + seconds
            if let currentDuration, currentDuration.isFinite, currentDuration > 0 {
                duration = max(currentTime, currentDuration + seconds)
            }
            pendingResumeSeconds = nil
            AppLog.playback.info(
                "playback.transcode.resume_offset.detected — \(self.playbackLogScope(), privacy: .public) offset=\(seconds, format: .fixed(precision: 3))"
            )
            return
        }

        guard PlaybackResumeSeekPlanner.shouldApplySeek(
            pendingResumeSeconds: seconds,
            currentPlayerTime: current,
            currentItemDuration: currentDuration,
            currentMediaRuntimeSeconds: runtimeSeconds,
            transcodeStartOffset: transcodeStartOffset
        ) else {
            pendingResumeSeconds = nil
            return
        }

        pendingResumeSeconds = nil

        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
        recordRequestedPlaybackPosition(seconds)
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
        Self.variantPinningProfile(from: url, requestedProfile: fallback)
    }

    private func inferredActiveProfile(
        for selection: PlaybackAssetSelection,
        fallback: TranscodeURLProfile
    ) -> TranscodeURLProfile {
        if case .directPlay = selection.decision.route {
            return .serverDefault
        }
        return inferredTranscodeProfile(from: selection.assetURL, fallback: fallback)
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
        guard progressPersistenceEnabled else { return }
        guard let snapshot = makeProgressSnapshot(isPaused: isPaused, didFinish: didFinish) else { return }
        await persistProgress(snapshot: snapshot)
    }

    private func recordObservedPlaybackPosition(_ seconds: Double) {
        guard seconds.isFinite else { return }
        let sanitized = max(0, seconds)
        lastKnownPlaybackPositionSeconds = sanitized
        if let pending = pendingPlaybackPositionOverrideSeconds,
           Self.isResumePositionSatisfied(
               currentTime: sanitized,
               resumeSeconds: pending
           ) || sanitized > pending {
            pendingPlaybackPositionOverrideSeconds = nil
        }
    }

    private func recordRequestedPlaybackPosition(_ seconds: Double) {
        guard seconds.isFinite else { return }
        let sanitized = max(0, seconds)
        pendingPlaybackPositionOverrideSeconds = sanitized
        lastKnownPlaybackPositionSeconds = sanitized
    }

    private func makeProgressSnapshot(
        isPaused: Bool,
        didFinish: Bool
    ) -> (local: PlaybackProgress, remote: PlaybackProgressUpdate)? {
        guard let itemID = currentItemID else { return nil }

        let playerPositionSeconds = player.currentTime().seconds
        let playerAbsoluteSeconds = playerPositionSeconds.isFinite
            ? max(0, playerPositionSeconds) + transcodeStartOffset
            : nil
        let observedSeconds = currentTime.isFinite ? max(0, currentTime) : nil
        let positionSeconds = Self.resolvedProgressPositionSeconds(
            pendingPlaybackPositionOverrideSeconds: pendingPlaybackPositionOverrideSeconds,
            playerAbsoluteSeconds: playerAbsoluteSeconds,
            observedSeconds: observedSeconds,
            lastKnownPlaybackPositionSeconds: lastKnownPlaybackPositionSeconds,
            pendingResumeSeconds: pendingResumeSeconds,
            sessionInitialResumeSeconds: sessionInitialResumeSeconds
        )
        let itemDurationSeconds = player.currentItem?.duration.seconds ?? 0
        let observedDurationSeconds = duration.isFinite ? max(0, duration) : 0
        let streamDurationSeconds = itemDurationSeconds + transcodeStartOffset
        let totalSeconds = max(positionSeconds, max(streamDurationSeconds, observedDurationSeconds))
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

    nonisolated static func resolvedProgressPositionSeconds(
        pendingPlaybackPositionOverrideSeconds: Double?,
        playerAbsoluteSeconds: Double?,
        observedSeconds: Double?,
        lastKnownPlaybackPositionSeconds: Double?,
        pendingResumeSeconds: Double?,
        sessionInitialResumeSeconds: Double
    ) -> Double {
        func nonNegative(_ value: Double?) -> Double? {
            guard let value, value.isFinite else { return nil }
            return max(0, value)
        }

        let pendingOverride = nonNegative(pendingPlaybackPositionOverrideSeconds)
        let positivePlayer = nonNegative(playerAbsoluteSeconds).flatMap { $0 > 1 ? $0 : nil }
        let positiveObserved = nonNegative(observedSeconds).flatMap { $0 > 0 ? $0 : nil }
        let lastKnown = nonNegative(lastKnownPlaybackPositionSeconds)
        let pendingResume = nonNegative(pendingResumeSeconds).flatMap { $0 > 0 ? $0 : nil }
        let initialResume = nonNegative(sessionInitialResumeSeconds).flatMap { $0 > 0 ? $0 : nil }

        if let pendingOverride {
            return pendingOverride
        }
        if let pendingResume {
            return max(pendingResume, positivePlayer ?? 0, positiveObserved ?? 0, lastKnown ?? 0)
        }
        if let positivePlayer {
            return positivePlayer
        }
        if let positiveObserved {
            return positiveObserved
        }
        if let lastKnown {
            return lastKnown
        }
        if let initialResume {
            return initialResume
        }
        return 0
    }

    private func persistProgress(
        snapshot: (local: PlaybackProgress, remote: PlaybackProgressUpdate)
    ) async {
        try? await repository.savePlaybackProgress(snapshot.local)
        enqueueRemoteProgressReport(snapshot.remote)
    }

    private func enqueueRemoteProgressReport(_ progress: PlaybackProgressUpdate) {
        pendingRemoteProgressUpdate = progress
        startRemoteProgressReportTaskIfNeeded()
    }

    private func startRemoteProgressReportTaskIfNeeded() {
        guard remoteProgressReportTask == nil else { return }

        remoteProgressReportTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                if self.isRecoveryInProgress {
                    await Self.sleepForRemoteProgress(seconds: Self.remoteProgressRecoveryPollInterval)
                    continue
                }

                guard let progress = self.pendingRemoteProgressUpdate else {
                    self.remoteProgressReportTask = nil
                    return
                }

                if let lastReport = self.lastRemoteProgressReportDate {
                    let remaining = Self.remoteProgressMinimumInterval - Date().timeIntervalSince(lastReport)
                    if remaining > 0 {
                        await Self.sleepForRemoteProgress(seconds: remaining)
                        continue
                    }
                }

                self.pendingRemoteProgressUpdate = nil
                self.lastRemoteProgressReportDate = Date()
                let apiClient = self.apiClient
                await Self.reportRemotePlaybackProgress(progress, apiClient: apiClient)
            }

            self?.remoteProgressReportTask = nil
        }
    }

    private nonisolated static func sleepForRemoteProgress(seconds: TimeInterval) async {
        let nanoseconds = UInt64(max(0.1, seconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private nonisolated static func reportRemotePlaybackProgress(
        _ progress: PlaybackProgressUpdate,
        apiClient: any JellyfinAPIClientProtocol & Sendable
    ) async {
        try? await apiClient.reportPlayback(progress: progress)
    }

    private nonisolated static func persistProgress(
        snapshot: (local: PlaybackProgress, remote: PlaybackProgressUpdate),
        repository: MetadataRepositoryProtocol,
        apiClient: any JellyfinAPIClientProtocol & Sendable,
        sendStopped: Bool
    ) async {
        // Save locally regardless of whether the item is in media_items
        // (playback_progress has no FK since migration v2_playback_progress_no_fk)
        try? await repository.savePlaybackProgress(snapshot.local)
        await reportRemotePlaybackProgress(snapshot.remote, apiClient: apiClient)
        if sendStopped {
            try? await apiClient.reportPlaybackStopped(progress: snapshot.remote)
        }
    }

    func finishCurrentPlayback() async {
        pause()
        guard progressPersistenceEnabled else { return }
        if let snapshot = makeProgressSnapshot(isPaused: true, didFinish: true) {
            await Self.persistProgress(
                snapshot: snapshot,
                repository: repository,
                apiClient: apiClient,
                sendStopped: true
            )
        }
        if let currentItemID {
            try? await apiClient.reportPlayed(itemID: currentItemID)
        }
        if let currentMediaItem, currentMediaItem.mediaType == .episode {
            await episodeReleaseTracker?.markSeriesFollowed(from: currentMediaItem)
        }
    }

    private func tearDownCurrentItemObservers() {
        startupSubtitleSelectionTask?.cancel()
        startupSubtitleSelectionTask = nil
        videoValidationTask?.cancel()
        videoValidationTask = nil
        directPlayPostStartRebufferTask?.cancel()
        directPlayPostStartRebufferTask = nil
        directPlayStallEscalationTask?.cancel()
        directPlayStallEscalationTask = nil

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
        timeControlObserver = nil
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
            return canUseH264Fallback ? [.conservativeCompatibility, .appleOptimizedHEVC, .forceH264Transcode] : [.conservativeCompatibility]
        case .appleOptimizedHEVC:
            #if os(tvOS)
            // On tvOS, if appleOptimizedHEVC (HEVC re-encode) failed, the source
            // likely has DV/HDR packaging that AVPlayer can't handle as HEVC at all.
            // Skip conservativeCompatibility (stream-copy would also fail) and go
            // straight to H264 for reliable decode.
            return canUseH264Fallback ? [.forceH264Transcode] : []
            #else
            // Try conservative (stream-copy) before dropping all the way to H264
            return canUseH264Fallback ? [.conservativeCompatibility, .forceH264Transcode] : [.conservativeCompatibility]
            #endif
        case .conservativeCompatibility:
            return canUseH264Fallback ? [.forceH264Transcode] : []
        case .forceH264Transcode:
            return []
        }
    }

    nonisolated static func qualitySafeRecoveryProfiles(
        _ profiles: [TranscodeURLProfile],
        source: MediaSource?
    ) -> [TranscodeURLProfile] {
        guard let source, source.isLikely4K, source.isLikelyHDRorDV else { return profiles }
        return profiles.filter { $0 == .serverDefault || $0 == .conservativeCompatibility }
    }

    /// Reasons whose adaptive never-freeze drop must produce a WATCHABLE picture: the direct-play
    /// stall paths AND the pre-start preflight (the preheat showed the connection can't sustain the
    /// source bitrate, so start straight on watchable SDR instead of starting DV that will stall).
    nonisolated static func isAdaptiveWatchabilityStall(_ reason: StartupFailureReason?) -> Bool {
        switch reason {
        case .directPlayStall, .directPlayPostStartStall, .directPlayPreflightInsufficient:
            return true
        default:
            return false
        }
    }

    /// When a Dolby Vision / HDR direct-play stall forces the adaptive never-freeze drop, the drop
    /// MUST be watchable. The default quality-preservation path (`qualitySafeRecoveryProfiles`)
    /// restricts a 4K DV source to `conservativeCompatibility` — an HEVC stream-copy that keeps the
    /// HDR10/PQ base layer but drops the Dolby Vision dynamic metadata, so the picture renders far
    /// too dark (device-confirmed "très très sombre"; direct DV keeps the metadata and looks fine).
    /// `forceH264Transcode` makes the server tone-map HDR→SDR (BT.709) at normal brightness instead.
    /// The user accepted the temporary quality drop (never freeze, then back to DV when bandwidth
    /// recovers); a watchable SDR image beats an unwatchable dark HDR10 one. Returns `nil` when the
    /// override does not apply (normal quality-safe selection is used). Direct DV itself is never
    /// touched — this only changes the stall-drop target.
    nonisolated static func adaptiveWatchabilityOverride(
        reason: StartupFailureReason?,
        source: MediaSource?,
        allowSDRFallback: Bool,
        adaptiveEnabled: Bool
    ) -> [TranscodeURLProfile]? {
        guard adaptiveEnabled, allowSDRFallback else { return nil }
        guard isAdaptiveWatchabilityStall(reason) else { return nil }
        guard source?.isLikelyHDRorDV == true else { return nil }
        return [.forceH264Transcode]
    }

    nonisolated static func shouldBlockAutomaticDestructiveFallback(
        source: MediaSource,
        guarantees: PlaybackRouteGuarantees
    ) -> Bool {
        guard source.isLikely4K, source.isLikelyHDRorDV else { return false }
        if !guarantees.preservesOriginalVideo { return true }
        return guarantees.hdrIntegrity == .sdrToneMapped || !guarantees.preservesHDR
    }

    nonisolated static func hasStartupRecoveryCandidate(
        after activeProfile: TranscodeURLProfile,
        playbackPolicy: PlaybackPolicy,
        allowSDRFallback: Bool,
        usesDirectRemuxOnly: Bool
    ) -> Bool {
        if usesDirectRemuxOnly {
            return true
        }

        return !recoveryPlan(
            after: activeProfile,
            policy: playbackPolicy,
            allowSDRFallback: allowSDRFallback
        ).isEmpty
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
        // for Dolby Vision titles. Ask the server for its best copy/remux path.
        if itemHasDolbyVision, stored == .forceH264Transcode {
            return .serverDefault
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
            updated.selectedVariantURL = variant.resolvedURL.reelfinLogString
            updated.selectedVideoRange = variant.videoRange
            updated.selectedSupplementalCodecs = variant.supplementalCodecs
        }
        updated.selectedMasterPlaylistURL = selectedMasterPlaylistURL?.reelfinLogString
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

        if let snapshot = cachedVideoFormatSnapshot {
            if !snapshot.codecFourCC.isEmpty {
                updated.codecFourCC = snapshot.codecFourCC
            }
            updated.bitDepth = snapshot.bitDepth ?? updated.bitDepth ?? debugInfo?.videoBitDepth
            updated.hdrTransfer = snapshot.hdrTransfer
            updated.dolbyVisionActive = snapshot.dolbyVisionActive
        } else if updated.bitDepth == nil {
            updated.bitDepth = debugInfo?.videoBitDepth
        }

        if updated != playbackProof {
            playbackProof = updated
            PlayerDeepEvidenceSink.append(
                "playback.proof — \(playbackLogScope()) resolution=\(updated.decodedResolution) codec=\(updated.codecFourCC) bitDepth=\(updated.bitDepth ?? 0) hdr=\(updated.hdrTransfer) dv=\(updated.dolbyVisionActive) method=\(updated.playbackMethod) profile=\(updated.transcodeProfile ?? "n/a") srcBitrate=\(updated.sourceBitrate ?? 0) container=\(updated.sourceContainer ?? "n/a") dvProfile=\(updated.dvProfile ?? 0) dvLevel=\(updated.dvLevel ?? 0) videoRange=\(updated.videoRangeType ?? "n/a") observedBitrate=\(updated.observedBitrate ?? 0)"
            )
            AppLog.playback.info(
                "playback.proof — \(self.playbackLogScope(), privacy: .public) resolution=\(updated.decodedResolution, privacy: .public) codec=\(updated.codecFourCC, privacy: .public) bitDepth=\(updated.bitDepth ?? 0, privacy: .public) hdr=\(updated.hdrTransfer, privacy: .public) dv=\(updated.dolbyVisionActive, privacy: .public) method=\(updated.playbackMethod, privacy: .public) profile=\(updated.transcodeProfile ?? "n/a", privacy: .public) srcBitrate=\(updated.sourceBitrate ?? 0, privacy: .public) container=\(updated.sourceContainer ?? "n/a", privacy: .public) dvProfile=\(updated.dvProfile ?? 0, privacy: .public) dvLevel=\(updated.dvLevel ?? 0, privacy: .public) videoRange=\(updated.videoRangeType ?? "n/a", privacy: .public) observedBitrate=\(updated.observedBitrate ?? 0, privacy: .public)"
            )
        }
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

    static func videoFormatSnapshot(
        from format: CMFormatDescription,
        fallbackBitDepth: Int?
    ) -> VideoFormatSnapshot {
        let subtype = Self.fourCCString(from: CMFormatDescriptionGetMediaSubType(format))
        let extensions = CMFormatDescriptionGetExtensions(format) as? [CFString: Any] ?? [:]
        return videoFormatSnapshot(
            codecFourCC: subtype,
            extensions: extensions,
            fallbackBitDepth: fallbackBitDepth
        )
    }

    static func videoFormatSnapshot(
        codecFourCC: String,
        extensions: [CFString: Any],
        fallbackBitDepth: Int?
    ) -> VideoFormatSnapshot {
        let normalizedCodec = codecFourCC.lowercased()
        let bitDepth = (extensions[kCMFormatDescriptionExtension_Depth] as? NSNumber)?.intValue ?? fallbackBitDepth
        let transfer = (extensions[kCMFormatDescriptionExtension_TransferFunction] as? String)?.lowercased() ?? ""
        let primaries = (extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String)?.lowercased() ?? ""
        let extDescription = String(describing: extensions).lowercased()

        let dolbyVisionActive = normalizedCodec == "dvh1"
            || normalizedCodec == "dvhe"
            || extDescription.contains("dolby")
            || extDescription.contains("vision")
        let hdrMode: HDRPlaybackMode
        if dolbyVisionActive {
            hdrMode = .dolbyVision
        } else if transfer.contains("pq") || transfer.contains("hlg") || primaries.contains("2020") {
            hdrMode = .hdr10
        } else {
            hdrMode = .unknown
        }

        let hdrTransfer: String
        if transfer.contains("pq") {
            hdrTransfer = "PQ"
        } else if transfer.contains("hlg") {
            hdrTransfer = "HLG"
        } else if primaries.contains("2020") || hdrMode == .dolbyVision || hdrMode == .hdr10 {
            hdrTransfer = "PQ"
        } else {
            hdrTransfer = "SDR"
        }

        return VideoFormatSnapshot(
            codecFourCC: normalizedCodec,
            bitDepth: bitDepth,
            hdrTransfer: hdrTransfer,
            dolbyVisionActive: dolbyVisionActive,
            hdrMode: hdrMode
        )
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

    nonisolated private static func fourCCString(from value: FourCharCode) -> String {
        let n = Int(value.bigEndian)
        let bytes = [
            UInt8((n >> 24) & 0xff),
            UInt8((n >> 16) & 0xff),
            UInt8((n >> 8) & 0xff),
            UInt8(n & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii)?.lowercased() ?? ""
    }

    nonisolated static func startupSubtitleLoadAction(
        autoSelectedTrackID: String?,
        isEmbedded: Bool
    ) -> StartupSubtitleLoadAction {
        guard let trackID = autoSelectedTrackID else { return .none }
        return isEmbedded ? .applyEmbedded(trackID) : .skipExternal(trackID)
    }

    nonisolated static func shouldAttachVideoOutputProbe(
        route: PlaybackRoute,
        source: MediaSource?,
        isTVOS: Bool
    ) -> Bool {
        guard isTVOS else { return true }
        guard isProgressiveDirectPlay(route) else { return true }
        guard source?.isLikelyHDRorDV == true else { return true }
        return false
    }

    nonisolated static func shouldAutoSelectDefaultSubtitleAtStartup(
        track: MediaTrack,
        route: PlaybackRoute?,
        source: MediaSource?,
        isTVOS: Bool
    ) -> Bool {
        guard !isForcedSubtitle(track) else { return true }
        guard isTVOS, let route else { return true }
        guard isProgressiveDirectPlay(route) else { return true }
        guard source?.isLikelyHDRorDV == true else { return true }
        return false
    }

    nonisolated private static func isForcedSubtitle(_ track: MediaTrack) -> Bool {
        let title = track.title.lowercased()
        return track.isForced || title.contains("forced") || title.contains("forcé")
    }

    nonisolated private static func isProgressiveDirectPlay(_ route: PlaybackRoute) -> Bool {
        guard case let .directPlay(url) = route else { return false }
        return url.pathExtension.lowercased() != "m3u8"
    }

    nonisolated static func isAppleNativePlaybackPath(
        playMethod: String,
        assetURL: URL
    ) -> Bool {
        let method = playMethod.lowercased()
        if method == "directplay" || method == "nativebridge" {
            return true
        }
        return assetURL.pathExtension.lowercased() == "m3u8"
    }

    nonisolated static func avURLAssetOptions(
        for selection: PlaybackAssetSelection,
        allowsCellularAccess: Bool = true
    ) -> [String: Any] {
        var options: [String: Any] = [:]
#if os(iOS)
        if allowsCellularAccess {
            options[AVURLAssetAllowsCellularAccessKey] = true
        }
#endif
        if let mimeType = directPlayAssetOverrideMIMEType(
            route: selection.decision.route,
            source: selection.source,
            assetURL: selection.assetURL
        ) {
            options[AVURLAssetOverrideMIMETypeKey] = mimeType
        }
        return options
    }

    nonisolated static func shouldDeferInitialDirectPlayResumeSeek(
        route: PlaybackRoute,
        resumeSeconds: Double?
    ) -> Bool {
        guard let resumeSeconds, resumeSeconds > 0 else { return false }
        guard case .directPlay = route else { return false }
        return true
    }

    nonisolated static func shouldAutoplayStartupGateOwnDirectPlayResumeSeek(
        route: PlaybackRoute,
        autoPlay: Bool,
        resumeSeconds: Double?
    ) -> Bool {
        guard autoPlay else { return false }
        guard let resumeSeconds, resumeSeconds > 0 else { return false }
        guard case .directPlay = route else { return false }
        return true
    }

    nonisolated static func shouldApplyPendingDirectPlayResumeSeekOnReady(
        route: PlaybackRoute?,
        pendingResumeSeconds: Double?,
        currentTime: Double,
        itemStatus: AVPlayerItem.Status,
        transcodeStartOffset: Double,
        directPlayAutoplayStartupGateActive: Bool = false
    ) -> Bool {
        guard !directPlayAutoplayStartupGateActive else { return false }
        guard itemStatus == .readyToPlay else { return false }
        guard case .directPlay = route else { return false }
        guard transcodeStartOffset <= 0 else { return false }
        guard let pendingResumeSeconds, pendingResumeSeconds > 0 else { return false }
        return !isResumePositionSatisfied(
            currentTime: currentTime,
            resumeSeconds: pendingResumeSeconds
        )
    }

    nonisolated private static func directPlayAssetOverrideMIMEType(
        route: PlaybackRoute,
        source: MediaSource,
        assetURL: URL
    ) -> String? {
        guard case .directPlay = route else { return nil }
        let assetExtension = assetURL.pathExtension.lowercased()
        guard assetExtension.isEmpty else { return nil }

        if let filePath = source.filePath {
            let fileExtension = URL(fileURLWithPath: filePath).pathExtension.lowercased()
            if let mimeType = directPlayMIMEType(forExtension: fileExtension) {
                return mimeType
            }
        }

        let containerTokens = (source.container ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if containerTokens.contains("mp4") || containerTokens.contains("m4v") {
            return "video/mp4"
        }
        if containerTokens.contains("mov") || containerTokens.contains("qt") {
            return "video/quicktime"
        }
        return nil
    }

    nonisolated private static func directPlayMIMEType(forExtension pathExtension: String) -> String? {
        switch pathExtension {
        case "mp4", "m4v":
            return "video/mp4"
        case "mov", "qt":
            return "video/quicktime"
        default:
            return nil
        }
    }

    nonisolated static func directPlayStabilityPolicy(
        route: PlaybackRoute,
        source: MediaSource?,
        defaultForwardBufferDuration: Double,
        defaultWaitsToMinimizeStalling: Bool,
        maxStreamingBitrate: Int? = nil,
        isTVOS: Bool
    ) -> DirectPlayStabilityPolicy {
        guard isTVOS else {
            guard shouldUseIPhoneNoStallDirectPlayGuard(route: route, source: source) else {
                return DirectPlayStabilityPolicy(
                    forwardBufferDuration: defaultForwardBufferDuration,
                    waitsToMinimizeStalling: defaultWaitsToMinimizeStalling,
                    reason: nil
                )
            }
            let guardedDecision = DirectPlayStartupPolicy.guardedDecision(isTVOS: false)
            return DirectPlayStabilityPolicy(
                forwardBufferDuration: max(defaultForwardBufferDuration, guardedDecision.preferredBufferDuration),
                waitsToMinimizeStalling: true,
                reason: "ios_guarded_directplay_startup"
            )
        }

        if shouldUseFastDirectPlayStartup(
            route: route,
            source: source,
            maxStreamingBitrate: maxStreamingBitrate ?? 0,
            isTVOS: isTVOS
        ) {
            return DirectPlayStabilityPolicy(
                forwardBufferDuration: defaultForwardBufferDuration,
                waitsToMinimizeStalling: defaultWaitsToMinimizeStalling,
                reason: nil
            )
        }

        guard shouldUseStallResistantDirectPlay(route: route, source: source) else {
            return DirectPlayStabilityPolicy(
                forwardBufferDuration: defaultForwardBufferDuration,
                waitsToMinimizeStalling: defaultWaitsToMinimizeStalling,
                reason: nil
            )
        }

        return DirectPlayStabilityPolicy(
            forwardBufferDuration: max(defaultForwardBufferDuration, 4),
            waitsToMinimizeStalling: true,
            reason: "tvos_guarded_directplay_startup"
        )
    }

    nonisolated static func measuredHeadroomDirectPlayStartupPolicy(
        startupClass: PlaybackStartupClass
    ) -> DirectPlayStabilityPolicy {
        let startupPolicy = PlaybackStartupPolicy.configuration(for: startupClass)
        return DirectPlayStabilityPolicy(
            forwardBufferDuration: startupPolicy.preferredForwardBufferDuration,
            waitsToMinimizeStalling: startupPolicy.automaticallyWaitsToMinimizeStalling,
            reason: "directplay_measured_headroom_fast_start"
        )
    }

    private nonisolated static func shouldUseIPhoneNoStallDirectPlayGuard(
        route: PlaybackRoute,
        source: MediaSource?
    ) -> Bool {
        DirectPlaySessionPolicy.isIPhoneNoStallGuardedDirectPlay(route: route, source: source)
    }

    nonisolated static func hasRenderableVideoFrame(
        copiedPixelBuffer: Bool,
        presentationSize: CGSize,
        videoOutputAttached: Bool,
        avkitReadyForDisplay: Bool,
        requiresAVKitReadyForDisplay: Bool
    ) -> Bool {
        if avkitReadyForDisplay { return true }
        if requiresAVKitReadyForDisplay { return false }
        if copiedPixelBuffer { return true }
        guard !videoOutputAttached else { return false }
        return presentationSize.width > 2 && presentationSize.height > 2
    }

    nonisolated static func shouldAcceptAVKitReadyForDisplay(itemStatus: AVPlayerItem.Status) -> Bool {
        itemStatus == .readyToPlay
    }

    nonisolated static func shouldIgnorePlayRequestAfterUnsafeDirectPlayStartup(
        startupPlaybackBlocked: Bool,
        route: PlaybackRoute?
    ) -> Bool {
        guard startupPlaybackBlocked else { return false }
        guard let route else { return true }
        if case .directPlay = route {
            return true
        }
        return false
    }

    nonisolated static func requiresAVKitReadyForDisplayProof(
        route: PlaybackRoute?,
        source: MediaSource?,
        isTVOS: Bool
    ) -> Bool {
        guard let route else { return false }
        guard isProgressiveDirectPlay(route) else { return false }
        guard source?.isLikelyHDRorDV == true else { return false }
        if isTVOS {
            return !shouldAttachVideoOutputProbe(route: route, source: source, isTVOS: true)
        }
        return true
    }

    nonisolated static func decodedFrameWatchdogPlaybackHasStarted(
        playerSeconds: Double,
        absolutePlaybackSeconds: Double,
        transcodeStartOffset: Double
    ) -> Bool {
        let relativePlayerSeconds = playerSeconds.isFinite ? max(0, playerSeconds) : 0
        if transcodeStartOffset > 0 {
            return relativePlayerSeconds >= 0.8
        }

        let absoluteSeconds = absolutePlaybackSeconds.isFinite ? max(0, absolutePlaybackSeconds) : 0
        return max(relativePlayerSeconds, absoluteSeconds) >= 0.8
    }

    nonisolated static func shouldPrerollVideoBeforeAudioStart(
        route: PlaybackRoute,
        source: MediaSource?,
        isTVOS: Bool
    ) -> Bool {
        if isTVOS {
            return false
        }
        return shouldUseIPhoneNoStallDirectPlayGuard(route: route, source: source)
    }

    nonisolated static func shouldPrerollDuringStartupReadinessGate(
        route: PlaybackRoute,
        source: MediaSource?,
        requirement: PlaybackStartupReadinessPolicy.Requirement,
        isTVOS: Bool
    ) -> Bool {
        guard !isTVOS else { return false }
        guard !requirement.allowsTimeoutStart else { return false }
        return shouldUseIPhoneNoStallDirectPlayGuard(route: route, source: source)
    }

    nonisolated static func shouldReleasePausedStartupAfterFirstFrame(
        route: PlaybackRoute,
        source: MediaSource?,
        resumeSeconds: Double?,
        preheatResult: PlaybackStartupPreheater.Result?,
        serverBaselineResult: PlaybackServerNetworkBaseline.Result?,
        isTVOS: Bool
    ) -> Bool {
        DirectPlaySessionPolicy.shouldReleasePausedStartupAfterFirstFrame(
            route: route,
            source: source,
            resumeSeconds: resumeSeconds,
            preheatResult: preheatResult,
            serverBaselineResult: serverBaselineResult,
            isTVOS: isTVOS
        )
    }

    nonisolated static func shouldReleaseSparseResumedDirectPlayStartup(
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
        DirectPlaySessionPolicy.shouldReleaseSparseResumedDirectPlayStartup(
            route: route,
            source: source,
            resumeSeconds: resumeSeconds,
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            currentTime: currentTime,
            itemStatus: itemStatus,
            transcodeStartOffset: transcodeStartOffset,
            likelyToKeepUp: likelyToKeepUp,
            bufferedDuration: bufferedDuration,
            bufferStableDuration: bufferStableDuration,
            preheatResult: preheatResult,
            accessObservedBitrate: accessObservedBitrate,
            accessStallCount: accessStallCount,
            selectedAudioTrackID: selectedAudioTrackID,
            isTVOS: isTVOS
        )
    }

    nonisolated static func shouldReleaseLocalGatewayResumedDirectPlayStartup(
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
        DirectPlaySessionPolicy.shouldReleaseLocalGatewayResumedDirectPlayStartup(
            route: route,
            source: source,
            resumeSeconds: resumeSeconds,
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            currentTime: currentTime,
            itemStatus: itemStatus,
            transcodeStartOffset: transcodeStartOffset,
            preheatResult: preheatResult,
            likelyToKeepUp: likelyToKeepUp,
            bufferedDuration: bufferedDuration,
            bufferStableDuration: bufferStableDuration,
            accessObservedBitrate: accessObservedBitrate,
            accessStallCount: accessStallCount,
            selectedAudioTrackID: selectedAudioTrackID,
            gatewayDiagnostics: gatewayDiagnostics,
            requirement: requirement,
            isTVOS: isTVOS
        )
    }

    nonisolated static func shouldPrimeLocalGatewayResumedDirectPlayStartup(
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
        DirectPlaySessionPolicy.shouldPrimeLocalGatewayResumedDirectPlayStartup(
            route: route,
            source: source,
            resumeSeconds: resumeSeconds,
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            currentTime: currentTime,
            itemStatus: itemStatus,
            transcodeStartOffset: transcodeStartOffset,
            preheatResult: preheatResult,
            bufferedDuration: bufferedDuration,
            accessStallCount: accessStallCount,
            selectedAudioTrackID: selectedAudioTrackID,
            gatewayDiagnostics: gatewayDiagnostics,
            requirement: requirement,
            isTVOS: isTVOS
        )
    }

    nonisolated static func shouldReleasePrimedLocalGatewayResumedDirectPlayStartup(
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
        DirectPlaySessionPolicy.shouldReleasePrimedLocalGatewayResumedDirectPlayStartup(
            route: route,
            source: source,
            resumeSeconds: resumeSeconds,
            primingStartTime: primingStartTime,
            hasMarkedFirstFrame: hasMarkedFirstFrame,
            currentTime: currentTime,
            itemStatus: itemStatus,
            transcodeStartOffset: transcodeStartOffset,
            preheatResult: preheatResult,
            likelyToKeepUp: likelyToKeepUp,
            bufferedDuration: bufferedDuration,
            accessObservedBitrate: accessObservedBitrate,
            accessStallCount: accessStallCount,
            selectedAudioTrackID: selectedAudioTrackID,
            gatewayDiagnostics: gatewayDiagnostics,
            requirement: requirement,
            isTVOS: isTVOS
        )
    }

    nonisolated static func shouldPauseLocalGatewayPrimingPlayback(
        route: PlaybackRoute,
        source: MediaSource?,
        primingStartTime: Double,
        currentTime: Double,
        bufferedDuration: Double,
        gatewayDiagnostics: LocalMediaGatewayDiagnostics? = nil,
        isTVOS: Bool
    ) -> Bool {
        DirectPlaySessionPolicy.shouldPauseLocalGatewayPrimingPlayback(
            route: route,
            source: source,
            primingStartTime: primingStartTime,
            currentTime: currentTime,
            bufferedDuration: bufferedDuration,
            gatewayDiagnostics: gatewayDiagnostics,
            isTVOS: isTVOS
        )
    }

    nonisolated static func shouldResumeLocalGatewayPrimingPlayback(
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
        DirectPlaySessionPolicy.shouldResumeLocalGatewayPrimingPlayback(
            route: route,
            source: source,
            resumeSeconds: resumeSeconds,
            currentTime: currentTime,
            preheatResult: preheatResult,
            accessStallCount: accessStallCount,
            selectedAudioTrackID: selectedAudioTrackID,
            gatewayDiagnostics: gatewayDiagnostics,
            requirement: requirement,
            isTVOS: isTVOS
        )
    }

    nonisolated static func requiresStableStartupReadinessBuffer(
        route: PlaybackRoute,
        source: MediaSource?,
        requirement: PlaybackStartupReadinessPolicy.Requirement,
        isTVOS: Bool
    ) -> Bool {
        DirectPlaySessionPolicy.requiresStableStartupBuffer(
            route: route,
            source: source,
            requirement: requirement,
            isTVOS: isTVOS
        )
    }

    nonisolated static func hasStableStartupReadinessBuffer(
        bufferedDuration: Double,
        likelyToKeepUp: Bool,
        stableDuration: Double
    ) -> Bool {
        DirectPlaySessionPolicy.hasStableStartupBuffer(
            bufferedDuration: bufferedDuration,
            likelyToKeepUp: likelyToKeepUp,
            stableDuration: stableDuration
        )
    }

    nonisolated static func bufferedDurationAhead(
        playbackPosition: Double,
        loadedTimeRanges: [CMTimeRange]
    ) -> Double {
        let position = playbackPosition.isFinite ? max(0, playbackPosition) : 0
        return loadedTimeRanges.reduce(0) { longestDuration, range in
            let start = range.start.seconds
            let end = CMTimeRangeGetEnd(range).seconds
            guard start.isFinite, end.isFinite, end > position else {
                return longestDuration
            }
            guard start <= position + 0.5 else {
                return longestDuration
            }
            return max(longestDuration, end - position)
        }
    }

    nonisolated static func shouldWaitForItemReadyBeforeAutoplayAfterStartupSkip(
        route: PlaybackRoute,
        itemStatus: AVPlayerItem.Status
    ) -> Bool {
        guard case .directPlay = route else { return false }
        return itemStatus != .readyToPlay && itemStatus != .failed
    }

    nonisolated static func shouldAcceptMaterializedDirectPlayResumeSeek(
        currentTime: Double,
        resumeSeconds: Double,
        itemStatus: AVPlayerItem.Status,
        hasMarkedFirstFrame: Bool
    ) -> Bool {
        DirectPlaySessionPolicy.shouldAcceptMaterializedResumeSeek(
            currentTime: currentTime,
            resumeSeconds: resumeSeconds,
            itemStatus: itemStatus,
            hasMarkedFirstFrame: hasMarkedFirstFrame
        )
    }

    nonisolated static func shouldPreserveDirectPlayStartup(route: PlaybackRoute) -> Bool {
        shouldPreserveDirectPlayRecovery(route: route)
    }

    nonisolated static func shouldPreserveDirectPlayStartup(
        route: PlaybackRoute,
        source: MediaSource?,
        playbackPolicy: PlaybackPolicy,
        allowSDRFallback: Bool,
        usesDirectRemuxOnly: Bool,
        maxStreamingBitrate: Int,
        isTVOS: Bool
    ) -> Bool {
        if shouldPreemptivelyUseStableHLSForHighRiskDirectPlay(
            route: route,
            source: source,
            playbackPolicy: playbackPolicy,
            allowSDRFallback: allowSDRFallback,
            usesDirectRemuxOnly: usesDirectRemuxOnly,
            maxStreamingBitrate: maxStreamingBitrate,
            isTVOS: isTVOS
        ) {
            return false
        }

        return shouldPreserveDirectPlayStartup(route: route)
    }

    nonisolated static func shouldPreserveDirectPlayRecovery(route: PlaybackRoute?) -> Bool {
        guard let route else { return false }
        if case .directPlay = route {
            return true
        }
        return false
    }

    nonisolated static func isLocalMediaGatewayURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        guard LocalMediaGatewayURLPolicy.isLoopbackURL(url) else { return false }
        return url.path.contains("/media/") && url.pathExtension.lowercased() != "m3u8"
    }

    nonisolated static func redactedPlaylistURIForLog(_ uri: String?) -> String {
        guard let uri, !uri.isEmpty else { return "none" }
        guard var components = URLComponents(string: uri),
              let queryItems = components.queryItems,
              !queryItems.isEmpty
        else {
            return uri
        }

        let sensitiveNames: Set<String> = [
            "api_key", "apikey", "token", "access_token", "x-emby-token", "authorization"
        ]
        components.queryItems = queryItems.map { item in
            sensitiveNames.contains(item.name.lowercased())
                ? URLQueryItem(name: item.name, value: "REDACTED")
                : item
        }
        return components.string ?? uri
    }

    nonisolated static func directPlayRecoverySelection(
        preparedSelection: PlaybackAssetSelection,
        gatewayRemoteSelection: PlaybackAssetSelection?
    ) -> PlaybackAssetSelection {
        guard isLocalMediaGatewayURL(preparedSelection.assetURL),
              let gatewayRemoteSelection,
              gatewayRemoteSelection.source.itemID == preparedSelection.source.itemID,
              gatewayRemoteSelection.source.id == preparedSelection.source.id,
              LocalMediaGatewayURLPolicy.isSupportedRemoteURL(gatewayRemoteSelection.assetURL),
              case .directPlay = gatewayRemoteSelection.decision.route
        else {
            return preparedSelection
        }
        return gatewayRemoteSelection
    }

    nonisolated static func startupReadinessLoadedSelection(
        requestedSelection: PlaybackAssetSelection,
        preparedSelection: PlaybackAssetSelection?
    ) -> PlaybackAssetSelection {
        guard !isLocalMediaGatewayURL(requestedSelection.assetURL) else {
            return requestedSelection
        }
        guard let preparedSelection,
              isLocalMediaGatewayURL(preparedSelection.assetURL),
              preparedSelection.source.itemID == requestedSelection.source.itemID,
              preparedSelection.source.id == requestedSelection.source.id,
              case .directPlay = requestedSelection.decision.route,
              case .directPlay = preparedSelection.decision.route
        else {
            return requestedSelection
        }
        return preparedSelection
    }

    nonisolated static func shouldDisableLocalGatewayForDirectPlayRecovery(
        reason: String,
        preparedSelection: PlaybackAssetSelection,
        hasMarkedFirstFrame: Bool
    ) -> Bool {
        guard !hasMarkedFirstFrame else { return false }
        guard isLocalMediaGatewayURL(preparedSelection.assetURL) else { return false }

        switch StartupFailureReason(rawValue: reason) {
        case .decodedFrameWatchdog,
             .audioOnlyNoVideo,
             .readyButNoVideoFrame,
             .presentationSizeZero,
             .playerItemFailed,
             .playerItemFailedTransient,
             .startupWatchdogExpired:
            return true
        default:
            return false
        }
    }

    nonisolated static func shouldBypassSameRouteDirectPlayRecovery(
        reason: String,
        preparedSelection: PlaybackAssetSelection,
        hasMarkedFirstFrame: Bool,
        failureDomain: String?,
        failureCode: Int?
    ) -> Bool {
        guard !hasMarkedFirstFrame else { return false }
        guard isLocalMediaGatewayURL(preparedSelection.assetURL) else { return false }
        guard StartupFailureReason(rawValue: reason) == .playerItemFailedTransient else {
            return false
        }
        return failureDomain == AVFoundationErrorDomain
            && failureCode == AVError.serverIncorrectlyConfigured.rawValue
    }

    nonisolated static func canAttemptSameRouteDirectPlayRecovery(
        preparedSelection: PlaybackAssetSelection,
        gatewayRemoteSelection: PlaybackAssetSelection?
    ) -> Bool {
        guard isLocalMediaGatewayURL(preparedSelection.assetURL) else { return true }
        guard let gatewayRemoteSelection else { return false }
        return !isLocalMediaGatewayURL(gatewayRemoteSelection.assetURL)
    }

    nonisolated static func shouldBlockLegacyCoordinatorRecovery(
        isNativePlayerActive: Bool,
        nativeSurface: NativePlayerPlaybackSurface
    ) -> Bool {
        isNativePlayerActive && nativeSurface == .sampleBuffer
    }

    nonisolated static func shouldAllowAppleNativeCoordinatorFallback(
        reason: String,
        isNativePlayerActive: Bool,
        nativeSurface: NativePlayerPlaybackSurface
    ) -> Bool {
        guard !shouldBlockLegacyCoordinatorRecovery(
            isNativePlayerActive: isNativePlayerActive,
            nativeSurface: nativeSurface
        ) else {
            return false
        }
        guard nativeSurface == .appleNative else { return false }

        switch StartupFailureReason(rawValue: reason) {
        case .playerItemFailedTransient,
             .playerItemFailed,
             .startupVideoPrerollTimeout,
             .startupWatchdogExpired,
             .decodedFrameWatchdog,
             .audioOnlyNoVideo,
             .readyButNoVideoFrame,
             .presentationSizeZero:
            return true
        default:
            return false
        }
    }

    nonisolated static func shouldUseProfileFallbackAfterSameRouteDirectPlayRecoveryFailure(reason: String) -> Bool {
        switch StartupFailureReason(rawValue: reason) {
        case .decodedFrameWatchdog,
             .audioOnlyNoVideo,
             .readyButNoVideoFrame,
             .decoderStall,
             .presentationSizeZero,
             .playerItemFailed,
             .playerItemFailedTransient,
             .startupWatchdogExpired:
            return true
        default:
            return false
        }
    }

    nonisolated static func directPlaySameRouteRecoveryResumeSeconds(
        hasMarkedFirstFrame: Bool,
        playerSeconds: Double,
        sessionInitialResumeSeconds: Double,
        transcodeStartOffset: Double
    ) -> Double? {
        let currentSeconds = playerSeconds.isFinite ? max(0, playerSeconds) : 0
        let initialResumeSeconds = sessionInitialResumeSeconds.isFinite ? max(0, sessionInitialResumeSeconds) : 0
        let startOffsetSeconds = transcodeStartOffset.isFinite ? max(0, transcodeStartOffset) : 0

        let absoluteSeconds: Double
        if hasMarkedFirstFrame {
            absoluteSeconds = currentSeconds + startOffsetSeconds
        } else if startOffsetSeconds > 0 {
            absoluteSeconds = startOffsetSeconds
        } else {
            absoluteSeconds = max(initialResumeSeconds, currentSeconds)
        }

        return absoluteSeconds > 0 ? absoluteSeconds : nil
    }

    nonisolated static func shouldAttemptSameRouteDirectPlayRecovery(reason: String) -> Bool {
        switch StartupFailureReason(rawValue: reason) {
        case .decodedFrameWatchdog,
             .audioOnlyNoVideo,
             .readyButNoVideoFrame,
             .decoderStall,
             .presentationSizeZero,
             .playerItemFailed,
             .playerItemFailedTransient,
             .startupWatchdogExpired,
             .directPlayStall:
            return true
        default:
            return false
        }
    }

    nonisolated static func shouldUseFastDirectPlayStartup(
        route: PlaybackRoute,
        source: MediaSource?,
        maxStreamingBitrate: Int,
        isTVOS: Bool
    ) -> Bool {
        guard isTVOS else { return false }
        guard case let .directPlay(url) = route else { return false }
        guard url.pathExtension.lowercased() != "m3u8" else { return false }
        guard !DirectPlaySessionPolicy.isStallResistantDirectPlay(route: route, source: source) else { return false }
        guard let bitrate = source?.bitrate, bitrate > 0 else { return false }
        guard maxStreamingBitrate > 0 else { return false }
        return Double(maxStreamingBitrate) >= Double(bitrate) * 1.5
    }

    nonisolated static func shouldSuspendCurrentItemBeforeProfileRecovery(reason: String) -> Bool {
        switch StartupFailureReason(rawValue: reason) {
        case .startupReadinessTimeout,
             .startupVideoPrerollTimeout,
             .directPlayPreflightInsufficient,
             .decodedFrameWatchdog,
             .audioOnlyNoVideo,
             .readyButNoVideoFrame,
             .decoderStall,
             .presentationSizeZero,
             .playerItemFailed,
             .playerItemFailedTransient,
             .startupWatchdogExpired:
            return true
        default:
            return false
        }
    }

    nonisolated static func shouldDisableDirectRoutesForRecovery(reason: String) -> Bool {
        switch StartupFailureReason(rawValue: reason) {
        case .startupReadinessTimeout,
             .startupVideoPrerollTimeout,
             .directPlayPreflightInsufficient,
             .decodedFrameWatchdog,
             .audioOnlyNoVideo,
             .readyButNoVideoFrame,
             .decoderStall,
             .presentationSizeZero,
             .playerItemFailed,
             .playerItemFailedTransient,
             .startupWatchdogExpired:
            return true
        case .directPlayStall, .directPlayPostStartStall:
            // Adaptive fallback: a sustained direct-play stall means the connection can't carry the
            // original bitrate. Re-resolving to direct play would just re-stall — force a transcode
            // (sustainable HLS) so playback continues instead of freezing.
            return AdaptiveFallbackPolicy.isEnabled
        default:
            return false
        }
    }

    nonisolated static func shouldAllowNativeModeCoordinatorFallback(reason: String) -> Bool {
        shouldAllowNativeModeCoordinatorFallback(reason: reason, rootReason: nil)
    }

    nonisolated static func shouldAllowNativeModeCoordinatorFallback(
        reason: String,
        rootReason: String?
    ) -> Bool {
        if shouldStartNativeModeCoordinatorFallbackChain(reason: reason) {
            return true
        }

        _ = rootReason
        return false
    }

    nonisolated static func shouldStartNativeModeCoordinatorFallbackChain(reason: String) -> Bool {
        // Adaptive fallback (recovery-scoped): allow the native-engine session to hand a sustained
        // direct-play stall to the coordinator so it can resolve a sustainable HLS transcode
        // (never freeze). This only runs during recovery — startup never calls it — so it cannot
        // affect the initial route. Without this, `nativeCoordinatorFallbackReason` returns nil and
        // PlaybackCoordinator.resolvePlayback throws `.legacyPlaybackCoordinator` → the freeze.
        guard AdaptiveFallbackPolicy.isEnabled else { return false }
        switch StartupFailureReason(rawValue: reason) {
        case .directPlayStall, .directPlayPostStartStall:
            return true
        default:
            return false
        }
    }

    nonisolated static func canUseWarmedSelection(
        _ selection: PlaybackAssetSelection,
        resumeSeconds: Double
    ) -> Bool {
        guard resumeSeconds > 0 else { return true }
        if case .directPlay = selection.decision.route {
            return true
        }
        return false
    }

    static func shouldAttemptDirectPlayStallRecovery(
        route: PlaybackRoute,
        source: MediaSource?,
        recentStallCount: Int,
        elapsedSecondsSinceLoad: Double,
        elapsedSecondsSinceFirstFrame: Double?,
        isTVOS: Bool = false
    ) -> Bool {
        DirectPlaySessionPolicy.shouldAttemptStallRecovery(
            route: route,
            source: source,
            recentStallCount: recentStallCount,
            elapsedSecondsSinceLoad: elapsedSecondsSinceLoad,
            elapsedSecondsSinceFirstFrame: elapsedSecondsSinceFirstFrame,
            isTVOS: isTVOS
        )
    }

    static func shouldKeepCurrentDirectPlayItemAfterPostStartStall(
        route: PlaybackRoute,
        source: MediaSource?,
        isTVOS: Bool
    ) -> Bool {
        DirectPlaySessionPolicy.shouldKeepCurrentItemAfterPostStartStall(
            route: route,
            source: source,
            isTVOS: isTVOS
        )
    }

    static func shouldMarkDirectPlayRouteFragileAfterPostStartStall(
        route: PlaybackRoute,
        source: MediaSource?,
        recentStallCount: Int,
        elapsedSecondsSinceFirstFrame: Double?
    ) -> Bool {
        DirectPlaySessionPolicy.shouldMarkRouteFragileAfterPostStartStall(
            route: route,
            source: source,
            recentStallCount: recentStallCount,
            elapsedSecondsSinceFirstFrame: elapsedSecondsSinceFirstFrame
        )
    }

    static func postStartDirectPlayStallBufferDuration(
        currentForwardBufferDuration: Double,
        recentStallCount: Int = 1,
        isTVOS: Bool = false
    ) -> Double {
        DirectPlaySessionPolicy.postStartStallBufferDuration(
            currentForwardBufferDuration: currentForwardBufferDuration,
            recentStallCount: recentStallCount,
            isTVOS: isTVOS
        )
    }

    private static func markDirectPlayRouteFragile(
        route: PlaybackRoute,
        source: MediaSource?,
        at date: Date = Date()
    ) {
        guard let signature = directPlayRouteHealthSignature(route: route, source: source) else {
            return
        }
        pruneFragileDirectPlayRoutes(at: date)
        fragileDirectPlayRoutes[signature] = date
    }

    private static func isDirectPlayRouteMarkedFragile(
        route: PlaybackRoute,
        source: MediaSource?,
        at date: Date = Date()
    ) -> Bool {
        guard let signature = directPlayRouteHealthSignature(route: route, source: source) else {
            return false
        }
        pruneFragileDirectPlayRoutes(at: date)
        return fragileDirectPlayRoutes[signature] != nil
    }

    private static func pruneFragileDirectPlayRoutes(at date: Date) {
        fragileDirectPlayRoutes = fragileDirectPlayRoutes.filter {
            date.timeIntervalSince($0.value) <= fragileDirectPlayRouteTTL
        }
    }

    private static func directPlayRouteHealthSignature(
        route: PlaybackRoute,
        source: MediaSource?
    ) -> String? {
        guard case let .directPlay(url) = route, let source else { return nil }
        return [
            PlaybackServerNetworkBaseline.serverKey(for: url),
            source.itemID,
            source.id
        ].joined(separator: "|")
    }

    nonisolated static func directPlayPrestartRecoveryReason(
        route: PlaybackRoute,
        sourceBitrate: Int?,
        sourceIsHDRorDV: Bool = false,
        preheatResult: PlaybackStartupPreheater.Result?,
        serverBaselineResult: PlaybackServerNetworkBaseline.Result? = nil,
        isTVOS: Bool
    ) -> StartupFailureReason? {
        directPlayStartupDecision(
            route: route,
            sourceBitrate: sourceBitrate,
            sourceIsHDRorDV: sourceIsHDRorDV,
            preheatResult: preheatResult,
            serverBaselineResult: serverBaselineResult,
            isTVOS: isTVOS
        ).failureReason
    }

    nonisolated static func directPlayStartupDecision(
        route: PlaybackRoute,
        sourceBitrate: Int?,
        sourceIsHDRorDV: Bool = false,
        preheatResult: PlaybackStartupPreheater.Result?,
        serverBaselineResult: PlaybackServerNetworkBaseline.Result? = nil,
        isTVOS: Bool
    ) -> DirectPlayStartupPolicy.Decision {
        DirectPlayStartupPolicy.decision(
            route: route,
            sourceBitrate: sourceBitrate,
            sourceIsHDRorDV: sourceIsHDRorDV,
            itemPreheatResult: preheatResult,
            serverBaselineResult: serverBaselineResult,
            isTVOS: isTVOS
        )
    }

    static func shouldBlockAutoplayAfterUnsafeStartup(
        route: PlaybackRoute,
        source: MediaSource?,
        runtimeSeconds: Double?,
        resumeSeconds: Double,
        isTVOS: Bool
    ) -> Bool {
        let requirement = PlaybackStartupReadinessPolicy.requirement(
            route: route,
            sourceBitrate: source?.bitrate,
            sourceIsHDRorDV: source?.isLikelyHDRorDV == true,
            runtimeSeconds: runtimeSeconds,
            resumeSeconds: resumeSeconds,
            isTVOS: isTVOS
        )
        return requirement?.allowsTimeoutStart == false
    }

    nonisolated private static func shouldUseStallResistantDirectPlay(
        route: PlaybackRoute,
        source: MediaSource?
    ) -> Bool {
        DirectPlaySessionPolicy.isStallResistantDirectPlay(route: route, source: source)
    }

    nonisolated static func shouldPreemptivelyUseStableHLSForHighRiskDirectPlay(
        route: PlaybackRoute,
        source: MediaSource?,
        playbackPolicy: PlaybackPolicy,
        allowSDRFallback: Bool,
        usesDirectRemuxOnly: Bool,
        maxStreamingBitrate: Int,
        isTVOS: Bool
    ) -> Bool {
        _ = route
        _ = source
        _ = playbackPolicy
        _ = allowSDRFallback
        _ = usesDirectRemuxOnly
        _ = maxStreamingBitrate
        _ = isTVOS
        return false
    }

    nonisolated static func variantURLStrippingResumeQuery(
        masterURL _: URL,
        variantURL: URL
    ) -> URL {
        guard var components = URLComponents(url: variantURL, resolvingAgainstBaseURL: false) else {
            return variantURL
        }

        let resumeKeys = ["StartTimeTicks", "startTimeTicks", "StartTime", "startTime"]
        let variantItems = (components.queryItems ?? []).filter { item in
            !resumeKeys.contains { $0.caseInsensitiveCompare(item.name) == .orderedSame }
        }

        components.queryItems = variantItems.isEmpty ? nil : variantItems
        return components.url ?? variantURL
    }

    nonisolated static func initialTranscodeStartOffset(
        for selection: PlaybackAssetSelection,
        resumeSeconds: Double?
    ) -> Double {
        guard let resumeSeconds, resumeSeconds > 0 else { return 0 }
        guard isServerOffsetEligibleRoute(selection.decision.route) else { return 0 }
        return urlContainsServerStartTime(selection.assetURL) ? resumeSeconds : 0
    }

    nonisolated static func isServerOffsetEligibleRoute(_ route: PlaybackRoute?) -> Bool {
        switch route {
        case .remux, .transcode:
            return true
        case .directPlay, .nativeBridge, .none:
            return false
        }
    }

    nonisolated private static var deepPlaybackEvidenceIntervalSeconds: TimeInterval {
        5
    }

    nonisolated private static var isDeepPlaybackEvidenceEnabled: Bool {
        let value = ProcessInfo.processInfo.environment["REELFIN_PLAYER_DEEP_EVIDENCE"] ?? ""
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }

    nonisolated private static func timeControlStatusLabel(_ status: AVPlayer.TimeControlStatus) -> String {
        switch status {
        case .paused:
            return "paused"
        case .waitingToPlayAtSpecifiedRate:
            return "waiting"
        case .playing:
            return "playing"
        @unknown default:
            return "unknown"
        }
    }

    nonisolated private static func urlContainsServerStartTime(_ url: URL) -> Bool {
        let resumeKeys = ["StartTimeTicks", "startTimeTicks", "StartTime", "startTime"]
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.contains { item in
            resumeKeys.contains { $0.caseInsensitiveCompare(item.name) == .orderedSame }
        }
    }

    nonisolated static func shouldResumePlaybackAfterTrackReload(
        wasPlayingBeforeReplacement: Bool,
        playerRate: Float,
        timeControlStatus: AVPlayer.TimeControlStatus
    ) -> Bool {
        PlaybackResumePolicy.shouldResumeAfterItemReplacement(
            wasPlayingBeforeReplacement: wasPlayingBeforeReplacement,
            playerRate: playerRate,
            timeControlStatus: timeControlStatus
        )
    }
}

private extension URL {
    var queryItems: [URLQueryItem] {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }
}

public enum PlaybackResumePolicy {
    public static func shouldResumeAfterItemReplacement(
        wasPlayingBeforeReplacement: Bool,
        playerRate: Float,
        timeControlStatus: AVPlayer.TimeControlStatus
    ) -> Bool {
        wasPlayingBeforeReplacement || shouldResumeAfterControllerReattach(
            playerRate: playerRate,
            timeControlStatus: timeControlStatus
        )
    }

    public static func shouldResumeAfterControllerReattach(
        playerRate: Float,
        timeControlStatus: AVPlayer.TimeControlStatus
    ) -> Bool {
        playerRate > 0 || timeControlStatus == .playing || timeControlStatus == .waitingToPlayAtSpecifiedRate
    }

    public struct ControllerReattachPlaybackIntent: Equatable, Sendable {
        public let pauseDuringDetach: Bool
        public let resumeAfterAttach: Bool
    }

    public static func controllerReattachPlaybackIntent(
        playerRate: Float,
        timeControlStatus: AVPlayer.TimeControlStatus
    ) -> ControllerReattachPlaybackIntent {
        let shouldResume = shouldResumeAfterControllerReattach(
            playerRate: playerRate,
            timeControlStatus: timeControlStatus
        )
        return ControllerReattachPlaybackIntent(
            pauseDuringDetach: shouldResume,
            resumeAfterAttach: shouldResume
        )
    }
}
