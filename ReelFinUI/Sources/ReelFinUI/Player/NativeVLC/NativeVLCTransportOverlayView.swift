import Foundation
import Shared
import SwiftUI

struct NativeVLCTransportOverlayView: View {
    let item: MediaItem
    @Binding var isPaused: Bool
    @Binding var showsDiagnostics: Bool
    let playbackTime: Double
    let durationSeconds: Double?
    let isBuffering: Bool
    let onSeekRelative: (Double) -> Void
    let onSeekAbsolute: (Double) -> Void
    let onDismiss: () -> Void
    @State private var scrubValue: Double?

    var body: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
        .padding(.horizontal, 64)
        .padding(.vertical, 44)
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            playerButton(systemName: "chevron.backward", action: onDismiss)
                .accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                statusText
            }
            Spacer()
            playerButton(systemName: showsDiagnostics ? "stethoscope.circle.fill" : "stethoscope.circle") {
                showsDiagnostics.toggle()
            }
            .accessibilityLabel("Diagnostics")
        }
    }

    private var statusText: some View {
        Text(isBuffering ? "Buffering" : "Original file, native engine")
            .font(.callout.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            scrubber
            GlassEffectContainer(spacing: 18) {
                HStack(spacing: 18) {
                    playerButton(systemName: "gobackward.10") { onSeekRelative(-10) }
                    playerButton(systemName: isPaused ? "play.fill" : "pause.fill") {
                        isPaused.toggle()
                    }
                    .font(.system(size: 30, weight: .bold))
                    playerButton(systemName: "goforward.30") { onSeekRelative(30) }
                }
            }
        }
        .padding(22)
        .reelFinGlassRoundedRect(
            cornerRadius: 28,
            interactive: true,
            tint: Color.white.opacity(0.08),
            stroke: Color.white.opacity(0.16),
            shadowOpacity: 0.22,
            shadowRadius: 24,
            shadowYOffset: 12
        )
    }

    private var scrubber: some View {
        VStack(spacing: 8) {
            scrubberControl
            HStack {
                Text(Self.formatTime(scrubValue ?? playbackTime))
                Spacer()
                Text(Self.formatTime(durationSeconds))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.76))
        }
    }

    @ViewBuilder
    private var scrubberControl: some View {
        #if os(tvOS)
        NativeVLCTVProgressScrubberView(
            playbackTime: scrubValue ?? playbackTime,
            durationSeconds: durationSeconds,
            onSeekRelative: onSeekRelative
        )
        #else
        Slider(
            value: scrubBinding,
            in: 0...max(durationSeconds ?? max(playbackTime, 1), 1),
            onEditingChanged: handleScrubEditing
        )
        #endif
    }

    private var scrubBinding: Binding<Double> {
        Binding(
            get: { scrubValue ?? playbackTime },
            set: { scrubValue = $0 }
        )
    }

    private func handleScrubEditing(_ isEditing: Bool) {
        guard !isEditing, let scrubValue else { return }
        onSeekAbsolute(scrubValue)
        self.scrubValue = nil
    }

    private func playerButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 66, height: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
        .foregroundStyle(.white)
    }

    private static func formatTime(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "--:--" }
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
