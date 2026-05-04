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
    @Environment(\.reelFinDisplayDensity) private var displayDensity
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #endif

    private let item: MediaItem
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let layoutStyle: PosterCardLayoutStyle
    private let focusStyle: PosterCardFocusStyle
    private let namespace: Namespace.ID?
    private let transitionSourceID: String?
    private let ranking: Int?
    private let progress: Double?
    private let optimizationStatus: ApplePlaybackOptimizationStatus?
    private let showsArtworkProgress: Bool
    private let showsInlineProgress: Bool
    private let showsTopTrailingBadges: Bool
    private let titleLineLimit: Int
    private let subtitleLineLimit: Int
    private let preferredWidth: CGFloat?

    public init(
        item: MediaItem,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        layoutStyle: PosterCardLayoutStyle = .row,
        focusStyle: PosterCardFocusStyle = .standard,
        namespace: Namespace.ID? = nil,
        transitionSourceID: String? = nil,
        ranking: Int? = nil,
        progress: Double? = nil,
        optimizationStatus: ApplePlaybackOptimizationStatus? = nil,
        showsArtworkProgress: Bool = true,
        showsInlineProgress: Bool = false,
        showsTopTrailingBadges: Bool = true,
        titleLineLimit: Int = 1,
        subtitleLineLimit: Int = 1,
        preferredWidth: CGFloat? = nil
    ) {
        self.item = item
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.layoutStyle = layoutStyle
        self.focusStyle = focusStyle
        self.namespace = namespace
        self.transitionSourceID = transitionSourceID
        self.ranking = ranking
        self.progress = progress
        self.optimizationStatus = optimizationStatus
        self.showsArtworkProgress = showsArtworkProgress
        self.showsInlineProgress = showsInlineProgress
        self.showsTopTrailingBadges = showsTopTrailingBadges
        self.titleLineLimit = titleLineLimit
        self.subtitleLineLimit = subtitleLineLimit
        self.preferredWidth = preferredWidth
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: tvMetadataSpacing) {
            PosterCardArtworkView(
                item: item,
                apiClient: apiClient,
                imagePipeline: imagePipeline,
                layoutStyle: layoutStyle,
                focusStyle: focusStyle,
                namespace: namespace,
                transitionSourceID: transitionSourceID,
                ranking: ranking,
                progress: showsArtworkProgress ? progress : nil,
                optimizationStatus: optimizationStatus,
                showsProgressOverlay: showsArtworkProgress,
                showsTopTrailingBadges: showsTopTrailingBadges,
                preferredWidth: preferredWidth
            )

            PosterCardMetadataView(
                item: item,
                layoutStyle: layoutStyle,
                inlineProgress: showsInlineProgress ? progress : nil,
                titleLineLimit: titleLineLimit,
                subtitleLineLimit: subtitleLineLimit,
                preferredWidth: preferredWidth
            )
            #if os(tvOS)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
            #endif
        }
        .frame(width: resolvedPosterWidth, alignment: .leading)
        #if os(tvOS)
        .tvMotionFocus(.posterCard, isFocused: isFocused)
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("media_card_\(item.id)")
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    private var resolvedPosterWidth: CGFloat {
        preferredWidth ?? PosterCardMetrics.posterWidth(
            for: layoutStyle,
            compact: isCompact,
            displayDensity: displayDensity
        )
    }

    private var tvMetadataSpacing: CGFloat {
        #if os(tvOS)
        return ReelFinTheme.tvCardMetadataSpacing
        #else
        return displayDensity.scaledSpacing(10)
        #endif
    }
}

