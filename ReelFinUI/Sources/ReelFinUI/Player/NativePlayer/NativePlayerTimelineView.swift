import SwiftUI

struct NativePlayerTimelineView: View {
    let presentation: NativePlayerChromePresentation
    let playbackTime: Double
    let durationSeconds: Double?
    let onSeekAbsolute: (Double) -> Void
    @State private var scrubValue: Double?

    var body: some View {
        VStack(spacing: 8) {
            scrubberControl
            timeLabels
        }
    }

    @ViewBuilder
    private var scrubberControl: some View {
#if os(tvOS)
        NativePlayerTVProgressScrubberView(
            playbackTime: scrubValue ?? playbackTime,
            durationSeconds: durationSeconds
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
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Text(presentation.currentTimeText)
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                    .offset(x: currentLabelX(width: proxy.size.width), y: 0)

                Text(presentation.remainingTimeText)
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 30)
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

    private func currentLabelX(width: CGFloat) -> CGFloat {
        let labelWidth: CGFloat = 92
        let progress = CGFloat(presentation.progress)
        let centered = (width * progress) - (labelWidth / 2)
        return min(max(0, centered), max(0, width - labelWidth))
    }
}
