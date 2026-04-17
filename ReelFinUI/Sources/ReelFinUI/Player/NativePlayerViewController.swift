import AVKit
import PlaybackEngine
import Shared
import SwiftUI
#if os(iOS) || os(tvOS)
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
#endif
#if os(iOS) || os(tvOS)
        context.coordinator.installTrickplayOverlayIfNeeded(in: controller)
        context.coordinator.updateTrickplayOverlay(
            manifest: transportState.trickplayManifest,
            timeOffsetSeconds: transportState.playbackTimeOffsetSeconds,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
#endif
#if os(iOS)
        context.coordinator.updateSkipOverlay(
            suggestion: transportState.activeSkipSuggestion,
            onSkipSuggestion: onSkipSuggestion
        )
#endif
        // Let AVPlayer auto-select audio and subtitle tracks according to the
        // device's language/accessibility settings. The native "···" button in
        // AVPlayerViewController then lets the user override at runtime without
        // any custom UI — it appears automatically whenever the asset exposes
        // ≥2 AVMediaSelectionOptions in the audible or legible group.
#if os(tvOS)
        // On tvOS we provide our own audio/subtitle menus via transportBarCustomMenuItems.
        // Disabling automatic criteria suppresses the duplicate native AVKit subtitle/audio
        // buttons that would otherwise appear alongside our custom menu items.
        controller.player?.appliesMediaSelectionCriteriaAutomatically = false
        context.coordinator.updateTransportBarMenu(
            in: controller,
            transportState: transportState,
            onSelectAudio: onSelectAudio,
            onSelectSubtitle: onSelectSubtitle,
            onSkipSuggestion: onSkipSuggestion
        )
#else
        controller.player?.appliesMediaSelectionCriteriaAutomatically = true
#endif

        context.coordinator.startObserving(player: player, controller: controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
#if os(tvOS)
            controller.player?.appliesMediaSelectionCriteriaAutomatically = false
#else
            controller.player?.appliesMediaSelectionCriteriaAutomatically = true
#endif
            context.coordinator.startObserving(player: player, controller: controller)
        }
#if os(iOS)
        context.coordinator.installSkipOverlayIfNeeded(in: controller)
        context.coordinator.updateSkipOverlay(
            suggestion: transportState.activeSkipSuggestion,
            onSkipSuggestion: onSkipSuggestion
        )
#endif
#if os(iOS) || os(tvOS)
        context.coordinator.installTrickplayOverlayIfNeeded(in: controller)
        context.coordinator.updateTrickplayOverlay(
            manifest: transportState.trickplayManifest,
            timeOffsetSeconds: transportState.playbackTimeOffsetSeconds,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
#endif
#if os(tvOS)
        context.coordinator.updateTransportBarMenu(
            in: controller,
            transportState: transportState,
            onSelectAudio: onSelectAudio,
            onSelectSubtitle: onSelectSubtitle,
            onSkipSuggestion: onSkipSuggestion
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
#if os(tvOS)
        private weak var lastTransportMenuController: AVPlayerViewController?
        private var lastTransportMenuModel: PlaybackControlsModel?
#endif
        private var itemObservation: NSKeyValueObservation?
        private var statusObservation: NSKeyValueObservation?
        private weak var controller: AVPlayerViewController?
        private weak var observedPlayer: AVPlayer?
#if os(iOS) || os(tvOS)
        private var timeJumpObserver: NSObjectProtocol?
        private var previewTimeObserver: Any?
        private let trickplayPreviewView = PlaybackTrickplayPreviewView()
#endif
#if os(iOS)
        private var didReattachForCurrentItem = false
        private var observedItemIdentifier: ObjectIdentifier?
        private var reattachGeneration: UInt = 0
        private var reattachWorkItem: DispatchWorkItem?
        private let skipOverlayView = PlaybackSkipOverlayView()
#endif

        deinit {
#if os(iOS)
            reattachWorkItem?.cancel()
#endif
#if os(iOS) || os(tvOS)
            if let timeJumpObserver {
                NotificationCenter.default.removeObserver(timeJumpObserver)
            }
            if let previewTimeObserver, let observedPlayer {
                observedPlayer.removeTimeObserver(previewTimeObserver)
            }
#endif
        }

#if os(tvOS)
        func updateTransportBarMenu(
            in controller: AVPlayerViewController,
            transportState: PlaybackTransportState,
            onSelectAudio: ((String) -> Void)?,
            onSelectSubtitle: ((String?) -> Void)?,
            onSkipSuggestion: (() -> Void)?
        ) {
            let controls = PlaybackControlsModel.make(
                audioTracks: transportState.availableAudioTracks,
                subtitleTracks: transportState.availableSubtitleTracks,
                selectedAudioID: transportState.selectedAudioTrackID,
                selectedSubtitleID: transportState.selectedSubtitleTrackID,
                skipSuggestion: transportState.activeSkipSuggestion
            )

            let sameController = lastTransportMenuController === controller
            guard !sameController || lastTransportMenuModel != controls else {
                return
            }

            lastTransportMenuController = controller
            lastTransportMenuModel = controls

            guard controls.hasSelectableTracks || controls.skipSuggestion != nil else {
                controller.transportBarCustomMenuItems = []
                return
            }

            var menuItems: [UIMenuElement] = []

            if let skipSuggestion = controls.skipSuggestion {
                menuItems.append(
                    UIAction(
                        title: skipSuggestion.title,
                        image: UIImage(systemName: skipSuggestion.systemImageName)
                    ) { _ in
                        Task { @MainActor in onSkipSuggestion?() }
                    }
                )
            }

            if !controls.audioOptions.isEmpty {
                let audioActions: [UIAction] = controls.audioOptions.compactMap { option in
                    guard let trackID = option.trackID else { return nil }
                    return UIAction(
                        title: option.title,
                        image: UIImage(systemName: "speaker.wave.2"),
                        state: option.isSelected ? .on : .off
                    ) { _ in
                        Task { @MainActor in onSelectAudio?(trackID) }
                    }
                }
                menuItems.append(UIMenu(
                    title: "Audio",
                    image: UIImage(systemName: "speaker.wave.2"),
                    options: .singleSelection,
                    children: audioActions
                ))
            }

            if !controls.subtitleOptions.isEmpty {
                let subActions: [UIAction] = controls.subtitleOptions.map { option in
                    UIAction(
                        title: option.title,
                        image: UIImage(systemName: option.iconName ?? "captions.bubble"),
                        state: option.isSelected ? .on : .off
                    ) { _ in
                        Task { @MainActor in onSelectSubtitle?(option.trackID) }
                    }
                }
                menuItems.append(UIMenu(
                    title: "Sous-titres",
                    image: UIImage(systemName: "captions.bubble"),
                    options: .singleSelection,
                    children: subActions
                ))
            }

            controller.transportBarCustomMenuItems = menuItems
        }
#endif

        func startObserving(player: AVPlayer, controller: AVPlayerViewController) {
            self.controller = controller
#if os(iOS)
            reattachWorkItem?.cancel()
            didReattachForCurrentItem = false
            observedItemIdentifier = player.currentItem.map(ObjectIdentifier.init)
            statusObservation = nil
#endif
#if os(iOS) || os(tvOS)
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
#if os(iOS)
                    self.reattachWorkItem?.cancel()
                    self.didReattachForCurrentItem = false
                    self.observedItemIdentifier = player.currentItem.map(ObjectIdentifier.init)
                    self.observeItemStatus(player: player)
#endif
                    self.observeTimeJumps(player: player)
                }
            }

            if player.currentItem != nil {
                observeTimeJumps(player: player)
#if os(iOS)
                observeItemStatus(player: player)
#endif
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

#if os(iOS) || os(tvOS)
        private static func normalizedDurationSeconds(for item: AVPlayerItem?) -> Double {
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
#endif

#if os(iOS)
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
            reattachGeneration &+= 1
            let generation = reattachGeneration

            DispatchQueue.main.async {
                // Detach and re-attach the player to force AVPlayerViewController
                // to fully re-initialize its internal video rendering pipeline (XPC).
                controller.player = nil
                let workItem = DispatchWorkItem { [weak self, weak controller, weak item] in
                    guard let self, let controller, let item else { return }
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

        func updateSkipOverlay(
            suggestion: PlaybackSkipSuggestion?,
            onSkipSuggestion: (() -> Void)?
        ) {
            skipOverlayView.update(
                suggestion: suggestion,
                onSkipSuggestion: onSkipSuggestion
            )
        }
#endif

#if os(iOS) || os(tvOS)
        func installTrickplayOverlayIfNeeded(in controller: AVPlayerViewController) {
            guard trickplayPreviewView.superview == nil else { return }
            let overlayView = controller.contentOverlayView ?? controller.view!
            overlayView.addSubview(trickplayPreviewView)
            NSLayoutConstraint.activate([
                trickplayPreviewView.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
                trickplayPreviewView.centerYAnchor.constraint(equalTo: overlayView.safeAreaLayoutGuide.centerYAnchor, constant: -28)
            ])
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
