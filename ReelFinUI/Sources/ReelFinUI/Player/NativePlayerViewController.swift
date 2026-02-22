import AVKit
import SwiftUI

struct NativePlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        // Already presented full-screen by SwiftUI; avoid nested full-screen transitions.
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
#if os(iOS)
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = false
#endif
        context.coordinator.startObserving(player: player, controller: controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
            context.coordinator.startObserving(player: player, controller: controller)
        }
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

            DispatchQueue.main.async { [weak self] in
                guard let self, let controller = self.controller else { return }
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
