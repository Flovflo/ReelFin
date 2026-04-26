import SwiftUI

#if os(tvOS)
struct NativePlayerTVProgressScrubberView: View {
    let playbackTime: Double
    let durationSeconds: Double?
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: {}) {
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
        .focused($isFocused)
        .focusable(true)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .accessibilityLabel("Playback position")
    }

    private func filledWidth(for width: CGFloat) -> CGFloat {
        guard let durationSeconds, durationSeconds > 0 else { return 0 }
        let progress = min(max(playbackTime / durationSeconds, 0), 1)
        return width * CGFloat(progress)
    }

    private func playheadOffset(for width: CGFloat) -> CGFloat {
        min(max(0, filledWidth(for: width) - 1.5), max(0, width - 3))
    }
}
#endif
