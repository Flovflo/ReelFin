import PlaybackEngine
import Shared
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PlayerView: View {
    var session: PlaybackSessionController
    let item: MediaItem
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Native iOS/tvOS player controls (scrubber, audio/subtitle menu, PiP, AirPlay).
            NativePlayerViewController(player: session.player)
                .ignoresSafeArea()
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
