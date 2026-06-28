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
            CustomPlayerSurface(player: engine.player)
                .ignoresSafeArea()
            overlay
        }
        .onAppear {
#if os(iOS)
            OrientationManager.shared.lockLandscapeForPlayerPresentation()
#endif
        }
        .onDisappear {
            engine.stop()
#if os(iOS)
            OrientationManager.shared.restorePortraitAfterPlayerDismissal()
#endif
        }
    }

    @ViewBuilder
    private var overlay: some View {
        let state = engine.bufferingState
        if state.isLoadingBarVisible {
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

    private func label(for state: PlaybackBufferingState) -> String {
        let pct = Int((state.progress * 100).rounded())
        switch state.phase {
        case .prebuffering: return "Mise en cache de l’original… \(pct)%"
        case .buffering: return "Mise en mémoire tampon… \(pct)%"
        default: return ""
        }
    }
}

/// Minimal AVPlayerViewController host (iOS/tvOS). The custom engine owns the AVPlayer.
private struct CustomPlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