public struct PosterCardArtworkView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.reelFinDisplayDensity) private var displayDensity
    @Environment(\.isFocused) private var isFocused

    private let item: MediaItem
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let layoutStyle: PosterCardLayoutStyle
    private let focusStyle: PosterCardFocusStyle
    private let namespace: Namespace.ID?
    private let transitionSourceID: String?
    private let ranking: Int?
    private let progress: Double?
    private let optimizationStatus: ApplePlaybackOptimizationStatus?
    private let showsProgressOverlay: Bool
    private let showsTopTrailingBadges: Bool
    private let preferredWidth: CGFloat?

    public init(
        item: MediaItem,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        layoutStyle: PosterCardLayoutStyle = .row,
        focusStyle: PosterCardFocusStyle = .standard,
        namespace: Namespace.ID? = nil,
        transitionSourceID: String? = nil,
        ranking: Int? = nil,
        progress: Double? = nil,
        optimizationStatus: ApplePlaybackOptimizationStatus? = nil,
        showsProgressOverlay: Bool = true,
        showsTopTrailingBadges: Bool = true,
        preferredWidth: CGFloat? = nil
    ) {
        self.item = item
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.layoutStyle = layoutStyle
        self.focusStyle = focusStyle
        self.namespace = namespace
        self.transitionSourceID = transitionSourceID
        self.ranking = ranking
        self.progress = progress
        self.optimizationStatus = optimizationStatus
        self.showsProgressOverlay = showsProgressOverlay
        self.showsTopTrailingBadges = showsTopTrailingBadges
        self.preferredWidth = preferredWidth
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
            .frame(width: resolvedPosterWidth, height: resolvedPosterHeight)
            .clipShape(RoundedRectangle(cornerRadius: ReelFinTheme.cardCornerRadius, style: .continuous))
            #if !os(tvOS)
            .shadow(color: .black.opacity(isFocused ? focusedShadowOpacity : 0.18), radius: isFocused ? focusedShadowRadius : 10, x: 0, y: isFocused ? focusedShadowYOffset : 6)
            #endif
            #if os(iOS)
            .overlay {
                RoundedRectangle(cornerRadius: ReelFinTheme.cardCornerRadius, style: .continuous)
                    .stroke(isFocused ? focusedStrokeColor : ReelFinTheme.glassStrokeColor, lineWidth: isFocused ? focusedStrokeWidth : ReelFinTheme.glassStrokeWidth)
            }
            #endif
            .overlay {
                if item.isPlayed {
                    RoundedRectangle(cornerRadius: ReelFinTheme.cardCornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsTopTrailingBadges {
                    VStack(alignment: .trailing, spacing: 8) {
                        if item.isPlayed {
                            PosterPlaybackStatusBadge(
                                text: "Watched",
                                systemImage: "checkmark.circle.fill",
                                tint: Color(red: 0.78, green: 0.95, blue: 0.82),
                                compact: layoutStyle != .landscape
                            )
                        } else if let positionText = item.playbackPositionDisplayText {
                            PosterPlaybackStatusBadge(
                                text: positionText,
                                systemImage: "play.circle.fill",
                                tint: Color.white.opacity(0.94),
                                compact: layoutStyle != .landscape
                            )
                        }

                        if let optimizationStatus {
                            ApplePlaybackPosterBadge(status: optimizationStatus)
                        }
                    }
                    .padding(8)
                }
            }

            if showsProgressOverlay,
               !item.isPlayed,
               let progressValue = progress ?? item.playbackProgress,
               progressValue > 0 {
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
        .frame(width: resolvedPosterWidth, height: resolvedPosterHeight)
        .modifier(MatchedCardModifier(itemID: transitionSourceID ?? item.id, namespace: namespace))
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
        PosterCardMetrics(
            layoutStyle: layoutStyle,
            compact: horizontalSizeClass == .compact,
            displayDensity: displayDensity
        )
    }

    private var resolvedPosterWidth: CGFloat {
        preferredWidth ?? metrics.posterWidth
    }

    private var resolvedPosterHeight: CGFloat {
        switch layoutStyle {
        case .landscape:
            return resolvedPosterWidth * (9.0 / 16.0)
        default:
            return resolvedPosterWidth * 1.55
        }
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
    @Environment(\.reelFinDisplayDensity) private var displayDensity
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #endif
    private let item: MediaItem
    private let layoutStyle: PosterCardLayoutStyle
    private let inlineProgress: Double?
    private let titleLineLimit: Int
    private let subtitleLineLimit: Int
    private let preferredWidth: CGFloat?

    public init(
        item: MediaItem,
        layoutStyle: PosterCardLayoutStyle = .row,
        inlineProgress: Double? = nil,
        titleLineLimit: Int = 1,
        subtitleLineLimit: Int = 1,
        preferredWidth: CGFloat? = nil
    ) {
        self.item = item
        self.layoutStyle = layoutStyle
        self.inlineProgress = inlineProgress
        self.titleLineLimit = titleLineLimit
        self.subtitleLineLimit = subtitleLineLimit
        self.preferredWidth = preferredWidth
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metadataSpacing) {
            Text(item.seriesName ?? item.name)
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(titleColor)
                .lineLimit(resolvedTitleLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: titleBlockHeight, maxHeight: titleBlockHeight, alignment: .topLeading)

            secondaryMetadata
        }
        .frame(width: resolvedPosterWidth, alignment: .leading)
    }

    private var titleFontSize: CGFloat {
        #if os(tvOS)
        return layoutStyle == .landscape ? 24 : 22
        #else
        return displayDensity.scaledTextSize(15)
        #endif
    }

    private var resolvedPosterWidth: CGFloat {
        preferredWidth ?? PosterCardMetrics.posterWidth(
            for: layoutStyle,
            compact: horizontalSizeClass == .compact,
            displayDensity: displayDensity
        )
    }

    private var subtitleFontSize: CGFloat {
        #if os(tvOS)
        return layoutStyle == .landscape ? 18 : 17
        #else
        return displayDensity.scaledTextSize(13)
        #endif
    }

    private var badgeFontSize: CGFloat {
        #if os(tvOS)
        return 15
        #else
        return displayDensity.scaledTextSize(11)
        #endif
    }

    private var metadataSpacing: CGFloat {
        #if os(tvOS)
        return 8
        #else
        return displayDensity.scaledSpacing(2)
        #endif
    }

    private var titleColor: Color {
        #if os(tvOS)
        return isFocused ? ReelFinTheme.tvBrightText : .white
        #else
        return .white
        #endif
    }

    private var subtitleColor: Color {
        #if os(tvOS)
        return isFocused ? ReelFinTheme.tvMutedText : ReelFinTheme.tvSoftText
        #else
        return .white.opacity(0.5)
        #endif
    }

    private var badgeForeground: Color {
        #if os(tvOS)
        return isFocused ? .white : ReelFinTheme.tvBrightText
        #else
        return .white
        #endif
    }

    private var badgeBackground: some ShapeStyle {
        #if os(tvOS)
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color.white.opacity(isFocused ? 0.22 : 0.16),
                    Color.white.opacity(isFocused ? 0.12 : 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        #else
        return AnyShapeStyle(Color.white.opacity(0.15))
        #endif
    }

    private var resolvedTitleLineLimit: Int {
        #if os(tvOS)
        return max(titleLineLimit, 2)
        #else
        return titleLineLimit
        #endif
    }

    private var titleBlockHeight: CGFloat {
        PosterCardMetrics.titleBlockHeight(
            fontSize: titleFontSize,
            lineLimit: resolvedTitleLineLimit
        )
    }

    @ViewBuilder
    private var secondaryMetadata: some View {
        if let inlineFooterText, let inlineProgress, inlineProgress > 0 {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: badgeFontSize, weight: .semibold))
                    .foregroundStyle(badgeForeground)

                PosterCardInlineProgressTrack(
                    progress: inlineProgress,
                    width: inlineProgressWidth
                )

                Text(inlineFooterText)
                    .font(.system(size: subtitleFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: secondaryMetadataHeight, alignment: .topLeading)
        } else if item.mediaType == .episode, let index = item.indexNumber {
            let seasonText = item.parentIndexNumber.map { "S\($0)" } ?? ""
            Text("\(seasonText) E\(index)")
                .font(.system(size: badgeFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(badgeForeground)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeBackground)
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, minHeight: secondaryMetadataHeight, alignment: .topLeading)
        } else if let year = item.year {
            Text(String(year))
                .font(.system(size: subtitleFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(subtitleColor)
                .lineLimit(subtitleLineLimit)
                .frame(maxWidth: .infinity, minHeight: secondaryMetadataHeight, alignment: .topLeading)
        } else if reservesSecondaryMetadataSpace {
            Color.clear
                .frame(height: secondaryMetadataHeight)
        }
    }

    private var secondaryMetadataHeight: CGFloat {
        #if os(tvOS)
        let lineHeight = max(subtitleFontSize * 1.24, badgeFontSize + 8)
        return ceil(lineHeight)
        #else
        return layoutStyle == .landscape ? ceil(max(subtitleFontSize * 1.24, badgeFontSize + 8)) : 0
        #endif
    }

    private var reservesSecondaryMetadataSpace: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    private var inlineFooterText: String? {
        guard layoutStyle == .landscape else { return nil }

        var values: [String] = []
        if item.mediaType == .episode,
           let season = item.parentIndexNumber,
           let episode = item.indexNumber {
            values.append("S\(season), E\(episode)")
        }

        if let runtime = item.runtimeDisplayText {
            values.append(runtime)
        } else if let year = item.year {
            values.append(String(year))
        }

        return values.isEmpty ? nil : values.joined(separator: " • ")
    }

    private var inlineProgressWidth: CGFloat {
        #if os(tvOS)
        return 56
        #else
        return displayDensity.scaledVisualSize(34)
        #endif
    }
}

private struct PosterPlaybackStatusBadge: View {
    let text: String
    let systemImage: String
    let tint: Color
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 10 : 12, weight: .bold))

            if !compact {
                Text(text)
                    .lineLimit(1)
            } else {
                Text(shortText)
                    .lineLimit(1)
            }
        }
        .font(.system(size: compact ? 10 : 12, weight: .bold, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 5 : 6)
        .background(Color.black.opacity(0.42), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 0.6)
        }
    }

    private var shortText: String {
        text == "Watched" ? "Seen" : text
    }
}

