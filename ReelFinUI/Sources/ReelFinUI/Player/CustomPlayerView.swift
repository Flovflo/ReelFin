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
            engine.stop()
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

    /// Always-visible cache HUD so you can watch the deep buffer build in real time. Green bar +
    /// seconds of the original cached ahead of the playhead (updates every second).
    private var cacheHUD: some View {
        let seconds = Int(engine.bufferingState.reservoirSeconds.rounded())
        let fraction = min(1, engine.bufferingState.reservoirSeconds / 300) // bar spans ~5 min
        return HStack(spacing: 8) {
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
