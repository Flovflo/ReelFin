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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Engine-agnostic video surface:
            // Native AVPlayer → AVPlayerViewController
            // VLC → UIView wrapper (transparent to user)
            if session.isNativeEngine, let player = session.nativePlayer {
                NativePlayerViewController(player: player)
                    .ignoresSafeArea()
            } else if let vlcView = session.vlcVideoView {
                VLCVideoViewRepresentable(videoView: vlcView)
                    .ignoresSafeArea()
            } else {
                // Fallback: native player with whatever AVPlayer is available
                NativePlayerViewController(player: session.player)
                    .ignoresSafeArea()
            }
        }
        .accessibilityIdentifier("native_player_screen")
        .onDisappear {
            session.pause()
#if os(iOS)
            OrientationManager.shared.lock = .portrait
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
#endif
            onDismiss()
        }
        .onAppear {
#if os(iOS)
            OrientationManager.shared.lock = .allButUpsideDown
#endif
        }
    }
}

// MARK: - VLC Video View Representable

/// Wraps VLCKit's UIView drawable into SwiftUI.
/// The user sees no difference from the native player.
private struct VLCVideoViewRepresentable: UIViewRepresentable {
    let videoView: UIView

    func makeUIView(context: Context) -> UIView {
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return videoView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
