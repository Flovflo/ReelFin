import PlaybackEngine
import Shared
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PlayerView: View {
    var session: PlaybackSessionController
    let item: MediaItem

#if os(iOS)
    @State private var showingTrackPicker = false

    /// Whether the track picker button should be offered.
    /// We show it whenever there is more than one audio track
    /// or at least one subtitle track available.
    private var hasSelectableTracks: Bool {
        session.availableAudioTracks.count > 1 || !session.availableSubtitleTracks.isEmpty
    }
#endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

#if os(tvOS)
            // AVPlayerViewController on tvOS exposes audio and subtitle selection
            // natively through transportBarCustomMenuItems. Track data is passed
            // directly so the menus rebuild whenever the session state changes.
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
#else
            // AVPlayerViewController — native controls handle PiP, AirPlay, and scrubbing.
            NativePlayerViewController(player: session.player)
            .ignoresSafeArea()

            // Track-picker button — shown only when language/subtitle selection is meaningful.
            // Positioned at the top-leading corner, above AVKit's standard transport overlay,
            // so it doesn't collide with the native Done / AirPlay buttons at top-trailing.
            if hasSelectableTracks {
                VStack {
                    HStack {
                        Button {
                            showingTrackPicker = true
                        } label: {
                            Label("Pistes", systemImage: "text.bubble")
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .padding(.leading, 20)
                        .padding(.top, 20)
                        Spacer()
                    }
                    Spacer()
                }
            }

            if let skipSuggestion = session.activeSkipSuggestion {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            session.skipCurrentSegment()
                        } label: {
                            Label(skipSuggestion.title, systemImage: skipSuggestion.systemImageName)
                                .font(.callout.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 20)
                        Spacer()
                    }
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
#endif
        }
        .accessibilityIdentifier("native_player_screen")
#if os(iOS)
        .sheet(isPresented: $showingTrackPicker) {
            TrackPickerView(session: session)
        }
#endif
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
