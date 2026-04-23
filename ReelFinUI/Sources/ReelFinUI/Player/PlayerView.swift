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

            NativePlayerViewController(
                player: session.player,
                transportState: session.transportState,
                apiClient: apiClient,
                imagePipeline: imagePipeline,
                onSkipSuggestion: { session.skipCurrentSegment() }
            )
            .ignoresSafeArea()
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
