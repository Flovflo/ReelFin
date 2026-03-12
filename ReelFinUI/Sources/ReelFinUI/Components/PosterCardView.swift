import Shared
import SwiftUI

public enum PosterCardLayoutStyle: Sendable {
    case row
    case grid
    case landscape
}

public enum PosterCardFocusStyle: Sendable, Equatable {
    case standard
    case subtle
}

public struct PosterCardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let item: MediaItem
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let layoutStyle: PosterCardLayoutStyle
    private let focusStyle: PosterCardFocusStyle
    private let namespace: Namespace.ID?
    private let ranking: Int?
    private let progress: Double?
    private let titleLineLimit: Int
    private let subtitleLineLimit: Int

    public init(
        item: MediaItem,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        layoutStyle: PosterCardLayoutStyle = .row,
        focusStyle: PosterCardFocusStyle = .standard,
        namespace: Namespace.ID? = nil,
        ranking: Int? = nil,
        progress: Double? = nil,
        titleLineLimit: Int = 1,
        subtitleLineLimit: Int = 1
    ) {
        self.item = item
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.layoutStyle = layoutStyle
        self.focusStyle = focusStyle
        self.namespace = namespace
        self.ranking = ranking
        self.progress = progress
        self.titleLineLimit = titleLineLimit
        self.subtitleLineLimit = subtitleLineLimit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PosterCardArtworkView(
                item: item,
                apiClient: apiClient,
                imagePipeline: imagePipeline,
                layoutStyle: layoutStyle,
                focusStyle: focusStyle,
                namespace: namespace,
                ranking: ranking,
                progress: progress
            )

            PosterCardMetadataView(
                item: item,
                layoutStyle: layoutStyle,
                titleLineLimit: titleLineLimit,
                subtitleLineLimit: subtitleLineLimit
            )
        }
        .frame(width: PosterCardMetrics.posterWidth(for: layoutStyle, compact: isCompact), alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("media_card_\(item.id)")
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
}

public struct PosterCardArtworkView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isFocused) private var isFocused

    private let item: MediaItem
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let layoutStyle: PosterCardLayoutStyle
    private let focusStyle: PosterCardFocusStyle
    private let namespace: Namespace.ID?
    private let ranking: Int?
    private let progress: Double?

    public init(
        item: MediaItem,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        layoutStyle: PosterCardLayoutStyle = .row,
        focusStyle: PosterCardFocusStyle = .standard,
        namespace: Namespace.ID? = nil,
        ranking: Int? = nil,
        progress: Double? = nil
    ) {
        self.item = item
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.layoutStyle = layoutStyle
        self.focusStyle = focusStyle
        self.namespace = namespace
        self.ranking = ranking
        self.progress = progress
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedRemoteImage(
                itemID: imageItemID,
                type: layoutStyle == .landscape ? .backdrop : .primary,
                width: layoutStyle == .landscape ? 400 : 360,
                apiClient: apiClient,
                imagePipeline: imagePipeline
            )
            .frame(width: metrics.posterWidth, height: metrics.posterHeight)
            .clipShape(RoundedRectangle(cornerRadius: ReelFinTheme.cardCornerRadius, style: .continuous))
            #if os(tvOS)
            .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 8)
            #else
            .shadow(color: .black.opacity(isFocused ? focusedShadowOpacity : 0.18), radius: isFocused ? focusedShadowRadius : 10, x: 0, y: isFocused ? focusedShadowYOffset : 6)
            #endif
            .modifier(MatchedCardModifier(itemID: item.id, namespace: namespace))
            #if os(iOS)
            .overlay {
                RoundedRectangle(cornerRadius: ReelFinTheme.cardCornerRadius, style: .continuous)
                    .stroke(isFocused ? focusedStrokeColor : ReelFinTheme.glassStrokeColor, lineWidth: isFocused ? focusedStrokeWidth : ReelFinTheme.glassStrokeWidth)
            }
            #endif
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
        .frame(width: metrics.posterWidth, height: metrics.posterHeight)
        .contentShape(RoundedRectangle(cornerRadius: ReelFinTheme.cardCornerRadius, style: .continuous))
        #if os(iOS)
        .scaleEffect(isFocused ? focusedScale : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isFocused)
        #endif
    }

    private var imageItemID: String {
        if item.mediaType == .episode {
            return item.parentID ?? item.id
        }
        return item.id
    }

    private var metrics: PosterCardMetrics {
        PosterCardMetrics(layoutStyle: layoutStyle, compact: horizontalSizeClass == .compact)
    }

    private var focusedStrokeColor: Color {
        switch focusStyle {
        case .standard:
            return .white.opacity(0.50)
        case .subtle:
            return .white.opacity(0.22)
        }
    }

    private var focusedStrokeWidth: CGFloat {
        switch focusStyle {
        case .standard:
            return 2
        case .subtle:
            return 1
        }
    }

    private var focusedScale: CGFloat {
        switch focusStyle {
        case .standard:
            return 1.08
        case .subtle:
            return 1.03
        }
    }

    private var focusedShadowOpacity: Double {
        focusStyle == .standard ? 0.45 : 0.28
    }

    private var focusedShadowRadius: CGFloat {
        focusStyle == .standard ? 24 : 16
    }

    private var focusedShadowYOffset: CGFloat {
        focusStyle == .standard ? 14 : 8
    }
}

