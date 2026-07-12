import SwiftUI

#if os(tvOS)
struct NativePlayerTVProgressScrubberView: View {
    let playbackTime: Double
    let durationSeconds: Double?
    let focus: FocusState<NativePlayerTVChromeFocus?>.Binding
    let isScrubbing: Bool
    let onSelect: () -> Void
    let onMove: (NativePlayerRemoteMoveDirection) -> Void
    let onScrubBegin: (TVRemoteScrubSample) -> Void
    let onScrubUpdate: (TVRemoteScrubSample) -> Void
    let onGestureAvailabilityChanged: (Bool) -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(isFocused ? 0.32 : 0.22))
                        Rectangle()
                            .fill(Color.white.opacity(0.72))
                            .frame(width: filledWidth(for: proxy.size.width))
                    }
                    .frame(height: isScrubbing ? 11 : (isFocused ? 9 : 7))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 7, x: 0, y: 2)

                    Rectangle()
                        .fill(Color.white.opacity(0.96))
                        .frame(
                            width: isScrubbing ? 5 : 3,
                            height: isScrubbing ? 42 : (isFocused ? 32 : 24)
                        )
                        .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 1)
                        .offset(x: playheadOffset(for: proxy.size.width))
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 24)
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.14), value: isScrubbing)
            .overlay {
                if isFocused {
                    TVRemoteCircularScrubGestureView(
                        onBegin: onScrubBegin,
                        onChange: onScrubUpdate,
                        onAvailabilityChanged: onGestureAvailabilityChanged
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .focused(focus, equals: .timeline)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .onMoveCommand { direction in
            switch direction {
            case .left:
                onMove(.left)
            case .right:
                onMove(.right)
            case .up:
                onMove(.up)
            case .down:
                onMove(.down)
            @unknown default:
                break
            }
        }
        .accessibilityLabel("Playback position")
        .accessibilityValue(
            (isScrubbing ? "Scrubbing, " : "") + NativePlayerTVTimelineAccessibility.value(
                playbackTime: playbackTime,
                durationSeconds: durationSeconds
            )
        )
        .accessibilityIdentifier("native_player_timeline_scrubber")
    }

    private func filledWidth(for width: CGFloat) -> CGFloat {
        guard let durationSeconds, durationSeconds > 0 else { return 0 }
        let progress = min(max(playbackTime / durationSeconds, 0), 1)
        return width * CGFloat(progress)
    }

    private func playheadOffset(for width: CGFloat) -> CGFloat {
        min(max(0, filledWidth(for: width) - 1.5), max(0, width - 3))
    }

    private var isFocused: Bool { focus.wrappedValue == .timeline }
}
#endif
