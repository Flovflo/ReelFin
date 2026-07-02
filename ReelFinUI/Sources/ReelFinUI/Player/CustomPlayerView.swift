import AVKit
import PlaybackEngine
import SwiftUI

/// Full-screen host for the NEW custom playback engine (flag-gated). Shows `engine.player` and an
/// original-first LOADING BAR overlay while the deep cache is being built (pre-buffer / mid-play
/// buffer) — instead of a silent freeze or a quality drop. The legacy player path is untouched.
struct CustomPlayerView: View {
    let engine: CustomPlaybackEngine

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CustomPlayerSurface(player: engine.player, engine: engine)
                .ignoresSafeArea()
            if engine.bufferingState.phase != .failed {
                VStack {
                    cacheHUD
                    Spacer()
                }
                .padding(.top, 8)
            }
            overlay
        }
        .onAppear {
#if os(iOS)
            OrientationManager.shared.lockLandscapeForPlayerPresentation()
#endif
        }
        .onDisappear {
            // Picture in Picture outlives the view — only a real dismissal stops playback.
            if !engine.isPictureInPictureActive {
                engine.stop()
            }
#if os(iOS)
            OrientationManager.shared.restorePortraitAfterPlayerDismissal()
#endif
        }
    }

    @ViewBuilder
    private var overlay: some View {
        let state = engine.bufferingState
        if state.phase == .failed {
            // Honest, retryable error — the recovery ladder's last rung. Never a silent frozen frame.
            VStack(spacing: 14) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
                Text(engine.errorMessage ?? "La lecture a échoué.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Button {
                    engine.retry()
                } label: {
                    Label("Réessayer", systemImage: "arrow.clockwise")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        } else if state.isLoadingBarVisible {
            VStack(spacing: 12) {
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 240)
                    .tint(.white)
                Text(label(for: state))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(20)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        } else if let error = engine.errorMessage {
            Text(error)
                .font(.callout)
                .foregroundStyle(.white)
                .padding(16)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// Always-visible HUD: quality badge (the proof you're getting the original) + live reservoir.
    private var cacheHUD: some View {
        let seconds = Int(engine.bufferingState.reservoirSeconds.rounded())
        let fraction = min(1, engine.bufferingState.reservoirSeconds / 300) // bar spans ~5 min
        return HStack(spacing: 8) {
            if let badge = qualityBadge {
                Text(badge.text)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badge.tint.opacity(0.85), in: Capsule())
                    .foregroundStyle(.black)
            }
            Image(systemName: "internaldrive")
            Text("Cache \(seconds)s")
                .font(.caption.monospacedDigit())
            ProgressView(value: fraction)
                .frame(width: 90)
                .tint(.green)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.45), in: Capsule())
    }

    private var qualityBadge: (text: String, tint: Color)? {
        if engine.bufferingState.phase == .degradedSDR {
            return ("Qualité adaptée", .orange)
        }
        guard let label = engine.sourceQualityLabel else { return nil }
        return (label, .white)
    }

    private func label(for state: PlaybackBufferingState) -> String {
        let pct = Int((state.progress * 100).rounded())
        switch state.phase {
        case .prebuffering: return "Mise en cache de l’original… \(pct)%"
        case .buffering: return "Mise en mémoire tampon… \(pct)%"
        default: return ""
        }
    }
}

/// Minimal AVPlayerViewController host (iOS/tvOS). The custom engine owns the AVPlayer; the
/// delegate keeps the engine informed about Picture in Picture so teardown never kills it.
private struct CustomPlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    let engine: CustomPlaybackEngine

    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        private let engine: CustomPlaybackEngine
        init(engine: CustomPlaybackEngine) { self.engine = engine }

        nonisolated func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            Task { @MainActor in self.engine.isPictureInPictureActive = true }
        }

        nonisolated func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            Task { @MainActor in
                self.engine.isPictureInPictureActive = false
                // The hosting view is long gone when PiP ends detached — stop cleanly then.
                if playerViewController.viewIfLoaded?.window == nil {
                    self.engine.stop()
                }
            }
        }

        nonisolated func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }
    }
}