public struct PosterCardMetadataView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let item: MediaItem
    private let layoutStyle: PosterCardLayoutStyle
    private let titleLineLimit: Int
    private let subtitleLineLimit: Int

    public init(
        item: MediaItem,
        layoutStyle: PosterCardLayoutStyle = .row,
        titleLineLimit: Int = 1,
        subtitleLineLimit: Int = 1
    ) {
        self.item = item
        self.layoutStyle = layoutStyle
        self.titleLineLimit = titleLineLimit
        self.subtitleLineLimit = subtitleLineLimit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metadataSpacing) {
            Text(item.seriesName ?? item.name)
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(titleLineLimit)
                .fixedSize(horizontal: false, vertical: true)

            if item.mediaType == .episode, let index = item.indexNumber {
                let seasonText = item.parentIndexNumber.map { "S\($0)" } ?? ""
                Text("\(seasonText) E\(index)")
                    .font(.system(size: badgeFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
            } else if let year = item.year {
                Text(String(year))
                    .font(.system(size: subtitleFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(subtitleLineLimit)
            }
        }
        .frame(width: PosterCardMetrics.posterWidth(for: layoutStyle, compact: horizontalSizeClass == .compact), alignment: .leading)
    }

    private var titleFontSize: CGFloat {
        #if os(tvOS)
        return 20
        #else
        return 15
        #endif
    }

    private var subtitleFontSize: CGFloat {
        #if os(tvOS)
        return 16
        #else
        return 13
        #endif
    }

    private var badgeFontSize: CGFloat {
        #if os(tvOS)
        return 14
        #else
        return 11
        #endif
    }

    private var metadataSpacing: CGFloat {
        #if os(tvOS)
        return 4
        #else
        return 2
        #endif
    }
}

private struct PosterCardMetrics {
    let layoutStyle: PosterCardLayoutStyle
    let compact: Bool

    var posterWidth: CGFloat {
        Self.posterWidth(for: layoutStyle, compact: compact)
    }

    static func posterWidth(for layoutStyle: PosterCardLayoutStyle, compact: Bool) -> CGFloat {
        #if os(tvOS)
        switch layoutStyle {
        case .row:
            return 220
        case .grid:
            return 240
        case .landscape:
            return 400
        }
        #else
        switch layoutStyle {
        case .row:
            return compact ? 134 : 160
        case .grid:
            return compact ? 158 : 206
        case .landscape:
            return compact ? 240 : 300
        }
        #endif
    }

    var posterHeight: CGFloat {
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
