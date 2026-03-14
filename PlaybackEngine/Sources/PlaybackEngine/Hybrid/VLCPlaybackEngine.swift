import Foundation
import Shared
import UIKit

#if canImport(MobileVLCKit)
import MobileVLCKit
#elseif canImport(TVVLCKit)
import TVVLCKit
#endif

// MARK: - VLC Playback Engine

/// Wraps VLCKit (MobileVLCKit / TVVLCKit) as a PlaybackEngineAdapter.
/// All VLC-specific logic is isolated here; the UI never touches VLC directly.
///
/// When VLCKit is not available (canImport fails), this class still compiles
/// but returns a "VLC unavailable" error on prepare().
@Observable
@MainActor
public final class VLCPlaybackEngine: PlaybackEngineAdapter {

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

    public let engineType: PlaybackEngineType = .vlc

    // MARK: - Callbacks

    public var onStateChange: ((UnifiedPlaybackState) -> Void)?
    public var onTimeUpdate: ((TimeInterval) -> Void)?
    public var onPlaybackEnded: (() -> Void)?
    public var onError: ((String) -> Void)?

    // MARK: - Video View

    /// The UIView that VLC renders into. Embed this in the SwiftUI hierarchy.
    public let videoView = UIView()

    // MARK: - Private

    private let stateMachine = PlaybackStateMachine()
    #if canImport(MobileVLCKit) || canImport(TVVLCKit)
    private var mediaPlayer: VLCMediaPlayer?
    private var delegate: VLCDelegateAdapter?
    #endif
    private var timeUpdateTimer: Timer?

    // MARK: - Init

    public init() {
        videoView.backgroundColor = .black
        stateMachine.onTransition = { [weak self] _, newState in
            self?.playbackState = newState
            self?.onStateChange?(newState)
        }
    }

    // MARK: - PlaybackEngineAdapter

    public func prepare(url: URL, headers: [String: String]) async throws {
        cleanup()
        stateMachine.transition(to: .preparing)

        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        let player = VLCMediaPlayer()
        player.drawable = videoView

        let media = VLCMedia(url: url)

        // Apply HTTP headers if needed
        if !headers.isEmpty {
            for (key, value) in headers {
                media.addOption("--http-header=\(key): \(value)")
            }
        }

        // Optimize for fast startup
        media.addOption("--network-caching=1500")
        media.addOption("--file-caching=1000")

        let adapter = VLCDelegateAdapter(engine: self)
        player.delegate = adapter

        self.mediaPlayer = player
        self.delegate = adapter

        player.media = media

        // Wait for media to be parsed (timeout: 10s)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            adapter.onMediaReady = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            adapter.onMediaError = { error in
                guard !resumed else { return }
                resumed = true
                continuation.resume(throwing: AppError.network(error))
            }

            // Trigger parse. VLCKit 3.7.x exposes the Objective-C parse entrypoint without Swift options.
            media.parse()

            // Also start play to trigger state changes (VLC needs play to detect tracks)
            player.play()

