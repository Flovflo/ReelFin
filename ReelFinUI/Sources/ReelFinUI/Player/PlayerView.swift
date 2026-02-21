import PlaybackEngine
import Shared
import SwiftUI

struct PlayerView: View {
    @ObservedObject var session: PlaybackSessionController
    let item: MediaItem
    let onDismiss: () -> Void

    @State private var showDebug = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            NativePlayerLayerView(player: session.player)
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .top, spacing: 8) {
            VStack(spacing: 8) {
                topBar
                if let error = session.playbackErrorMessage {
                    errorBanner(error)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 10) {
            fallbackControls
                .padding(.horizontal, 12)
        }
        .overlay(alignment: .topLeading) {
            if showDebug {
                debugOverlay
                    .padding(.horizontal, 16)
                    .padding(.top, 108)
                    .transition(.opacity)
            }
        }
        .onDisappear {
            session.pause()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(session.routeDescription)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDebug.toggle()
                }
            } label: {
                Image(systemName: showDebug ? "ladybug.fill" : "ladybug")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(.white)
    }

    private var fallbackControls: some View {
        HStack(spacing: 12) {
            Button {
                onDismiss()
            } label: {
                Label("Close", systemImage: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer(minLength: 0)

            Button {
                session.seek(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 17, weight: .semibold))
            }

            Button {
                session.togglePlayback()
            } label: {
                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .semibold))
            }

            Button {
                session.seek(by: 30)
            } label: {
                Image(systemName: "goforward.30")
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playback error")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Playback Debug")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            if let info = session.debugInfo {
                debugRow("Container", info.container)
                debugRow("Video", info.videoCodec.uppercased())
                debugRow("Bit depth", info.videoBitDepth.map(String.init) ?? "Unknown")
                debugRow("HDR", session.runtimeHDRMode.rawValue)
                debugRow("Audio", info.audioMode)
                debugRow("Bitrate", info.bitrate.map { "\($0 / 1_000_000) Mbps" } ?? "Unknown")
                debugRow("Method", info.playMethod)
            } else {
                debugRow("Source", "Loading…")
            }

            debugRow("TTFF", session.metrics.timeToFirstFrameMs.map { String(format: "%.0f ms", $0) } ?? "Pending")
            debugRow("Stalls", "\(session.metrics.stallCount)")
            debugRow("Dropped", "\(session.metrics.droppedFrames)")
            debugRow("AirPlay", session.isExternalPlaybackActive ? "Active" : "Off")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
    }
}
