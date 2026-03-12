import ImageCache
import JellyfinAPI
import Shared
import SwiftUI

public struct EpisodeCardView: View {
    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #else
    @Environment(\.isFocused) private var isFocused
    #endif

    let episode: MediaItem
    let width: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    public init(
        episode: MediaItem,
        width: CGFloat,
        isSelected: Bool = false,
        onSelect: @escaping () -> Void,
        apiClient: any JellyfinAPIClientProtocol,
        imagePipeline: any ImagePipelineProtocol
    ) {
        self.episode = episode
        self.width = width
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                EpisodeCardArtworkView(
                    episode: episode,
                    width: width,
                    selectionLabel: isSelected ? "Selected" : nil,
                    apiClient: apiClient,
                    imagePipeline: imagePipeline
                )
                VStack(alignment: .leading, spacing: 12) {
                    Text(episodeLabel + runtimeSuffix)
                        .font(.system(size: metaFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.60))
                    Text(episode.name)
                        .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: overviewFontSize, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(2)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardFill)
            }
            .frame(width: width, alignment: .leading)
            #if os(iOS)
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(borderColor, lineWidth: borderWidth)
            }
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .contentShape(RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
#if os(tvOS)
        .focused($isFocused)
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 8)
#else
        .shadow(color: .black.opacity(isFocused ? 0.34 : 0.20), radius: isFocused ? 22 : 14, x: 0, y: isFocused ? 12 : 8)
        .scaleEffect(isFocused ? 1.018 : 1)
#endif
        .accessibilityHint("Play episode")
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }

    private var episodeLabel: String {
        let seasonText = episode.parentIndexNumber.map { "S\($0)" } ?? ""
        let episodeText = episode.indexNumber.map { "E\($0)" } ?? "Episode"
        return "\(seasonText) \(episodeText)".trimmingCharacters(in: .whitespaces)
    }

    private var runtimeSuffix: String {
        guard let runtime = episode.runtimeDisplayText else { return "" }
        return "  •  \(runtime)"
    }

    private var cardFill: Color {
#if os(tvOS)
        if isFocused {
            return Color.white.opacity(0.12)
        }
        if isSelected {
            return Color.white.opacity(0.08)
        }
        return Color.white.opacity(0.04)
#else
        return isFocused ? Color.white.opacity(0.10) : Color.white.opacity(0.05)
#endif
    }

    private var borderColor: Color {
        if isFocused {
            return .white.opacity(0.92)
        }
        if isSelected {
            return .white.opacity(0.42)
        }
        return .white.opacity(0.08)
    }

    private var borderWidth: CGFloat {
        if isFocused {
            return 2.4
        }
        return isSelected ? 1.2 : 0.8
    }

    private var metaFontSize: CGFloat {
#if os(tvOS)
        return 17
#else
        return 12
#endif
    }

    private var titleFontSize: CGFloat {
#if os(tvOS)
        return 24
#else
        return 18
#endif
    }

    private var overviewFontSize: CGFloat {
#if os(tvOS)
        return 18
#else
        return 14
#endif
    }
}
