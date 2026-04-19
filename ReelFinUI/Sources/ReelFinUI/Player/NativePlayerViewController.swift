import AVKit
import PlaybackEngine
import Shared
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct NativePlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer
    var transportState: PlaybackTransportState = .empty
    let apiClient: JellyfinAPIClientProtocol
    let imagePipeline: ImagePipelineProtocol
    var onSelectAudio: ((String) -> Void)?
    var onSelectSubtitle: ((String?) -> Void)?
    var onSkipSuggestion: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
#if os(iOS)
        // Already presented full-screen by SwiftUI; avoid nested full-screen transitions.
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        context.coordinator.installSkipOverlayIfNeeded(in: controller)
        context.coordinator.installTrickplayOverlayIfNeeded(in: controller)
        context.coordinator.updateSkipOverlay(
            suggestion: transportState.activeSkipSuggestion,
            onSkipSuggestion: onSkipSuggestion
        )
        context.coordinator.updateTrickplayOverlay(
            manifest: transportState.trickplayManifest,
            timeOffsetSeconds: transportState.playbackTimeOffsetSeconds,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
#endif
        // Let AVPlayer auto-select audio/subtitle tracks and expose them through
        // AVKit's native controls. tvOS gets noisy if we add duplicate custom
        // transport-bar menus on top of the system media selection buttons.
        controller.player?.appliesMediaSelectionCriteriaAutomatically = true

        context.coordinator.startObserving(player: player, controller: controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        let shouldAssignPlayer: Bool
#if os(iOS)
        shouldAssignPlayer = !context.coordinator.shouldDeferPlayerAssignment(
            to: player,
            controller: controller
        )
#else
        shouldAssignPlayer = true
#endif

        if shouldAssignPlayer, controller.player !== player {
            controller.player = player
            controller.player?.appliesMediaSelectionCriteriaAutomatically = true
            context.coordinator.startObserving(player: player, controller: controller)
        }
#if os(iOS)
        context.coordinator.installSkipOverlayIfNeeded(in: controller)
        context.coordinator.installTrickplayOverlayIfNeeded(in: controller)
        context.coordinator.updateSkipOverlay(
            suggestion: transportState.activeSkipSuggestion,
            onSkipSuggestion: onSkipSuggestion
        )
        context.coordinator.updateTrickplayOverlay(
            manifest: transportState.trickplayManifest,
            timeOffsetSeconds: transportState.playbackTimeOffsetSeconds,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
#endif
    }

    // MARK: - Coordinator

    /// Observes AVPlayer's currentItem and its status to force AVPlayerViewController
    /// to re-attach its video rendering surface when the item becomes ready.
    ///
    /// This resolves the classic iOS race condition where AVPlayerViewController is
    /// created inside a SwiftUI fullScreenCover with an empty AVPlayer, and the
    /// AVPlayerItem is loaded asynchronously seconds later (e.g., waiting for a
    /// server-side HLS transcode). Without this re-attachment, the internal
    /// PlayerRemoteXPC process fails to connect to the late-arriving video track,
    /// resulting in a black screen with working audio.
    @MainActor
    final class Coordinator: NSObject {
        private var itemObservation: NSKeyValueObservation?
        private var statusObservation: NSKeyValueObservation?
        private weak var controller: AVPlayerViewController?
        private weak var observedPlayer: AVPlayer?
#if os(iOS)
        private var timeJumpObserver: NSObjectProtocol?
        private var didReattachForCurrentItem = false
        private var isTemporarilyDetachedForReattach = false
        private var observedItemIdentifier: ObjectIdentifier?
        private var reattachGeneration: UInt = 0
        private var reattachWorkItem: DispatchWorkItem?
        private var previewTimeObserver: Any?
        private let skipOverlayView = PlaybackSkipOverlayView()
        private let trickplayPreviewView = PlaybackTrickplayPreviewView()
#endif

        deinit {
#if os(iOS)
            reattachWorkItem?.cancel()
            if let timeJumpObserver {
                NotificationCenter.default.removeObserver(timeJumpObserver)
            }
            if let previewTimeObserver, let observedPlayer {
                observedPlayer.removeTimeObserver(previewTimeObserver)
            }
#endif
        }

        func startObserving(player: AVPlayer, controller: AVPlayerViewController) {
            self.controller = controller
            #if os(iOS)
            reattachWorkItem?.cancel()
            isTemporarilyDetachedForReattach = false
            didReattachForCurrentItem = false
            observedItemIdentifier = player.currentItem.map(ObjectIdentifier.init)
            statusObservation = nil
            if let timeJumpObserver {
                NotificationCenter.default.removeObserver(timeJumpObserver)
                self.timeJumpObserver = nil
            }
            if let previewTimeObserver, let observedPlayer {
                observedPlayer.removeTimeObserver(previewTimeObserver)
                self.previewTimeObserver = nil
            }
            self.observedPlayer = player

            itemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.reattachWorkItem?.cancel()
                    self.isTemporarilyDetachedForReattach = false
                    self.didReattachForCurrentItem = false
                    self.observedItemIdentifier = player.currentItem.map(ObjectIdentifier.init)
                    self.observeTimeJumps(player: player)
                    self.observeItemStatus(player: player)
                }
            }

            // If there's already a current item, observe it immediately.
            if player.currentItem != nil {
                observeTimeJumps(player: player)
                observeItemStatus(player: player)
            }

            previewTimeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.15, preferredTimescale: 600),
                queue: .main
            ) { [weak self, weak player] time in
                guard let self, let player else { return }
                let durationSeconds = Self.normalizedDurationSeconds(for: player.currentItem)
                Task { @MainActor in
                    self.trickplayPreviewView.handleObservedTimeChange(
                        seconds: max(0, time.seconds),
                        isPlaying: player.timeControlStatus == .playing,
                        durationSeconds: durationSeconds
                    )
                }
            }
            #endif
        }

