import AVFoundation
import Combine
import CoreMedia
import Foundation
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

@MainActor
public final class PlaybackSessionController: ObservableObject {
    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0
    @Published public private(set) var availableAudioTracks: [MediaTrack] = []
    @Published public private(set) var availableSubtitleTracks: [MediaTrack] = []
    @Published public private(set) var selectedAudioTrackID: String?
    @Published public private(set) var selectedSubtitleTrackID: String?
    @Published public private(set) var routeDescription: String = ""
    @Published public private(set) var debugInfo: PlaybackDebugInfo?
    @Published public private(set) var runtimeHDRMode: HDRPlaybackMode = .unknown
    @Published public private(set) var metrics = PlaybackPerformanceMetrics()
    @Published public private(set) var isExternalPlaybackActive = false
    @Published public private(set) var playbackErrorMessage: String?

    public let player = AVPlayer()

    private let apiClient: JellyfinAPIClientProtocol
    private let repository: MetadataRepositoryProtocol
    private let coordinator: PlaybackCoordinator

    private var periodicObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var accessLogObserver: NSObjectProtocol?

    private var playerItemStatusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var externalPlaybackObserver: NSKeyValueObservation?
    private var lifecycleObservers: [NSObjectProtocol] = []

    private var currentItemID: String?
    private var currentSource: MediaSource?
    private var playMethodForReporting = "Transcode"
    private var didResumeAfterForeground = false
    private var hasMarkedFirstFrame = false
    private var hasDecodedVideoFrame = false
    private var playbackStrategy: PlaybackStrategy = .bestQualityFastest
    private var activeTranscodeProfile: TranscodeURLProfile = .serverDefault
    private var recoveryAttemptCount = 0
    private let maxRecoveryAttempts = 2
    private var isRecoveryInProgress = false
    private var startDate = Date()
    private var preferredProfilesByItemID: [String: TranscodeURLProfile] = [:]

    private var readyInterval: SignpostInterval?
    private var firstFrameInterval: SignpostInterval?
    private var activeStallInterval: SignpostInterval?
    private var startupWatchdogTask: Task<Void, Never>?
    private var decodedFrameWatchdogTask: Task<Void, Never>?
    private static let preferredProfileStorageKey = "reelfin.playback.preferredTranscodeProfileByItemID.v2"

    public init(
        apiClient: JellyfinAPIClientProtocol,
        repository: MetadataRepositoryProtocol,
        decisionEngine: PlaybackDecisionEngine = PlaybackDecisionEngine()
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.coordinator = PlaybackCoordinator(apiClient: apiClient, decisionEngine: decisionEngine)
        self.preferredProfilesByItemID = Self.loadStoredPreferredProfiles()
        configurePlayerBase()
        setupLifecycleObservers()
    }

