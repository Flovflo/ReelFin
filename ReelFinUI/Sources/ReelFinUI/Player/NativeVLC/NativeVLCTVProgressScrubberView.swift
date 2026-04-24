import SwiftUI

#if os(tvOS)
struct NativeVLCTVProgressScrubberView: View {
    let playbackTime: Double
    let durationSeconds: Double?
    let onSeekRelative: (Double) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: {}) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(isFocused ? 0.34 : 0.22))
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: filledWidth(for: proxy.size.width))
                    Circle()
                        .fill(Color.white)
                        .frame(width: isFocused ? 20 : 14, height: isFocused ? 20 : 14)
                        .offset(x: max(0, filledWidth(for: proxy.size.width) - 10))
                }
            }
            .frame(height: isFocused ? 22 : 14)
            .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .focusable(true)
        .onMoveCommand(perform: handleMove)
        .accessibilityLabel("Playback position")
    }

    private func filledWidth(for width: CGFloat) -> CGFloat {
        guard let durationSeconds, durationSeconds > 0 else { return 0 }
        let progress = min(max(playbackTime / durationSeconds, 0), 1)
        return width * CGFloat(progress)
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            onSeekRelative(-10)
        case .right:
            onSeekRelative(30)
        default:
            break
        }
    }
}
#endif