#if os(iOS)
        nonisolated static func shouldDeferPlayerAssignmentDuringReattach(
            isTemporarilyDetachedForReattach: Bool,
            controllerPlayerIsNil: Bool,
            observedPlayerMatches: Bool
        ) -> Bool {
            isTemporarilyDetachedForReattach
                && controllerPlayerIsNil
                && observedPlayerMatches
        }

        func shouldDeferPlayerAssignment(
            to player: AVPlayer,
            controller: AVPlayerViewController
        ) -> Bool {
            Self.shouldDeferPlayerAssignmentDuringReattach(
                isTemporarilyDetachedForReattach: isTemporarilyDetachedForReattach,
                controllerPlayerIsNil: controller.player == nil,
                observedPlayerMatches: observedPlayer === player
            )
        }

        nonisolated private static func normalizedDurationSeconds(for item: AVPlayerItem?) -> Double {
            guard let seconds = item?.duration.seconds, seconds.isFinite, seconds > 0 else {
                return 0
            }
            return seconds
        }

        private func observeTimeJumps(player: AVPlayer) {
            if let timeJumpObserver {
                NotificationCenter.default.removeObserver(timeJumpObserver)
                self.timeJumpObserver = nil
            }

            guard let item = player.currentItem else { return }
            timeJumpObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemTimeJumped,
                object: item,
                queue: .main
            ) { [weak self, weak player] _ in
                guard let self, let player else { return }
                let durationSeconds = Self.normalizedDurationSeconds(for: player.currentItem)
                self.trickplayPreviewView.handleTimeJump(
                    seconds: max(0, player.currentTime().seconds),
                    isPlaying: player.timeControlStatus == .playing,
                    durationSeconds: durationSeconds
                )
            }
        }

        private func observeItemStatus(player: AVPlayer) {
            statusObservation = nil
            guard let item = player.currentItem else {
                observedItemIdentifier = nil
                return
            }

            observedItemIdentifier = ObjectIdentifier(item)

            // If item is already ready, reattach immediately.
            if item.status == .readyToPlay {
                reattachIfNeeded(player: player, item: item)
                return
            }

            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .readyToPlay else { return }
                Task { @MainActor in
                    self?.reattachIfNeeded(player: player, item: item)
                }
            }
        }

        private func reattachIfNeeded(player: AVPlayer, item: AVPlayerItem) {
            guard !didReattachForCurrentItem else { return }
            guard observedItemIdentifier == ObjectIdentifier(item) else { return }
            guard let controller else { return }
            didReattachForCurrentItem = true
            reattachWorkItem?.cancel()
            isTemporarilyDetachedForReattach = false
            reattachGeneration &+= 1
            let generation = reattachGeneration

            DispatchQueue.main.async { [weak self, weak controller, weak item] in
                guard let self, let controller, let item else { return }
                guard self.reattachGeneration == generation else { return }
                guard self.observedItemIdentifier == ObjectIdentifier(item) else { return }
                guard player.currentItem === item else { return }

                // Detach and re-attach the player to force AVPlayerViewController
                // to fully re-initialize its internal video rendering pipeline (XPC).
                self.isTemporarilyDetachedForReattach = true
                controller.player = nil
                let workItem = DispatchWorkItem { [weak self, weak controller, weak item] in
                    guard let self, let controller, let item else { return }
                    defer {
                        self.isTemporarilyDetachedForReattach = false
                        self.reattachWorkItem = nil
                    }
                    guard self.reattachGeneration == generation else { return }
                    guard self.observedItemIdentifier == ObjectIdentifier(item) else { return }
                    guard player.currentItem === item else { return }
                    controller.player = player
                    if PlaybackResumePolicy.shouldResumeAfterControllerReattach(
                        playerRate: player.rate,
                        timeControlStatus: player.timeControlStatus
                    ) {
                        player.play()
                    }
                }
                self.reattachWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
            }
        }

        func installSkipOverlayIfNeeded(in controller: AVPlayerViewController) {
            guard skipOverlayView.superview == nil else { return }
            let overlayView = controller.contentOverlayView ?? controller.view!
            overlayView.addSubview(skipOverlayView)
            NSLayoutConstraint.activate([
                skipOverlayView.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor),
                skipOverlayView.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor),
                skipOverlayView.topAnchor.constraint(equalTo: overlayView.topAnchor),
                skipOverlayView.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor)
            ])
        }

        func installTrickplayOverlayIfNeeded(in controller: AVPlayerViewController) {
            guard trickplayPreviewView.superview == nil else { return }
            let overlayView = controller.contentOverlayView ?? controller.view!
            overlayView.addSubview(trickplayPreviewView)
            NSLayoutConstraint.activate([
                trickplayPreviewView.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
                trickplayPreviewView.bottomAnchor.constraint(equalTo: overlayView.safeAreaLayoutGuide.bottomAnchor, constant: -110)
            ])
        }

        func updateSkipOverlay(
            suggestion: PlaybackSkipSuggestion?,
            onSkipSuggestion: (() -> Void)?
        ) {
            skipOverlayView.update(
                suggestion: suggestion,
                onSkipSuggestion: onSkipSuggestion
            )
        }

        func updateTrickplayOverlay(
            manifest: TrickplayManifest?,
            timeOffsetSeconds: Double,
            apiClient: JellyfinAPIClientProtocol,
            imagePipeline: ImagePipelineProtocol
        ) {
            trickplayPreviewView.update(
                manifest: manifest,
                timeOffsetSeconds: timeOffsetSeconds,
                apiClient: apiClient,
                imagePipeline: imagePipeline
            )
        }
#endif
    }
}
