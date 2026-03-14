import AVFoundation
import Foundation
import Shared

// MARK: - Native AVPlayer Engine

/// Wraps AVPlayer as a PlaybackEngineAdapter.
/// This is a lightweight adapter for the unified hybrid system.
/// The heavy lifting (KVO, watchdog, recovery) stays in PlaybackSessionController.
@Observable
@MainActor
public final class NativeAVPlayerEngine: PlaybackEngineAdapter, NativePlayerProviding {

    // MARK: - Public State

    public private(set) var playbackState: UnifiedPlaybackState = .idle
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isBuffering = false
    public private(set) var errorMessage: String?
    public private(set) var audioTracks: [UnifiedTrack] = []
    public private(set) var subtitleTracks: [UnifiedTrack] = []
    public private(set) var selectedAudioTrackID: String?
    public private(set) var selectedSubtitleTrackID: String?
    public private(set) var isPlaying = false

    public let engineType: PlaybackEngineType = .native
    public let avPlayer = AVPlayer()

    // MARK: - Callbacks

    public var onStateChange: ((UnifiedPlaybackState) -> Void)?
    public var onTimeUpdate: ((TimeInterval) -> Void)?
    public var onPlaybackEnded: (() -> Void)?
    public var onError: ((String) -> Void)?

    // MARK: - Private

    private let stateMachine = PlaybackStateMachine()
    private var periodicObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?

    // MARK: - Init

    public init() {
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        stateMachine.onTransition = { [weak self] _, newState in
            self?.playbackState = newState
            self?.onStateChange?(newState)
        }
    }

    // MARK: - PlaybackEngineAdapter

    public func prepare(url: URL, headers: [String: String]) async throws {
        cleanupObservers()
        stateMachine.transition(to: .preparing)

        let options: [String: Any]
        if !headers.isEmpty {
            options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        } else {
            options = [:]
        }

        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5

        avPlayer.replaceCurrentItem(with: item)
        setupObservers()

        // Wait for ready or failure
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard !resumed else { return }
                switch item.status {
                case .readyToPlay:
                    resumed = true
                    Task { @MainActor [weak self] in
                        self?.stateMachine.transition(to: .ready)
                        self?.updateDuration()
                        self?.populateTracks()
                    }
                    continuation.resume()
                case .failed:
                    resumed = true
                    let message = item.error?.localizedDescription ?? "AVPlayerItem failed"
                    Task { @MainActor [weak self] in
                        self?.errorMessage = message
                        self?.stateMachine.transition(to: .failed)
                        self?.onError?(message)
                    }
                    continuation.resume(throwing: AppError.network(message))
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    public func play() {
        avPlayer.play()
        stateMachine.transition(to: .playing)
        isPlaying = true
    }

    public func pause() {
        avPlayer.pause()
        stateMachine.transition(to: .paused)
        isPlaying = false
    }

    public func seek(to seconds: TimeInterval) async {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 1.5, preferredTimescale: 600)
        stateMachine.transition(to: .seeking)
        _ = await avPlayer.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
        if avPlayer.rate > 0 {
            stateMachine.transition(to: .playing)
        } else {
            stateMachine.transition(to: .paused)
        }
    }

    public func stop() {
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        cleanupObservers()
        stateMachine.forceState(.idle)
        isPlaying = false
        currentTime = 0
        duration = 0
        audioTracks = []
        subtitleTracks = []
    }

    public func selectAudioTrack(id: String) {
        guard let item = avPlayer.currentItem else { return }
        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }

        if let index = Int(id), index < group.options.count {
            item.select(group.options[index], in: group)
            selectedAudioTrackID = id
        }
    }

    public func selectSubtitleTrack(id: String?) {
        guard let item = avPlayer.currentItem else { return }
        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }

        if let id, let index = Int(id), index < group.options.count {
            item.select(group.options[index], in: group)
            selectedSubtitleTrackID = id
        } else {
            item.select(nil, in: group)
            selectedSubtitleTrackID = nil
        }
    }

    public func setRate(_ rate: Float) {
        avPlayer.rate = rate
    }

    // MARK: - Observers

    private func setupObservers() {
        // Periodic time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        periodicObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            self.currentTime = seconds
            self.onTimeUpdate?(seconds)
        }

        // Time control status
        timeControlObservation = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                    if self.playbackState == .buffering || self.playbackState == .stalled {
                        self.stateMachine.transition(to: .playing)
                    }
                case .paused:
                    self.isPlaying = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering = true
                    if self.playbackState == .playing {
                        self.stateMachine.transition(to: .buffering)
                    }
                @unknown default:
                    break
                }
            }
        }

        // End of playback
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stateMachine.transition(to: .ended)
                self?.isPlaying = false
                self?.onPlaybackEnded?()
            }
        }

        // Stall
        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: avPlayer.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stateMachine.transition(to: .stalled)
                self?.isBuffering = true
            }
        }
    }

    private func cleanupObservers() {
        if let periodicObserver {
            avPlayer.removeTimeObserver(periodicObserver)
        }
        periodicObserver = nil
        itemStatusObservation = nil
        timeControlObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
        }
        stalledObserver = nil
    }

    // MARK: - Track Enumeration

    private func populateTracks() {
        guard let item = avPlayer.currentItem else { return }

        // Audio tracks
        if let audioGroup = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            audioTracks = audioGroup.options.enumerated().map { index, option in
                UnifiedTrack(
                    id: "\(index)",
                    title: option.displayName,
                    language: option.extendedLanguageTag ?? option.locale?.language.languageCode?.identifier,
                    codec: nil,
                    isDefault: audioGroup.defaultOption == option,
                    index: index,
                    engineSource: .native
                )
            }
        }

        // Subtitle tracks
        if let subtitleGroup = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            subtitleTracks = subtitleGroup.options.enumerated().compactMap { index, option in
                // Skip forced/CC-only tracks from the picker
                guard !option.hasMediaCharacteristic(.containsOnlyForcedSubtitles) else { return nil }
                return UnifiedTrack(
                    id: "\(index)",
                    title: option.displayName,
                    language: option.extendedLanguageTag ?? option.locale?.language.languageCode?.identifier,
                    codec: nil,
                    isDefault: subtitleGroup.defaultOption == option,
                    index: index,
                    engineSource: .native
                )
            }
        }
    }

    private func updateDuration() {
        guard let item = avPlayer.currentItem else { return }
        let seconds = item.duration.seconds
        if seconds.isFinite && seconds > 0 {
            duration = seconds
        }
    }
}
