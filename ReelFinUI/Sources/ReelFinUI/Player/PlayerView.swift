import AVKit
import PlaybackEngine
import Shared
import SwiftUI

struct PlayerView: View {
    @ObservedObject var session: PlaybackSessionController
    let item: MediaItem
    let onDismiss: () -> Void

    @State private var isSliding = false
    @State private var sliderValue: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: session.player)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                controls
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .onAppear {
            sliderValue = session.currentTime
        }
        .onChange(of: session.currentTime) { newValue in
            if !isSliding {
                sliderValue = newValue
            }
        }
        .onDisappear {
            session.pause()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(session.routeDescription)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                Button {
                    session.seek(by: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                }

                Button {
                    session.togglePlayback()
                } label: {
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                }

                Button {
                    session.seek(by: 30)
                } label: {
                    Image(systemName: "goforward.30")
                }

                Menu {
                    ForEach(session.availableAudioTracks) { track in
                        Button(track.title) {
                            session.selectAudioTrack(id: track.id)
                        }
                    }
                } label: {
                    Image(systemName: "waveform")
                }

                Menu {
                    Button("Off") {
                        session.selectSubtitleTrack(id: nil)
                    }

                    ForEach(session.availableSubtitleTracks) { track in
                        Button(track.title) {
                            session.selectSubtitleTrack(id: track.id)
                        }
                    }
                } label: {
                    Image(systemName: "captions.bubble")
                }
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { sliderValue },
                        set: { sliderValue = $0 }
                    ),
                    in: 0 ... max(session.duration, 1),
                    onEditingChanged: { editing in
                        isSliding = editing
                        if !editing {
                            session.seek(to: sliderValue)
                        }
                    }
                )
                .tint(ReelFinTheme.accent)

                HStack {
                    Text(formatTime(sliderValue))
                    Spacer()
                    Text(formatTime(session.duration))
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let value = Int(seconds)
        let minutes = value / 60
        let remaining = value % 60
        return String(format: "%02d:%02d", minutes, remaining)
    }
}
