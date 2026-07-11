import SwiftUI

struct NativePlayerTimelineView: View {
    let presentation: NativePlayerChromePresentation
    let playbackTime: Double
    let durationSeconds: Double?
    let onSeekRelative: (Double) -> Void
    let onSeekAbsolute: (Double) -> Void
    let onSelect: () -> Void
#if os(tvOS)
    let focus: FocusState<NativePlayerTVChromeFocus?>.Binding
    let onCommand: (NativePlayerTVTransportCommand) -> Void
#endif
    @State private var scrubValue: Double?

    var body: some View {
        VStack(spacing: 5) {
            scrubberControl
            timeLabels
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native_player_timeline")
    }

    @ViewBuilder
    private var scrubberControl: some View {
#if os(tvOS)
        NativePlayerTVProgressScrubberView(
            playbackTime: scrubValue ?? playbackTime,
            durationSeconds: durationSeconds,
            focus: focus,
            onCommand: onCommand
        )
#else
        Slider(
            value: scrubBinding,
            in: 0...max(durationSeconds ?? max(playbackTime, 1), 1),
            onEditingChanged: handleScrubEditing
        )
#endif
    }

    private var timeLabels: some View {
        HStack(spacing: 20) {
            Text(presentation.currentTimeText)
            Spacer(minLength: 0)
            Text(presentation.remainingTimeText)
        }
        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(.white.opacity(0.82))
        .shadow(color: .black.opacity(0.32), radius: 4, y: 1)
        .frame(height: 26)
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

}
