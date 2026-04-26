#if os(iOS)
import SwiftUI

struct NativePlayerIOSTimelineView: View {
    let presentation: NativePlayerChromePresentation
    let playbackTime: Double
    let durationSeconds: Double?
    let onSeekAbsolute: (Double) -> Void
    @State private var scrubValue: Double?

    var body: some View {
        HStack(spacing: 14) {
            Text(presentation.currentTimeText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .frame(width: currentTimeWidth, alignment: .leading)

            NativePlayerIOSProgressBar(progress: progress, onScrub: scrub)
                .layoutPriority(1)

            Text(presentation.remainingTimeText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)
                .frame(width: remainingTimeWidth, alignment: .trailing)
        }
        .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(.white.opacity(0.66))
        .padding(.horizontal, 14)
        .frame(height: 46)
        .nativePlayerIOSGlassCapsule()
    }

    private var progress: Double {
        guard let durationSeconds, durationSeconds > 0 else { return 0 }
        return min(max((scrubValue ?? playbackTime) / durationSeconds, 0), 1)
    }

    private var currentTimeWidth: CGFloat {
        hasHourComponent ? 76 : 58
    }

    private var remainingTimeWidth: CGFloat {
        hasHourComponent ? 86 : 70
    }

    private var hasHourComponent: Bool {
        playbackTime >= 3_600 || (durationSeconds ?? 0) >= 3_600
    }

    private func scrub(_ xProgress: Double, isFinal: Bool) {
        guard let durationSeconds, durationSeconds > 0 else { return }

        let seconds = min(max(xProgress, 0), 1) * durationSeconds
        scrubValue = seconds

        if isFinal {
            onSeekAbsolute(seconds)
            scrubValue = nil
        }
    }
}

private struct NativePlayerIOSProgressBar: View {
    let progress: Double
    let onScrub: (Double, Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.34))

                Capsule(style: .continuous)
                    .fill(.white.opacity(0.88))
                    .frame(width: width * min(max(progress, 0), 1))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onScrub(value.location.x / width, false)
                    }
                    .onEnded { value in
                        onScrub(value.location.x / width, true)
                    }
            )
        }
        .frame(height: 8)
    }
}
#endif