private struct PosterCardInlineProgressTrack: View {
    let progress: Double
    let width: CGFloat

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.28))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: max(width * progress, 10))
            }
            .frame(width: width, height: 6)
            .accessibilityHidden(true)
    }
}

struct PosterCardMetrics {
    let layoutStyle: PosterCardLayoutStyle
    let compact: Bool
    let displayDensity: ReelFinDisplayDensity

    init(
        layoutStyle: PosterCardLayoutStyle,
        compact: Bool,
        displayDensity: ReelFinDisplayDensity = .standard
    ) {
        self.layoutStyle = layoutStyle
        self.compact = compact
        self.displayDensity = displayDensity
    }

    var posterWidth: CGFloat {
        Self.posterWidth(for: layoutStyle, compact: compact, displayDensity: displayDensity)
    }

    static func posterWidth(
        for layoutStyle: PosterCardLayoutStyle,
        compact: Bool,
        displayDensity: ReelFinDisplayDensity = .standard
    ) -> CGFloat {
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
        let baseWidth: CGFloat
        switch layoutStyle {
        case .row:
            baseWidth = compact ? 134 : 160
        case .grid:
            baseWidth = compact ? 158 : 206
        case .landscape:
            baseWidth = compact ? 240 : 300
        }
        return baseWidth * displayDensity.visualScale
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

    static func titleBlockHeight(fontSize: CGFloat, lineLimit: Int) -> CGFloat {
        let lineHeight = fontSize * 1.18
        return ceil(lineHeight * CGFloat(max(lineLimit, 1)))
    }
}

struct PosterGridLayout: Equatable {
    let containerWidth: CGFloat
    let horizontalPadding: CGFloat
    let spacing: CGFloat
    let minimumCardWidth: CGFloat

    var availableWidth: CGFloat {
        max(0, containerWidth - (horizontalPadding * 2))
    }

    var columnCount: Int {
        guard availableWidth > 0, minimumCardWidth > 0 else { return 1 }
        return max(Int((availableWidth + spacing) / (minimumCardWidth + spacing)), 1)
    }

    var cardWidth: CGFloat {
        let columns = CGFloat(columnCount)
        let totalSpacing = spacing * max(columns - 1, 0)
        return max(0, (availableWidth - totalSpacing) / columns)
    }

    var occupiedWidth: CGFloat {
        (cardWidth * CGFloat(columnCount)) + (spacing * CGFloat(max(columnCount - 1, 0)))
    }

    var gridItems: [GridItem] {
        Array(
            repeating: GridItem(.fixed(cardWidth), spacing: spacing, alignment: .top),
            count: columnCount
        )
    }
}

struct MatchedCardModifier: ViewModifier {
    let itemID: String
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            if #available(iOS 18.0, tvOS 18.0, *) {
                content.matchedTransitionSource(id: "poster-\(itemID)", in: namespace)
            } else {
                content.matchedGeometryEffect(id: "poster-\(itemID)", in: namespace)
            }
        } else {
            content
        }
    }
}
