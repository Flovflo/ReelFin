import Foundation
import NativeMediaCore
import PlaybackEngine
import Shared
import SwiftUI

struct NativeVLCPlayerView: View {
    let playbackURL: URL?
    let playbackHeaders: [String: String]
    let startTimeSeconds: Double?
    let item: MediaItem
    let diagnostics: [String]
    let errorMessage: String?
    let onPlaybackTime: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var liveDiagnostics: [String] = []
    @State private var isPaused = false
    @State private var playbackTime: Double = 0
    @State private var localStartTimeSeconds: Double = 0
    @State private var seekGeneration = 0
    @State private var showsDiagnostics = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let playbackURL, routeViolation == nil {
                Group {
                    if isPacketDemuxedContainer {
                        NativeMatroskaSampleBufferPlayerView(
                            url: playbackURL,
                            headers: playbackHeaders,
                            container: containerFormat,
                            startTimeSeconds: resolvedStartTime,
                            baseDiagnostics: diagnostics,
                            isPaused: $isPaused,
                            onDiagnostics: { liveDiagnostics = $0 },
                            onPlaybackTime: handlePlaybackTime
                        )
                    } else {
                        NativeMP4SampleBufferPlayerView(
                            url: playbackURL,
                            startTimeSeconds: resolvedStartTime,
                            baseDiagnostics: diagnostics,
                            isPaused: $isPaused,
                            onDiagnostics: { liveDiagnostics = $0 },
                            onPlaybackTime: handlePlaybackTime
                        )
                    }
                }
                .id(playerIdentity)
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            if showsDiagnostics || visibleErrorMessage != nil {
                NativeVLCDiagnosticsPanelView(
                    rows: activeDiagnostics,
                    errorMessage: visibleErrorMessage
                )
            }
            NativeVLCTransportOverlayView(
                item: item,
                isPaused: $isPaused,
                showsDiagnostics: $showsDiagnostics,
                playbackTime: playbackTime,
                durationSeconds: durationSeconds,
                isBuffering: isBuffering,
                onSeekRelative: seekRelative,
                onSeekAbsolute: seekAbsolute,
                onDismiss: { dismiss() }
            )
        }
        .accessibilityIdentifier("native_vlc_class_player_screen")
        .onAppear {
            localStartTimeSeconds = startTimeSeconds ?? 0
            playbackTime = startTimeSeconds ?? 0
        }
        .onChange(of: playbackURL) { _, _ in
            localStartTimeSeconds = startTimeSeconds ?? 0
            playbackTime = startTimeSeconds ?? 0
            seekGeneration = 0
        }
#if os(tvOS)
        .onExitCommand {
            dismiss()
        }
        .onPlayPauseCommand {
            isPaused.toggle()
        }
#endif
    }

    private var activeDiagnostics: [String] {
        liveDiagnostics.isEmpty ? diagnostics : liveDiagnostics
    }
    private var playerIdentity: String {
        "\(playbackURL?.absoluteString ?? "none")|\(resolvedStartTime)|\(seekGeneration)"
    }
    private var resolvedStartTime: Double {
        localStartTimeSeconds > 0 ? localStartTimeSeconds : (startTimeSeconds ?? 0)
    }

    private var durationSeconds: Double? {
        guard let ticks = item.runtimeTicks, ticks > 0 else { return nil }
        return Double(ticks) / 10_000_000
    }

    private var isBuffering: Bool {
        activeDiagnostics.contains("state=buffering")
    }

    private var routeViolation: NativeVLCClassRouteViolation? {
        playbackURL.flatMap { NativeVLCClassRouteGuard.validateOriginalPlaybackURL($0).first }
    }

    private var visibleErrorMessage: String? {
        routeViolation?.localizedDescription ?? errorMessage
    }

    private var containerFormat: ContainerFormat {
        if diagnostics.contains(where: { $0 == "container=webm" }) { return .webm }
        if diagnostics.contains(where: { $0 == "container=mpegTS" }) { return .mpegTS }
        if diagnostics.contains(where: { $0 == "container=m2ts" }) { return .m2ts }
        return .matroska
    }

    private var isPacketDemuxedContainer: Bool {
        diagnostics.contains { line in
            line == "container=matroska" || line == "container=webm" || line == "container=mpegTS" || line == "container=m2ts"
        }
    }

    private func handlePlaybackTime(_ seconds: Double) {
        guard seconds.isFinite else { return }
        playbackTime = max(0, seconds)
        onPlaybackTime(playbackTime)
    }

    private func seekRelative(_ delta: Double) {
        seekAbsolute(playbackTime + delta)
    }

    private func seekAbsolute(_ seconds: Double) {
        let upperBound = durationSeconds ?? .greatestFiniteMagnitude
        let target = min(max(0, seconds), upperBound)
        playbackTime = target
        localStartTimeSeconds = target
        seekGeneration += 1
    }
}
