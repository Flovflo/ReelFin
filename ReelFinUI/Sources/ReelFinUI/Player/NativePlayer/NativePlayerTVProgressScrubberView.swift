import SwiftUI

#if os(tvOS)
struct NativePlayerTVProgressScrubberView: View {
    let playbackTime: Double
    let durationSeconds: Double?
    let focus: FocusState<NativePlayerTVChromeFocus?>.Binding
    let availableActions: [NativePlayerTVChromeAction]
    let onCommand: (NativePlayerTVTransportCommand) -> Void

    var body: some View {
        Button {
            onCommand(.select)
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
                    .frame(height: isFocused ? 9 : 7)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 7, x: 0, y: 2)

                    Rectangle()
                        .fill(Color.white.opacity(0.96))
                        .frame(width: 3, height: isFocused ? 32 : 24)
                        .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 1)
                        .offset(x: playheadOffset(for: proxy.size.width))
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 24)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused(focus, equals: .timeline)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .onMoveCommand { direction in
            switch direction {
            case .left:
                onCommand(.move(.left))
            case .right:
                onCommand(.move(.right))
            case .up:
                onCommand(.move(.up))
                focus.wrappedValue = NativePlayerTVChromeFocusGraph.destination(
                    from: .timeline,
                    direction: .up,
                    availableActions: availableActions
                )
            case .down:
                onCommand(.move(.down))
                focus.wrappedValue = NativePlayerTVChromeFocusGraph.destination(
                    from: .timeline,
                    direction: .down,
                    availableActions: availableActions
                )
            @unknown default:
                break
            }
        }
        .accessibilityLabel("Playback position")
        .accessibilityValue(
            NativePlayerTVTimelineAccessibility.value(
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
