import PlaybackEngine
import Shared
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PlayerView: View {
    var session: PlaybackSessionController
    let item: MediaItem

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            NativePlayerViewController(
                player: session.player,
                audioTracks: session.availableAudioTracks,
                subtitleTracks: session.availableSubtitleTracks,
                selectedAudioID: session.selectedAudioTrackID,
                selectedSubtitleID: session.selectedSubtitleTrackID,
                onSelectAudio: { id in session.selectAudioTrack(id: id) },
                onSelectSubtitle: { id in session.selectSubtitleTrack(id: id) },
                skipSuggestion: session.activeSkipSuggestion,
                onSkipSuggestion: { session.skipCurrentSegment() }
            )
            .ignoresSafeArea()
        }
        .accessibilityIdentifier("native_player_screen")
        .onDisappear {
            session.stop()
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
