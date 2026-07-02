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
                    HStack(alignment: .top) {
                        cacheHUD
                        Spacer()
                        subtitlePicker
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
            }
            subtitleCueOverlay
            skipOverlay
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

    /// External-subtitle cue rendered by the player itself (sidecar SRT/VTT — AVFoundation can't
    /// inject text tracks into a progressive asset). Bottom-centered, TV-readable.
    @ViewBuilder
    private var subtitleCueOverlay: some View {
        if let cue = engine.subtitles.currentCue, !cue.isEmpty {
            VStack {
                Spacer()
                Text(cue)
                    .font(.system(size: 34, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 72)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Skip intro/credits + next-episode suggestion (same resolver as the rest of the app).
    @ViewBuilder
    private var skipOverlay: some View {
        if let suggestion = engine.activeSkipSuggestion {
            VStack {
                Spacer()
                HStack {
                    Spacer()
#if os(iOS)
                    PlaybackSkipButton(suggestion: suggestion) {
                        engine.skipCurrentSegment()
                    }
#else
                    Button {
                        engine.skipCurrentSegment()
                    } label: {
                        Label(suggestion.title, systemImage: "forward.frame.fill")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 26)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.9))
                    .foregroundStyle(.black)
#endif
                }
                .padding(.trailing, 48)
                .padding(.bottom, 96)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// External subtitle track picker — only shown when the source actually has sidecar tracks.
    @ViewBuilder
    private var subtitlePicker: some View {
        if !engine.subtitles.availableTracks.isEmpty {
            Menu {
                Button {
                    engine.subtitles.select(trackID: nil)
                } label: {
                    Label("Désactivés", systemImage: engine.subtitles.activeTrackID == nil ? "checkmark" : "captions.bubble")
                }
                ForEach(engine.subtitles.availableTracks) { track in
                    Button {
                        engine.subtitles.select(trackID: track.id)
                    } label: {
                        Label(track.label, systemImage: engine.subtitles.activeTrackID == track.id ? "checkmark" : "captions.bubble")
                    }
                }
            } label: {
                Image(systemName: engine.subtitles.activeTrackID == nil ? "captions.bubble" : "captions.bubble.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.45), in: Circle())
            }
        }
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
