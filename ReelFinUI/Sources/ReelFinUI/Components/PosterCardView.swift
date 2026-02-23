import Shared
import SwiftUI

public enum PosterCardLayoutStyle: Sendable {
    case row
    case grid
    case landscape
}

public struct PosterCardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let item: MediaItem
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let layoutStyle: PosterCardLayoutStyle
    private let namespace: Namespace.ID?
    private let ranking: Int?
    private let progress: Double?

    public init(
        item: MediaItem,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        layoutStyle: PosterCardLayoutStyle = .row,
        namespace: Namespace.ID? = nil,
        ranking: Int? = nil,
        progress: Double? = nil
    ) {
        self.item = item
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.layoutStyle = layoutStyle
        self.namespace = namespace
        self.ranking = ranking
        self.progress = progress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                CachedRemoteImage(
                    itemID: {
                        // For landscape (Continue Watching), use the series ID for backdrop.
                        // For portrait poster, use the series/parent ID for episodes.
                        if item.mediaType == .episode {
                            return item.parentID ?? item.id
                        }
                        return item.id
                    }(),
                    type: layoutStyle == .landscape ? .backdrop : .primary,
                    width: layoutStyle == .landscape ? 400 : 360,
                    apiClient: apiClient,
                    imagePipeline: imagePipeline
                )
                .frame(width: posterWidth, height: posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: ReelFinTheme.cardCornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
                .modifier(MatchedCardModifier(itemID: item.id, namespace: namespace))
                .overlay {
                    RoundedRectangle(cornerRadius: ReelFinTheme.cardCornerRadius, style: .continuous)
                        .stroke(ReelFinTheme.glassStrokeColor, lineWidth: ReelFinTheme.glassStrokeWidth)
                }
                .overlay(alignment: .topTrailing) {
                    if item.isPlayed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                            }
                            .padding(8)
                    }
                }

                // Progress Bar Overlay
                if let progressValue = progress ?? item.playbackProgress, progressValue > 0 {
                    GeometryReader { geo in
                        Capsule()
                            .fill(.white.opacity(0.3))
                            .frame(height: 4)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(ReelFinTheme.accent)
                                    .frame(width: geo.size.width * CGFloat(progressValue))
                            }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }

                // Ranking Overlay
                if let ranking {
                    Text("\(ranking)")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.4)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.6), radius: 4, x: 2, y: 2)
                        .offset(x: -12, y: 16)
                }
            }

            // Text Metadata
            VStack(alignment: .leading, spacing: 2) {
                Text(item.seriesName ?? item.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if item.mediaType == .episode, let index = item.indexNumber {
                    let seasonText = item.parentIndexNumber.map { "S\($0)" } ?? ""
                    Text("\(seasonText) E\(index)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                } else if let year = item.year {
                    Text(String(year))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: posterWidth, alignment: .leading)
    }

    private var posterWidth: CGFloat {
        switch layoutStyle {
        case .row:
            return horizontalSizeClass == .compact ? 134 : 160 // Shrink slightly to match TV app feel
        case .grid:
            return horizontalSizeClass == .compact ? 158 : 206
        case .landscape:
            return horizontalSizeClass == .compact ? 240 : 300
        }
    }

    private var posterHeight: CGFloat {
        switch layoutStyle {
        case .landscape:
            return posterWidth * (9.0 / 16.0)
        default:
            return posterWidth * 1.55
        }
    }
}

private struct MatchedCardModifier: ViewModifier {
    let itemID: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "poster-\(itemID)", in: namespace)
        } else {
            content
        }
    }
}
