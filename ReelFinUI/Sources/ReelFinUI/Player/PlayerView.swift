import PlaybackEngine
import Shared
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PlayerView: View {
    var session: PlaybackSessionController
    let item: MediaItem
    let apiClient: JellyfinAPIClientProtocol
    let imagePipeline: ImagePipelineProtocol

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if session.isNativeVLCClassPlayerActive {
                NativeVLCPlayerView(
                    playbackURL: session.nativeVLCPlaybackURL,
                    playbackHeaders: session.nativeVLCPlaybackHeaders,
                    startTimeSeconds: session.nativeVLCStartTimeSeconds,
                    item: item,
                    diagnostics: session.nativeVLCDiagnosticsOverlayLines,
                    errorMessage: session.playbackErrorMessage,
                    onPlaybackTime: { session.updateNativeVLCPlaybackTime($0) }
                )
            } else {
                NativePlayerViewController(
                    player: session.player,
                    transportState: session.transportState,
                    apiClient: apiClient,
                    imagePipeline: imagePipeline,
                    onSkipSuggestion: { session.skipCurrentSegment() }
                )
                .ignoresSafeArea()
            }
        }
        .accessibilityIdentifier("native_player_screen")
        .onDisappear {
#if os(iOS)
            OrientationManager.shared.lock = .portrait
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
#endif
        }
        .onAppear {
#if os(iOS)
            OrientationManager.shared.lock = .allButUpsideDown
#endif
        }
    }
}
