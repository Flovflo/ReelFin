import AVKit
import PlaybackEngine
import Shared
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct NativePlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    var selectedAudioID: String?
    var selectedSubtitleID: String?
    var onSelectAudio: ((String) -> Void)?
    var onSelectSubtitle: ((String?) -> Void)?
    var skipSuggestion: PlaybackSkipSuggestion?
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
        context.coordinator.updateSkipOverlay(
            suggestion: skipSuggestion,
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
        updateTransportBarMenu(controller: controller)
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
            suggestion: skipSuggestion,
            onSkipSuggestion: onSkipSuggestion
        )
#endif
#if os(tvOS)
        updateTransportBarMenu(controller: controller)
#endif
    }

#if os(tvOS)
    private func updateTransportBarMenu(controller: AVPlayerViewController) {
        let controls = controlsModel
        guard controls.hasSelectableTracks || controls.skipSuggestion != nil else {
            controller.transportBarCustomMenuItems = []
            return
        }

        var menuItems: [UIMenuElement] = []

        if let skipSuggestion = controls.skipSuggestion {
            let onSkip = onSkipSuggestion
            menuItems.append(
                UIAction(
                    title: skipSuggestion.title,
                    image: UIImage(systemName: skipSuggestion.systemImageName)
                ) { _ in
                    Task { @MainActor in onSkip?() }
                }
            )
        }

        if !controls.audioOptions.isEmpty {
            let audioActions: [UIAction] = controls.audioOptions.compactMap { option in
                let onSelect = onSelectAudio
                guard let trackID = option.trackID else { return nil }
                return UIAction(
                    title: option.title,
                    image: UIImage(systemName: "speaker.wave.2"),
                    state: option.isSelected ? .on : .off
                ) { _ in
                    Task { @MainActor in onSelect?(trackID) }
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
            let onSelectSub = onSelectSubtitle
            let subActions: [UIAction] = controls.subtitleOptions.map { option in
                return UIAction(
                    title: option.title,
                    image: UIImage(systemName: option.iconName ?? "captions.bubble"),
                    state: option.isSelected ? .on : .off
                ) { _ in
                    Task { @MainActor in onSelectSub?(option.trackID) }
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

    private var controlsModel: PlaybackControlsModel {
        PlaybackControlsModel.make(
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            selectedAudioID: selectedAudioID,
            selectedSubtitleID: selectedSubtitleID,
            skipSuggestion: skipSuggestion
        )
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
        private var didReattachForCurrentItem = false
#if os(iOS)
        private let skipOverlayView = PlaybackSkipOverlayView()
#endif

        func startObserving(player: AVPlayer, controller: AVPlayerViewController) {
            self.controller = controller
            didReattachForCurrentItem = false
            statusObservation = nil

            itemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.didReattachForCurrentItem = false
                    self.observeItemStatus(player: player)
                }
            }

            // If there's already a current item, observe it immediately.
            if player.currentItem != nil {
                observeItemStatus(player: player)
            }
        }

        private func observeItemStatus(player: AVPlayer) {
            statusObservation = nil
            guard let item = player.currentItem else { return }

            // If item is already ready, reattach immediately.
            if item.status == .readyToPlay {
                reattachIfNeeded(player: player)
                return
            }

            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .readyToPlay else { return }
                Task { @MainActor in
                    self?.reattachIfNeeded(player: player)
                }
            }
        }

        private func reattachIfNeeded(player: AVPlayer) {
            guard !didReattachForCurrentItem else { return }
            didReattachForCurrentItem = true
            let controller = self.controller

            DispatchQueue.main.async {
                guard let controller else { return }
                // Detach and re-attach the player to force AVPlayerViewController
                // to fully re-initialize its internal video rendering pipeline (XPC).
                let rate = player.rate
                controller.player = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak controller] in
                    guard let controller else { return }
                    controller.player = player
                    if rate > 0 {
                        player.play()
                    }
                }
            }
        }

#if os(iOS)
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
    }
}
