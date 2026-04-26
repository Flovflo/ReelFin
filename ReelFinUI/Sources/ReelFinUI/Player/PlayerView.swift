import PlaybackEngine
import Shared
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PlayerView: View {
    var session: PlaybackSessionController
    let item: MediaItem
    let apiClient: JellyfinAPIClientProtocol
    let imagePipeline: ImagePipelineProtocol

    var body: some View {
        ZStack {
            if !usesNativeSampleBufferPlayer {
                Color.black.ignoresSafeArea()
            }

            if usesNativeSampleBufferPlayer {
                NativePlayerView(
                    playbackURL: session.nativePlayerPlaybackURL,
                    playbackHeaders: session.nativePlayerPlaybackHeaders,
                    startTimeSeconds: session.nativePlayerStartTimeSeconds,
                    item: item,
                    diagnostics: session.nativePlayerDiagnosticsOverlayLines,
                    errorMessage: session.playbackErrorMessage,
                    transportState: session.transportState,
                    onSelectTrack: handleNativePlaybackControlSelection,
                    onPlaybackTime: { session.updateNativePlayerPlaybackTime($0) }
                )
            } else {
                NativePlayerViewController(
                    player: session.player,
                    transportState: session.transportState,
                    apiClient: apiClient,
                    imagePipeline: imagePipeline,
                    onSkipSuggestion: { session.skipCurrentSegment() },
                    onReadyForDisplay: { session.markAVKitReadyForDisplay() }
                )
                .ignoresSafeArea()
            }

#if canImport(UIKit)
            PlayerScreenAccessibilityAnchor()
                .frame(width: 1, height: 1)
#endif
        }
        .accessibilityIdentifier("native_player_screen")
        .onDisappear {
#if os(iOS)
            OrientationManager.shared.restorePortraitAfterPlayerDismissal(requestGeometryUpdate: false)
#endif
        }
        .onAppear {
#if os(iOS)
            OrientationManager.shared.lockLandscapeForPlayerPresentation()
#endif
        }
    }

    private var usesNativeSampleBufferPlayer: Bool {
        session.isNativePlayerActive
            && session.nativePlayerPlaybackSurface == .sampleBuffer
    }

    private func handleNativePlaybackControlSelection(_ selection: PlaybackControlSelection) {
        switch selection {
        case .audio(let id):
            session.selectAudioTrack(id: id)
        case .subtitle(let id):
            session.selectSubtitleTrack(id: id)
        }
    }
}

#if canImport(UIKit)
private struct PlayerScreenAccessibilityAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "native_player_screen"
        view.accessibilityLabel = "Player"
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.accessibilityIdentifier = "native_player_screen"
        view.accessibilityLabel = "Player"
    }
}
#endif
