import PlaybackEngine
import SwiftUI

#if os(iOS)
struct PlaybackSkipButton: View {
    let suggestion: PlaybackSkipSuggestion
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var horizontalPadding = 28.0
    @ScaledMetric(relativeTo: .headline) private var verticalPadding = 18.0
    @ScaledMetric(relativeTo: .title3) private var minimumWidth = 186.0
    @ScaledMetric(relativeTo: .headline) private var cornerRadius = 20.0
    @ScaledMetric(relativeTo: .headline) private var shadowRadius = 24.0

    var body: some View {
        Button(action: action) {
            Text(suggestion.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black.opacity(0.94))
                .frame(minWidth: minimumWidth)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    Color.white.opacity(0.96),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.28), radius: shadowRadius, x: 0, y: 16)
        .accessibilityLabel(suggestion.title)
        .accessibilityHint("Skips the active intro, recap, credits, or jumps to the next episode.")
        .accessibilityIdentifier("playback_skip_button")
    }
}
#endif
