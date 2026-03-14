import PlaybackEngine
import Shared
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PlayerView: View {
    var session: HybridPlaybackSession
    let item: MediaItem
    let onDismiss: () -> Void
    @State private var presentedError: String?

    var body: some View {
#if os(tvOS)
        tvOSBody
#else
        iOSBody
#endif
    }

#if os(tvOS)
    private var tvOSBody: some View {
        NativePlayerViewController(player: session.player)
            .background(.black)
            .ignoresSafeArea()
            .accessibilityIdentifier("native_player_screen")
            .alert(
                "Playback Error",
                isPresented: Binding(
                    get: { presentedError != nil },
                    set: { if !$0 { presentedError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(presentedError ?? "Unknown error")
            }
            .onDisappear(perform: handleDisappear)
            .onChange(of: session.playbackErrorMessage) { _, newValue in
                presentedError = newValue
            }
            .onExitCommand(perform: dismissPlayer)
    }
#else
    private var iOSBody: some View {
        ZStack {
            PlayerSurfaceView(session: session)
            PlayerControlsOverlay(
                title: item.name,
                isPlaying: session.isPlaying,
                isBuffering: session.isBuffering,
                currentTime: session.currentTime,
                duration: session.duration,
                availableAudioTracks: session.availableAudioTracks,
                availableSubtitleTracks: session.availableSubtitleTracks,
                selectedAudioTrackID: session.selectedAudioTrackID,
                selectedSubtitleTrackID: session.selectedSubtitleTrackID,
                onBack: dismissPlayer,
                onPlayPause: togglePlayback,
                onSkipBackward: skipBackward,
                onSkipForward: skipForward,
                onSeek: seek,
                onSelectAudioTrack: session.selectAudioTrack,
                onSelectSubtitleTrack: session.selectSubtitleTrack
            )
        }
        .background(.black)
        .ignoresSafeArea()
        .accessibilityIdentifier("native_player_screen")
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { presentedError != nil },
                set: { if !$0 { presentedError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentedError ?? "Unknown error")
        }
        .onDisappear {
            handleDisappear()
        }
        .onAppear {
            handleAppear()
        }
        .onChange(of: session.playbackErrorMessage) { _, newValue in
            presentedError = newValue
        }
    }
#endif

    private func togglePlayback() {
        session.isPlaying ? session.pause() : session.play()
    }

    private func skipBackward() {
        let target = max(0, session.currentTime - 15)
        seek(to: target)
    }

    private func skipForward() {
        let target = min(session.duration, session.currentTime + 15)
        seek(to: target)
    }

    private func seek(to time: TimeInterval) {
        Task {
            await session.seek(to: time)
        }
    }

    private func dismissPlayer() {
        session.pause()
        onDismiss()
    }

    private func handleDisappear() {
        session.pause()
#if os(iOS)
        OrientationManager.shared.lock = .portrait
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
#endif
        onDismiss()
    }

    private func handleAppear() {
#if os(iOS)
        OrientationManager.shared.lock = .allButUpsideDown
#endif
    }
}
