import AVKit
import SwiftUI
#if os(tvOS)
import Shared
#endif

struct NativePlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer

#if os(tvOS)
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    var selectedAudioID: String?
    var selectedSubtitleID: String?
    var onSelectAudio: ((String) -> Void)?
    var onSelectSubtitle: ((String?) -> Void)?
#endif

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
#if os(tvOS)
        updateTransportBarMenu(controller: controller)
#endif
    }

#if os(tvOS)
    private func updateTransportBarMenu(controller: AVPlayerViewController) {
        guard audioTracks.count > 1 || !subtitleTracks.isEmpty else {
            controller.transportBarCustomMenuItems = []
            return
        }

        var menuItems: [UIMenuElement] = []

        if audioTracks.count > 1 {
            let audioActions: [UIAction] = audioTracks.map { track in
                let title = resolvedLanguageName(for: track)
                let isSelected = track.id == selectedAudioID
                let onSelect = onSelectAudio
                let trackID = track.id
                return UIAction(
                    title: title,
                    image: UIImage(systemName: "speaker.wave.2"),
                    state: isSelected ? .on : .off
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

        if !subtitleTracks.isEmpty {
            let noneSelected = selectedSubtitleID == nil
            let onSelectSub = onSelectSubtitle
            var subActions: [UIAction] = [
                UIAction(
                    title: "Aucun",
                    image: UIImage(systemName: "minus.circle"),
                    state: noneSelected ? .on : .off
                ) { _ in
                    Task { @MainActor in onSelectSub?(nil) }
                }
            ]
            subActions += subtitleTracks.map { track in
                let title = resolvedLanguageName(for: track)
                let isSelected = track.id == selectedSubtitleID
                let trackID = track.id
                return UIAction(
                    title: title,
                    image: UIImage(systemName: "captions.bubble"),
                    state: isSelected ? .on : .off
                ) { _ in
                    Task { @MainActor in onSelectSub?(trackID) }
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

    private func resolvedLanguageName(for track: MediaTrack) -> String {
        if let lang = track.language, !lang.isEmpty {
            let base = String(lang.prefix(2)).lowercased()
            if let localized = Locale.current.localizedString(forLanguageCode: base) {
                return localized
            }
        }
        return track.title.isEmpty ? "Piste \(track.index)" : track.title
    }
#endif

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
    final class Coordinator: NSObject {
        private var itemObservation: NSKeyValueObservation?
        private var statusObservation: NSKeyValueObservation?
        private weak var controller: AVPlayerViewController?
        private var didReattachForCurrentItem = false

        func startObserving(player: AVPlayer, controller: AVPlayerViewController) {
            self.controller = controller
            didReattachForCurrentItem = false
            statusObservation = nil

            itemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
                guard let self else { return }
                self.didReattachForCurrentItem = false
                self.observeItemStatus(player: player)
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
                self?.reattachIfNeeded(player: player)
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
    }
}
