import AVFoundation
import Combine
import CoreMedia
import Foundation
import Shared
import UIKit

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
    private var startDate = Date()

    private var readyInterval: SignpostInterval?
    private var firstFrameInterval: SignpostInterval?
    private var activeStallInterval: SignpostInterval?

    public init(
        apiClient: JellyfinAPIClientProtocol,
        repository: MetadataRepositoryProtocol,
        decisionEngine: PlaybackDecisionEngine = PlaybackDecisionEngine()
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.coordinator = PlaybackCoordinator(apiClient: apiClient, decisionEngine: decisionEngine)
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
    }

    public func load(item: MediaItem, autoPlay: Bool = true) async throws {
        currentItemID = item.id
        startDate = Date()
        hasMarkedFirstFrame = false
        metrics = PlaybackPerformanceMetrics()
        playbackErrorMessage = nil

        let selection = try await coordinator.resolvePlayback(itemID: item.id, mode: .performance)
        currentSource = selection.source
        debugInfo = selection.debugInfo
        runtimeHDRMode = selection.debugInfo.hdrMode
        playMethodForReporting = selection.decision.playMethod

        availableAudioTracks = selection.source.audioTracks
        availableSubtitleTracks = selection.source.subtitleTracks
        selectedAudioTrackID = availableAudioTracks.first(where: { $0.isDefault })?.id
        selectedSubtitleTrackID = nil

        routeDescription = routeLabel(for: selection.decision.route)

        let asset = AVURLAsset(
            url: selection.assetURL,
            options: ["AVURLAssetHTTPHeaderFieldsKey": selection.headers]
        )

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 12
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        readyInterval = SignpostInterval(signposter: Signpost.playerLifecycle, name: "avplayer_item_ready")
        firstFrameInterval = SignpostInterval(signposter: Signpost.playerLifecycle, name: "avplayer_first_frame")

        player.replaceCurrentItem(with: playerItem)
        configureObservers(for: playerItem)

        if let progress = try await repository.fetchPlaybackProgress(itemID: item.id), progress.positionTicks > 0 {
            let seconds = Double(progress.positionTicks) / 10_000_000
            let seekTime = CMTime(seconds: seconds, preferredTimescale: 600)
            _ = await player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        if autoPlay {
            play()
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
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        player.actionAtItemEnd = .pause

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
            if self.isPlaying {
                self.didResumeAfterForeground = true
                self.pause()
            }
        }

        let active = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.didResumeAfterForeground {
                self.didResumeAfterForeground = false
                self.play()
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
                if observedItem.status == .readyToPlay {
                    self.readyInterval?.end(name: "avplayer_item_ready", message: "ready_to_play")
                    self.readyInterval = nil
                    self.runtimeHDRMode = self.detectHDRMode(from: observedItem, fallback: self.debugInfo?.hdrMode ?? .unknown)
                } else if observedItem.status == .failed {
                    self.readyInterval?.end(name: "avplayer_item_ready", message: "ready_failed")
                    self.firstFrameInterval?.end(name: "avplayer_first_frame", message: "first_frame_failed")
                    let message = observedItem.error?.localizedDescription ?? "Playback failed."
                    self.playbackErrorMessage = message
                    self.isPlaying = false
                    AppLog.playback.error("AVPlayerItem failed: \(message, privacy: .public)")
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
        hasMarkedFirstFrame = true
        let elapsedMs = Date().timeIntervalSince(startDate) * 1000
        metrics.timeToFirstFrameMs = elapsedMs
        firstFrameInterval?.end(name: "avplayer_first_frame", message: "first_frame_rendered")
        firstFrameInterval = nil
        AppLog.playback.info("TTFF \(elapsedMs, format: .fixed(precision: 1))ms")
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
