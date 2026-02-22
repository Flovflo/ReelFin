import PlaybackEngine
import Shared
import SwiftUI

struct PlayerView: View {
    @ObservedObject var session: PlaybackSessionController
    let item: MediaItem
    let onDismiss: () -> Void

    @State private var showDebug = false
    @State private var spinnerRotation: Double = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            // Native iOS/tvOS player controls (scrubber, audio/subtitle menu, PiP, AirPlay).
            NativePlayerViewController(player: session.player)
                .ignoresSafeArea()

            if shouldShowLoadingOverlay {
                loadingOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if showDebug {
                debugOverlay
                    .padding(.horizontal, 16)
                    .padding(.top, 108)
                    .transition(.opacity)
            }

            if let error = session.playbackErrorMessage {
                errorBanner(error)
                    .padding(.horizontal, 16)
                    .padding(.top, 108)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .safeAreaInset(edge: .top) {
            topBarControls
                .padding(.horizontal, 12)
                .padding(.top, 6)
        }
        .onDisappear {
            session.pause()
        }
        .onAppear {
            spinnerRotation = 0
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                spinnerRotation = 360
            }
        }
    }

    private var topBarControls: some View {
        HStack(spacing: 10) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
            }

            Spacer(minLength: 0)

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
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var shouldShowLoadingOverlay: Bool {
        session.metrics.timeToFirstFrameMs == nil && session.playbackErrorMessage == nil
    }

    private var loadingOverlay: some View {
        VStack(spacing: 14) {
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(
                    LinearGradient(
                        colors: [ReelFinTheme.accent, ReelFinTheme.accentSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 42, height: 42)
                .rotationEffect(.degrees(spinnerRotation))

            Text(session.routeDescription.isEmpty ? "Starting playback…" : "Starting playback…\n\(session.routeDescription)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
