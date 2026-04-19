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
    @State private var isTrackPickerPresented = false

    private var controls: PlaybackControlsModel {
        PlaybackControlsModel.make(
            audioTracks: session.transportState.availableAudioTracks,
            subtitleTracks: session.transportState.availableSubtitleTracks,
            selectedAudioID: session.transportState.selectedAudioTrackID,
            selectedSubtitleID: session.transportState.selectedSubtitleTrackID,
            skipSuggestion: session.transportState.activeSkipSuggestion
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            NativePlayerViewController(
                player: session.player,
                transportState: session.transportState,
                apiClient: apiClient,
                imagePipeline: imagePipeline,
                onSkipSuggestion: { session.skipCurrentSegment() }
            )
            .ignoresSafeArea()

            if controls.hasSelectableTracks {
                PlayerTrackPickerButton {
                    isTrackPickerPresented = true
                }
                .padding(.top, 18)
                .padding(.trailing, 18)
            }
        }
        .accessibilityIdentifier("native_player_screen")
        .sheet(isPresented: $isTrackPickerPresented) {
            TrackPickerView(controls: controls) { selection in
                switch selection {
                case .audio(let id):
                    session.selectAudioTrack(id: id)
                case .subtitle(let id):
                    session.selectSubtitleTrack(id: id)
                }
            }
        }
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

private struct PlayerTrackPickerButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "captions.bubble")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial, in: Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .accessibilityLabel("Pistes audio et sous-titres")
        .accessibilityIdentifier("player_track_picker_button")
#if os(macOS)
        .help("Pistes audio et sous-titres")
#endif
    }
}