    deinit {
        if let periodicObserver {
            player.removeTimeObserver(periodicObserver)
        }

        [endObserver, stalledObserver, accessLogObserver].forEach {
            if let observer = $0 {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        lifecycleObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        startupWatchdogTask?.cancel()
        decodedFrameWatchdogTask?.cancel()
    }

    public func load(item: MediaItem, autoPlay: Bool = true) async throws {
        currentItemID = item.id
        startDate = Date()
        hasMarkedFirstFrame = false
        hasDecodedVideoFrame = false
        recoveryAttemptCount = 0
        metrics = PlaybackPerformanceMetrics()
        playbackErrorMessage = nil
        startupWatchdogTask?.cancel()
        decodedFrameWatchdogTask?.cancel()
        activeTranscodeProfile = preferredProfilesByItemID[item.id] ?? .serverDefault
        playbackStrategy = await currentPlaybackStrategy()

        do {
            var selection = try await coordinator.resolvePlayback(
                itemID: item.id,
                mode: .performance,
                allowTranscodingFallbackInPerformance: !usesDirectRemuxOnly,
                transcodeProfile: activeTranscodeProfile
            )
            var forcedH264ByManifestGuard = false

            if shouldBypassServerDefaultHEVCSelection(selection) {
                AppLog.playback.warning("Bypassing serverDefault HEVC stream-copy profile for this item.")
                activeTranscodeProfile = .appleOptimizedHEVC
                selection = try await coordinator.resolvePlayback(
                    itemID: item.id,
                    mode: .balanced,
                    allowTranscodingFallbackInPerformance: true,
                    transcodeProfile: activeTranscodeProfile
                )
            }

            activeTranscodeProfile = inferredTranscodeProfile(from: selection.assetURL, fallback: activeTranscodeProfile)

            if !usesDirectRemuxOnly, await shouldForceCompatibilityH264(for: selection) {
                AppLog.playback.warning(
                    "HEVC transcode manifest appears degraded/unstable for this source. Using compatibility H264 profile."
                )
                activeTranscodeProfile = .forceH264Transcode
                forcedH264ByManifestGuard = true
                selection = try await coordinator.resolvePlayback(
                    itemID: item.id,
                    mode: .balanced,
                    allowTranscodingFallbackInPerformance: true,
                    transcodeProfile: activeTranscodeProfile
                )
                activeTranscodeProfile = inferredTranscodeProfile(from: selection.assetURL, fallback: activeTranscodeProfile)
            }

            if !usesDirectRemuxOnly, case .transcode = selection.decision.route, !(await preflightSelection(selection)) {
                if forcedH264ByManifestGuard, activeTranscodeProfile == .forceH264Transcode {
                    AppLog.playback.warning(
                        "Preflight failed while HEVC manifest guard is active. Keeping forced H264 startup path."
                    )
                } else {
                if activeTranscodeProfile != .appleOptimizedHEVC {
                    AppLog.playback.warning(
                        "Initial transcode preflight failed (non-blocking). Trying Apple optimized HEVC profile."
                    )
                    activeTranscodeProfile = .appleOptimizedHEVC
                    selection = try await coordinator.resolvePlayback(
                        itemID: item.id,
                        mode: .balanced,
                        allowTranscodingFallbackInPerformance: true,
                        transcodeProfile: activeTranscodeProfile
                    )
                    activeTranscodeProfile = inferredTranscodeProfile(from: selection.assetURL, fallback: activeTranscodeProfile)
                }

                if case .transcode = selection.decision.route,
                   !(await preflightSelection(selection)),
                   activeTranscodeProfile != .forceH264Transcode
                {
                    AppLog.playback.warning(
                        "Apple optimized preflight failed (non-blocking). Switching to compatibility H264 profile."
                    )
                    activeTranscodeProfile = .forceH264Transcode
                    selection = try await coordinator.resolvePlayback(
                        itemID: item.id,
                        mode: .balanced,
                        allowTranscodingFallbackInPerformance: true,
                        transcodeProfile: activeTranscodeProfile
                    )
                    activeTranscodeProfile = inferredTranscodeProfile(from: selection.assetURL, fallback: activeTranscodeProfile)
                }
                }
            }

            prepareAndLoadSelection(selection, resumeSeconds: nil)

            if let progress = try await repository.fetchPlaybackProgress(itemID: item.id), progress.positionTicks > 0 {
                let seconds = Double(progress.positionTicks) / 10_000_000
                let seekTime = CMTime(seconds: seconds, preferredTimescale: 600)
                _ = await player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
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

    private var usesDirectRemuxOnly: Bool {
        playbackStrategy == .directRemuxOnly
    }

    private func currentPlaybackStrategy() async -> PlaybackStrategy {
        guard let configuration = await apiClient.currentConfiguration() else {
            return .bestQualityFastest
        }
        return configuration.playbackStrategy
    }

    private func prepareAndLoadSelection(_ selection: PlaybackAssetSelection, resumeSeconds: Double?) {
        startupWatchdogTask?.cancel()
        decodedFrameWatchdogTask?.cancel()
        activeTranscodeProfile = inferredTranscodeProfile(from: selection.assetURL, fallback: activeTranscodeProfile)
        currentSource = selection.source
        debugInfo = selection.debugInfo
        runtimeHDRMode = selection.debugInfo.hdrMode
        playMethodForReporting = selection.decision.playMethod

        availableAudioTracks = selection.source.audioTracks
        availableSubtitleTracks = selection.source.subtitleTracks
        selectedAudioTrackID = availableAudioTracks.first(where: { $0.isDefault })?.id
        selectedSubtitleTrackID = nil

        routeDescription = routeLabel(for: selection.decision.route)

        var assetOptions: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": selection.headers]
#if os(iOS)
        assetOptions["AVURLAssetAllowsCellularAccessKey"] = true
#endif
        let asset = AVURLAsset(url: selection.assetURL, options: assetOptions)

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        readyInterval = SignpostInterval(signposter: Signpost.playerLifecycle, name: "avplayer_item_ready")
        firstFrameInterval = SignpostInterval(signposter: Signpost.playerLifecycle, name: "avplayer_first_frame")
        hasMarkedFirstFrame = false
        hasDecodedVideoFrame = false
        startDate = Date()

        player.replaceCurrentItem(with: playerItem)
        configureObservers(for: playerItem)

        if let resumeSeconds, resumeSeconds > 0 {
            let seek = CMTime(seconds: resumeSeconds, preferredTimescale: 600)
            player.seek(to: seek, toleranceBefore: .zero, toleranceAfter: .zero)
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
    }

    public func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func selectAudioTrack(id: String) {
        guard
            let item = player.currentItem,
            let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
            let track = availableAudioTracks.first(where: { $0.id == id })
        else {
            return
        }

        let options = group.options
        guard track.index < options.count else { return }

        item.select(options[track.index], in: group)
        selectedAudioTrackID = id
    }

    public func selectSubtitleTrack(id: String?) {
        guard
            let item = player.currentItem,
            let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        else {
            return
        }

        if let id, let track = availableSubtitleTracks.first(where: { $0.id == id }) {
            let options = group.options
            guard track.index < options.count else { return }
            item.select(options[track.index], in: group)
            selectedSubtitleTrackID = id
        } else {
            item.select(nil, in: group)
            selectedSubtitleTrackID = nil
        }
    }

    private func configurePlayerBase() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = true
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
        if let periodicObserver {
            player.removeTimeObserver(periodicObserver)
            self.periodicObserver = nil
        }

        [endObserver, stalledObserver, accessLogObserver].forEach {
            if let observer = $0 {
                NotificationCenter.default.removeObserver(observer)
            }
        }

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
            }
        }

        playerItemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.player.currentItem === observedItem else { return }
                if observedItem.status == .readyToPlay {
                    self.readyInterval?.end(name: "avplayer_item_ready", message: "ready_to_play")
                    self.readyInterval = nil
                    self.runtimeHDRMode = self.detectHDRMode(from: observedItem, fallback: self.debugInfo?.hdrMode ?? .unknown)
                    self.scheduleVideoValidation(for: observedItem)
                } else if observedItem.status == .failed {
                    self.readyInterval?.end(name: "avplayer_item_ready", message: "ready_failed")
                    self.firstFrameInterval?.end(name: "avplayer_first_frame", message: "first_frame_failed")
                    let message = observedItem.error?.localizedDescription ?? "Playback failed."
                    self.isPlaying = false
                    if let nsError = observedItem.error as NSError? {
                        AppLog.playback.error(
                            "AVPlayerItem error domain=\(nsError.domain, privacy: .public) code=\(nsError.code) message=\(message, privacy: .public)"
                        )
                    }
                    AppLog.playback.error("AVPlayerItem failed: \(message, privacy: .public)")

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
        let elapsedMs = Date().timeIntervalSince(startDate) * 1000
        metrics.timeToFirstFrameMs = elapsedMs
        firstFrameInterval?.end(name: "avplayer_first_frame", message: "first_frame_rendered")
        firstFrameInterval = nil
        rememberWorkingProfileForCurrentItem()
        AppLog.playback.info("TTFF \(elapsedMs, format: .fixed(precision: 1))ms")
    }

    private func scheduleVideoValidation(for item: AVPlayerItem) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
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

    private func scheduleStartupWatchdog() {
        startupWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let delay = self.startupWatchdogDelayNanoseconds()
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            guard !self.hasMarkedFirstFrame else { return }
            guard self.player.currentItem != nil else { return }

            let delaySeconds = Double(delay) / 1_000_000_000
            AppLog.playback.warning("Startup watchdog fired: no first frame after \(delaySeconds, format: .fixed(precision: 1))s.")
            if !(await self.attemptRecovery(
                reason: "startup_watchdog",
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

            let playbackHasStarted = self.currentTime >= 0.8 || self.player.timeControlStatus == .playing || self.player.rate > 0
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
            return 8_000_000_000
        case .appleOptimizedHEVC:
            return 10_000_000_000
        case .conservativeCompatibility:
            return 10_000_000_000
        case .forceH264Transcode:
            return 8_000_000_000
        }
    }

    private func startupWatchdogDelayNanoseconds() -> UInt64 {
        switch activeTranscodeProfile {
        case .serverDefault:
            return 12_000_000_000
        case .appleOptimizedHEVC:
            return 15_000_000_000
        case .conservativeCompatibility:
            return 15_000_000_000
        case .forceH264Transcode:
            return 12_000_000_000
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
        guard recoveryAttemptCount < maxRecoveryAttempts else { return false }
        isRecoveryInProgress = true
        defer { isRecoveryInProgress = false }
        recoveryAttemptCount += 1

        let attempt = recoveryAttemptCount
        AppLog.playback.warning("Recovery attempt \(attempt) reason=\(reason, privacy: .public)")
        _ = userMessage
        playbackErrorMessage = nil

        if retryDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            guard player.currentItem != nil else { return false }
        }

        return await reloadRecoveryTranscode(reason: reason, attempt: attempt)
    }

    private func handlePlaybackFailure(message: String, error: NSError?) async -> Bool {
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
        return false
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
        let request = makeProbeRequest(url: url, headers: headers, range: nil)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw AppError.network("Playlist request failed.")
        }

        guard let manifest = String(data: data, encoding: .utf8), manifest.contains("#EXTM3U") else {
            throw AppError.network("Invalid HLS playlist.")
        }
        return manifest
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

    private func reloadRecoveryTranscode(reason: String, attempt: Int) async -> Bool {
        let resumeSeconds = max(0, player.currentTime().seconds)
        guard let itemID = currentItemID else { return false }

        let mode: PlaybackMode = usesDirectRemuxOnly ? .performance : .balanced
        let allowTranscodingFallback = !usesDirectRemuxOnly

        var lastError: Error?
        for profile in recoveryProfiles(for: reason, attempt: attempt) {
            do {
                let selection = try await coordinator.resolvePlayback(
                    itemID: itemID,
                    mode: mode,
                    allowTranscodingFallbackInPerformance: allowTranscodingFallback,
                    transcodeProfile: profile
                )

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
        }
        return false
    }

    private func recoveryProfiles(for reason: String, attempt: Int) -> [TranscodeURLProfile] {
        _ = attempt
        if usesDirectRemuxOnly {
            return [.serverDefault]
        }

        let baseProfiles: [TranscodeURLProfile]
        switch reason {
        case "audio_only_no_video":
            baseProfiles = startupRecoveryProfiles(after: activeTranscodeProfile)
        case "decoded_frame_watchdog":
            baseProfiles = startupRecoveryProfiles(after: activeTranscodeProfile)
        case "risky_hevc_stream_copy":
            baseProfiles = startupRecoveryProfiles(after: activeTranscodeProfile)
        case "video_presentation_size_zero":
            baseProfiles = startupRecoveryProfiles(after: activeTranscodeProfile)
        case "startup_watchdog":
            baseProfiles = startupRecoveryProfiles(after: activeTranscodeProfile)
        default:
            baseProfiles = [
                nextRecoveryProfile(after: activeTranscodeProfile),
                .appleOptimizedHEVC,
                .forceH264Transcode,
                .conservativeCompatibility,
                .serverDefault
            ]
        }

        return deduplicatedProfiles(baseProfiles)
    }

    private func nextRecoveryProfile(after profile: TranscodeURLProfile) -> TranscodeURLProfile {
        switch profile {
        case .serverDefault:
            return .appleOptimizedHEVC
        case .appleOptimizedHEVC:
            return .conservativeCompatibility
        case .conservativeCompatibility:
            return .forceH264Transcode
        case .forceH264Transcode:
            return .appleOptimizedHEVC
        }
    }

    private func deduplicatedProfiles(_ profiles: [TranscodeURLProfile]) -> [TranscodeURLProfile] {
        var seen = Set<TranscodeURLProfile>()
        return profiles.filter { seen.insert($0).inserted }
    }

    private func startupRecoveryProfiles(after activeProfile: TranscodeURLProfile) -> [TranscodeURLProfile] {
        switch activeProfile {
        case .serverDefault:
            return [.forceH264Transcode, .appleOptimizedHEVC, .conservativeCompatibility, .serverDefault]
        case .appleOptimizedHEVC:
            return [.forceH264Transcode, .conservativeCompatibility, .serverDefault]
        case .conservativeCompatibility:
            return [.forceH264Transcode, .appleOptimizedHEVC, .serverDefault]
        case .forceH264Transcode:
            return [.appleOptimizedHEVC, .conservativeCompatibility, .serverDefault]
        }
    }

    private func shouldBypassServerDefaultHEVCSelection(_ selection: PlaybackAssetSelection) -> Bool {
        guard activeTranscodeProfile == .serverDefault else { return false }
        guard case .transcode = selection.decision.route else { return false }

        let query = transcodeQueryMap(from: selection.assetURL)
        guard query["allowvideostreamcopy"] == "true" else { return false }
        let codec = query["videocodec"] ?? selection.source.normalizedVideoCodec
        return isHEVCCodec(codec)
    }

    private func refreshDecodedVideoFrameState() {
        guard !hasDecodedVideoFrame else { return }
        guard let item = player.currentItem else { return }
        
        let size = item.presentationSize
        if size.width > 2 && size.height > 2 {
            hasDecodedVideoFrame = true
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

        let profile = inferredTranscodeProfile(
            from: (player.currentItem?.asset as? AVURLAsset)?.url,
            fallback: activeTranscodeProfile
        )

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
            return .conservativeCompatibility
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
        guard let itemID = currentItemID else { return }

        let positionSeconds = max(0, player.currentTime().seconds)
        let totalSeconds = max(positionSeconds, player.currentItem?.duration.seconds ?? 0)

        let positionTicks = Int64(positionSeconds * 10_000_000)
        let totalTicks = Int64(totalSeconds * 10_000_000)

        let localProgress = PlaybackProgress(
            itemID: itemID,
            positionTicks: positionTicks,
            totalTicks: totalTicks,
            updatedAt: Date()
        )
        try? await repository.savePlaybackProgress(localProgress)

        let remoteProgress = PlaybackProgressUpdate(
            itemID: itemID,
            positionTicks: positionTicks,
            totalTicks: totalTicks,
            isPaused: isPaused,
            isPlaying: !isPaused,
            didFinish: didFinish,
            playMethod: playMethodForReporting
        )

        try? await apiClient.reportPlayback(progress: remoteProgress)
    }

    private func routeLabel(for route: PlaybackRoute) -> String {
        switch route {
        case .directPlay:
            return "Direct Play"
        case .remux:
            return "Direct Stream"
        case .transcode:
            return "Transcode (HLS)"
        }
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
