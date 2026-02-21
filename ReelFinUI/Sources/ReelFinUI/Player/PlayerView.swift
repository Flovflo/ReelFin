import PlaybackEngine
import Shared
import SwiftUI

struct PlayerView: View {
    @ObservedObject var session: PlaybackSessionController
    let item: MediaItem
    let onDismiss: () -> Void

    @State private var showDebug = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            NativePlayerViewController(player: session.player)
                .ignoresSafeArea()

            topBar

            if showDebug {
                debugOverlay
                    .padding(.top, 72)
                    .padding(.horizontal, 16)
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
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(session.routeDescription)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDebug.toggle()
                }
            } label: {
                Image(systemName: showDebug ? "ladybug.fill" : "ladybug")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .foregroundStyle(.white)
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
        .background(.ultraThinMaterial)
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
