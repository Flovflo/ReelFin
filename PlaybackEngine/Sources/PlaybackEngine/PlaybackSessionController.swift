import AVFoundation
import Combine
import Foundation
import Shared

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

    public let player = AVPlayer()

    private let apiClient: JellyfinAPIClientProtocol
    private let repository: MetadataRepositoryProtocol
    private let decisionEngine: PlaybackDecisionEngine

    private var periodicObserver: Any?
    private var endObserver: NSObjectProtocol?

    private var currentItemID: String?
    private var currentSource: MediaSource?

    public init(
        apiClient: JellyfinAPIClientProtocol,
        repository: MetadataRepositoryProtocol,
        decisionEngine: PlaybackDecisionEngine = PlaybackDecisionEngine()
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.decisionEngine = decisionEngine
    }

    deinit {
        if let periodicObserver {
            player.removeTimeObserver(periodicObserver)
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    public func load(item: MediaItem, autoPlay: Bool = true) async throws {
        currentItemID = item.id

        let sources = try await apiClient.fetchPlaybackSources(itemID: item.id)

        guard
            let configuration = await apiClient.currentConfiguration(),
            let session = await apiClient.currentSession(),
            let decision = decisionEngine.decide(
                itemID: item.id,
                sources: sources,
                configuration: configuration,
                token: session.token
            )
        else {
            throw AppError.network("No playable sources were found.")
        }

        currentSource = sources.first { $0.id == decision.sourceID }
        availableAudioTracks = currentSource?.audioTracks ?? []
        availableSubtitleTracks = currentSource?.subtitleTracks ?? []
        selectedAudioTrackID = availableAudioTracks.first(where: { $0.isDefault })?.id
        selectedSubtitleTrackID = nil

        let assetURL: URL
        switch decision.route {
        case let .directPlay(url):
            routeDescription = "Direct Play"
            assetURL = url
        case let .remux(url):
            routeDescription = "Direct Stream"
            assetURL = url
        case let .transcode(url):
            routeDescription = "Transcoding"
            assetURL = url
        }

        var headers: [String: String] = [:]
        headers["X-Emby-Token"] = session.token
        let asset = AVURLAsset(url: assetURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)

        if let progress = try await repository.fetchPlaybackProgress(itemID: item.id), progress.positionTicks > 0 {
            let seconds = Double(progress.positionTicks) / 10_000_000
            let seekTime = CMTime(seconds: seconds, preferredTimescale: 600)
            _ = await player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        configureObservers(for: playerItem)

        if autoPlay {
            play()
        }
    }

    public func play() {
        player.play()
        isPlaying = true
    }

    public func pause() {
        player.pause()
        isPlaying = false
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

    private func configureObservers(for item: AVPlayerItem) {
        if let periodicObserver {
            player.removeTimeObserver(periodicObserver)
            self.periodicObserver = nil
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 15, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds
                self.duration = self.player.currentItem?.duration.seconds ?? 0
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
            didFinish: didFinish
        )

        try? await apiClient.reportPlayback(progress: remoteProgress)
    }
}