            // Timeout safety
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                guard !resumed else { return }
                resumed = true
                // Consider it ready even without explicit callback
                continuation.resume()
            }
        }

        stateMachine.transition(to: .ready)
        updateDuration()
        populateTracks()
        startTimeUpdateTimer()

        #else
        // VLCKit not available
        let message = "VLCKit is not linked. Install MobileVLCKit or TVVLCKit to enable VLC playback."
        errorMessage = message
        stateMachine.transition(to: .failed)
        throw AppError.network(message)
        #endif
    }

    public func play() {
        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        mediaPlayer?.play()
        #endif
        stateMachine.transition(to: .playing)
        isPlaying = true
    }

    public func pause() {
        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        mediaPlayer?.pause()
        #endif
        stateMachine.transition(to: .paused)
        isPlaying = false
    }

    public func seek(to seconds: TimeInterval) async {
        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        guard let player = mediaPlayer else { return }
        stateMachine.transition(to: .seeking)

        let targetMs = Int32(seconds * 1000)
        player.time = VLCTime(int: targetMs)

        // Small delay to let VLC process the seek
        try? await Task.sleep(nanoseconds: 100_000_000)

        if player.isPlaying {
            stateMachine.transition(to: .playing)
        } else {
            stateMachine.transition(to: .paused)
        }
        #endif
    }

    public func stop() {
        cleanup()
        stateMachine.forceState(.idle)
        isPlaying = false
        currentTime = 0
        duration = 0
        audioTracks = []
        subtitleTracks = []
    }

    public func selectAudioTrack(id: String) {
        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        guard let player = mediaPlayer, let index = Int32(id) else { return }
        player.currentAudioTrackIndex = index
        selectedAudioTrackID = id
        #endif
    }

    public func selectSubtitleTrack(id: String?) {
        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        guard let player = mediaPlayer else { return }
        if let id, let index = Int32(id) {
            player.currentVideoSubTitleIndex = index
            selectedSubtitleTrackID = id
        } else {
            player.currentVideoSubTitleIndex = -1
            selectedSubtitleTrackID = nil
        }
        #endif
    }

    public func setRate(_ rate: Float) {
        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        mediaPlayer?.rate = rate
        #endif
    }

    // MARK: - Private Helpers

    private func cleanup() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        mediaPlayer?.stop()
        mediaPlayer?.delegate = nil
        mediaPlayer = nil
        delegate = nil
        #endif
    }

    private func startTimeUpdateTimer() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollTimeAndState()
            }
        }
    }

    private func pollTimeAndState() {
        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        guard let player = mediaPlayer else { return }

        let timeMs = player.time.value?.intValue ?? 0
        let seconds = Double(timeMs) / 1000.0
        if seconds >= 0 {
            currentTime = seconds
            onTimeUpdate?(seconds)
        }

        // Update playing state
        isPlaying = player.isPlaying
        isBuffering = player.state == .buffering

        // Check for ended
        if player.state == .ended {
            stateMachine.transition(to: .ended)
            isPlaying = false
            onPlaybackEnded?()
            timeUpdateTimer?.invalidate()
        }

        // Check for error
        if player.state == .error {
            let msg = "VLC playback error"
            errorMessage = msg
            stateMachine.transition(to: .failed)
            onError?(msg)
            timeUpdateTimer?.invalidate()
        }
        #endif
    }

    private func updateDuration() {
        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        guard let player = mediaPlayer, let media = player.media else { return }
        let lengthMs = media.length.intValue
        if lengthMs > 0 {
            duration = Double(lengthMs) / 1000.0
        }
        #endif
    }

    private func populateTracks() {
        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        guard let player = mediaPlayer else { return }

        // Audio tracks
        let audioTrackNames = player.audioTrackNames as? [String] ?? []
        let audioTrackIndexes = player.audioTrackIndexes as? [NSNumber] ?? []
        audioTracks = zip(audioTrackNames, audioTrackIndexes).enumerated().compactMap { offset, pair in
            let (name, index) = pair
            let idx = index.int32Value
            guard idx >= 0 else { return nil } // skip "Disable" entry
            return UnifiedTrack(
                id: "\(idx)",
                title: name,
                language: nil,
                codec: nil,
                isDefault: offset == 0,
                index: Int(idx),
                engineSource: .vlc
            )
        }

        // Subtitle tracks
        let subTrackNames = player.videoSubTitlesNames as? [String] ?? []
        let subTrackIndexes = player.videoSubTitlesIndexes as? [NSNumber] ?? []
        subtitleTracks = zip(subTrackNames, subTrackIndexes).enumerated().compactMap { offset, pair in
            let (name, index) = pair
            let idx = index.int32Value
            guard idx >= 0 else { return nil } // skip "Disable" entry
            return UnifiedTrack(
                id: "\(idx)",
                title: name,
                language: nil,
                codec: nil,
                isDefault: offset == 0,
                index: Int(idx),
                engineSource: .vlc
            )
        }
        #endif
    }

    // MARK: - VLC State Mapping

    fileprivate func handleVLCStateChange() {
        #if canImport(MobileVLCKit) || canImport(TVVLCKit)
        guard let player = mediaPlayer else { return }

        switch player.state {
        case .opening:
            stateMachine.transition(to: .preparing)
        case .buffering:
            isBuffering = true
            if playbackState == .playing || playbackState == .preparing {
                stateMachine.transition(to: .buffering)
            }
        case .playing:
            isBuffering = false
            isPlaying = true
            stateMachine.transition(to: .playing)
        case .paused:
            isPlaying = false
            stateMachine.transition(to: .paused)
        case .stopped:
            isPlaying = false
            stateMachine.forceState(.idle)
        case .ended:
            isPlaying = false
            stateMachine.transition(to: .ended)
            onPlaybackEnded?()
        case .error:
            let msg = "VLC playback error"
            errorMessage = msg
            stateMachine.transition(to: .failed)
            onError?(msg)
        case .esAdded:
            // Tracks may have changed; re-enumerate
            populateTracks()
        @unknown default:
            break
        }
        #endif
    }
}

// MARK: - VLC Delegate Adapter

#if canImport(MobileVLCKit) || canImport(TVVLCKit)
private final class VLCDelegateAdapter: NSObject, VLCMediaPlayerDelegate {
    private weak var engine: VLCPlaybackEngine?
    var onMediaReady: (() -> Void)?
    var onMediaError: ((String) -> Void)?
    private var didNotifyReady = false

    init(engine: VLCPlaybackEngine) {
        self.engine = engine
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, let engine = self.engine else { return }
            engine.handleVLCStateChange()

            // Notify ready on first play or buffering state
            if !self.didNotifyReady {
                let state = engine.playbackState
                if state == .playing || state == .buffering || state == .ready {
                    self.didNotifyReady = true
                    self.onMediaReady?()
                }
            }
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        // Time updates handled by polling timer
    }
}
#endif
