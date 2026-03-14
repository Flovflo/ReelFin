import SwiftUI

struct PlayerTimelineView: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var scrubTime: Double
    @State private var isScrubbing = false

    init(
        currentTime: TimeInterval,
        duration: TimeInterval,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.onSeek = onSeek
        _scrubTime = State(initialValue: currentTime)
    }

    var body: some View {
        VStack(spacing: 10) {
            timelineControl

            HStack {
                Text(formatTime(isScrubbing ? scrubTime : currentTime))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.78))
        }
        .onChange(of: currentTime) { _, newValue in
            guard !isScrubbing else { return }
            scrubTime = newValue
        }
    }

    @ViewBuilder
    private var timelineControl: some View {
#if os(tvOS)
        ProgressView(value: duration > 0 ? currentTime / duration : 0)
            .progressViewStyle(.linear)
            .tint(.white)
#else
        Slider(
            value: Binding(
                get: { isScrubbing ? scrubTime : currentTime },
                set: { scrubTime = $0 }
            ),
            in: 0...max(duration, 1),
            onEditingChanged: handleScrubbing
        )
        .tint(.white)
        .disabled(duration <= 0)
#endif
    }

    private func handleScrubbing(_ editing: Bool) {
        isScrubbing = editing
        guard !editing else { return }
        onSeek(scrubTime)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else {
            return "00:00"
        }

        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
