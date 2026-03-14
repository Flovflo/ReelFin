import PlaybackEngine
import SwiftUI

struct PlayerSurfaceView: View {
    let session: HybridPlaybackSession

    var body: some View {
        if session.isNativeEngine, let player = session.nativePlayer {
            NativePlayerViewController(player: player)
                .ignoresSafeArea()
        } else if let vlcView = session.vlcVideoView {
            VLCVideoViewRepresentable(videoView: vlcView)
                .ignoresSafeArea()
        } else {
            NativePlayerViewController(player: session.player)
                .ignoresSafeArea()
        }
    }
}
