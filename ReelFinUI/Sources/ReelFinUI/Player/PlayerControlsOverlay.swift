import Shared
import SwiftUI

struct PlayerControlsOverlay: View {
    let title: String
    let isPlaying: Bool
    let isBuffering: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let availableAudioTracks: [MediaTrack]
    let availableSubtitleTracks: [MediaTrack]
    let selectedAudioTrackID: String?
    let selectedSubtitleTrackID: String?
    let onBack: () -> Void
    let onPlayPause: () -> Void
    let onSkipBackward: () -> Void
    let onSkipForward: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onSelectAudioTrack: (String) -> Void
    let onSelectSubtitleTrack: (String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomPanel
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 34)
        .foregroundStyle(.white)
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            playerButton(title: "Back", systemImage: "chevron.backward", action: onBack)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                if isBuffering {
                    Text("Loading video…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            Spacer()
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            PlayerTimelineView(
                currentTime: currentTime,
                duration: duration,
                onSeek: onSeek
            )

            HStack(spacing: 16) {
                playerButton(title: "Back 15 Seconds", systemImage: "gobackward.15", action: onSkipBackward)
                playerButton(
                    title: isPlaying ? "Pause" : "Play",
                    systemImage: isPlaying ? "pause.fill" : "play.fill",
                    prominent: true,
                    action: onPlayPause
                )
                playerButton(title: "Forward 15 Seconds", systemImage: "goforward.15", action: onSkipForward)
                Spacer(minLength: 24)
                trackMenus
            }
        }
        .padding(24)
        .frame(maxWidth: 920)
        .glassPanelStyle(cornerRadius: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trackMenus: some View {
        HStack(spacing: 12) {
            if !availableAudioTracks.isEmpty {
                Menu {
                    ForEach(availableAudioTracks) { track in
                        Button(track.title) {
                            onSelectAudioTrack(track.id)
                        }
                    }
                } label: {
                    Label(audioMenuTitle, systemImage: "speaker.wave.2.fill")
                }
            }

            Menu {
                Button("Off") {
                    onSelectSubtitleTrack(nil)
                }
                ForEach(availableSubtitleTracks) { track in
                    Button(track.title) {
                        onSelectSubtitleTrack(track.id)
                    }
                }
            } label: {
                Label(subtitleMenuTitle, systemImage: "captions.bubble.fill")
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private var audioMenuTitle: String {
        availableAudioTracks.first(where: { $0.id == selectedAudioTrackID })?.title ?? "Audio"
    }

    private var subtitleMenuTitle: String {
        availableSubtitleTracks.first(where: { $0.id == selectedSubtitleTrackID })?.title ?? "Subtitles"
    }

    private func playerButton(
        title: String,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .padding(.horizontal, prominent ? 24 : 18)
                .padding(.vertical, 14)
                .frame(minWidth: prominent ? 160 : 0)
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? .black : .white)
        .background(prominent ? Color.white : Color.white.opacity(0.14), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(prominent ? 0 : 0.12), lineWidth: 1)
        }
    }
}
