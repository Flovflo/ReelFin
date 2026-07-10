import Foundation
import PlaybackEngine
import Shared
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum HomePlaybackRoute: Equatable {
    case custom
    case legacy

    static func preferred(useCustomPlayerEngine: Bool) -> Self {
        useCustomPlayerEngine ? .custom : .legacy
    }
}

enum HomePlayerPresentationPolicy {
    static func showsTopNavigation(hasActivePlayer: Bool) -> Bool {
        !hasActivePlayer
    }
}

/// Keep the playback payload and presentation trigger atomic. A separate `showPlayer` Boolean can
/// present an empty cover before SwiftUI observes the engine/session, leaving audio active behind
/// a black screen. The detail screen uses the same invariant.
private struct HomePlayerPresentation: Identifiable {
    enum Content {
        case custom(CustomPlaybackEngine)
        case legacy(PlaybackSessionController)
    }

    let id = UUID()
    let item: MediaItem
    let content: Content
}

// MARK: - Components (Merged here to avoid missing .pbxproj references)

#if os(tvOS)
/// A focusable card for Apple TV Siri Remote navigation.
/// Uses a plain Button so Siri Remote OK activates reliably while keeping the
/// custom focus treatment that matches the rest of the home shelf motion.
private struct TVCardButton: View {
    @Environment(\.tvTopNavigationFocusAction) private var requestTopNavigationFocus
    @FocusState private var isFocused: Bool
    @State private var isActivating = false

    let item: MediaItem
    let index: Int
    let kind: HomeSectionKind
    let isTop10: Bool
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let namespaceProvider: (String) -> Namespace.ID?
    let transitionSourceID: String
    let focusedItemID: FocusState<String?>.Binding?
    let isLandscapeRail: Bool
    let progress: Double?
    let optimizationStatus: ApplePlaybackOptimizationStatus?
    let onFocus: ((MediaItem) -> Void)?
    let onMoveUpFromContinueWatching: (() -> Void)?
    let onSelect: (MediaItem) -> Void

    var body: some View {
        let transitionNamespace = namespaceProvider(item.id)

        Button(action: handleActivation) {
            TVHomeShelfCard(
                item: item,
                kind: kind,
                ranking: isTop10 ? (index + 1) : nil,
                layoutStyle: layoutStyle,
                progress: progress,
                optimizationStatus: optimizationStatus,
                namespace: transitionNamespace,
                transitionSourceID: transitionSourceID,
                apiClient: apiClient,
                imagePipeline: imagePipeline,
                isFocused: isFocused,
                isActivating: isActivating,
                usesNativeZoomTransition: usesNativeZoomTransition(namespace: transitionNamespace)
            )
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .onMoveCommand(perform: handleMoveCommand)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .focused($isFocused)
        .modifier(TVHomeItemFocusModifier(itemID: item.id, focusedItemID: focusedItemID))
        .id(item.id)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("media_card_button_\(kind.rawValue)_\(item.id)")
        .onChange(of: isFocused) { _, focused in
            guard focused else { return }
            onFocus?(item)
        }
    }

    private var layoutStyle: PosterCardLayoutStyle {
        isLandscapeRail ? .landscape : .row
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard direction == .up, kind == .continueWatching else { return }
        if let onMoveUpFromContinueWatching {
            onMoveUpFromContinueWatching()
        } else {
            requestTopNavigationFocus?(.watchNow)
        }
    }

    private func handleActivation() {
        guard !isActivating else { return }

        if usesNativeZoomTransition(namespace: namespaceProvider(item.id)) {
            onSelect(item)
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
            isActivating = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 105_000_000)
            onSelect(item)
            isActivating = false
        }
    }

    private func usesNativeZoomTransition(namespace: Namespace.ID?) -> Bool {
        guard namespace != nil else { return false }
        if #available(tvOS 18.0, *) {
            return true
        }
        return false
    }
}

private struct TVHomeShelfCard: View {
    let item: MediaItem
    let kind: HomeSectionKind
    let ranking: Int?
    let layoutStyle: PosterCardLayoutStyle
    let progress: Double?
    let optimizationStatus: ApplePlaybackOptimizationStatus?
    let namespace: Namespace.ID?
    let transitionSourceID: String
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let isFocused: Bool
    let isActivating: Bool
    let usesNativeZoomTransition: Bool

    var body: some View {
        let activationPhase = isActivating && !usesNativeZoomTransition

        ZStack(alignment: .bottomLeading) {
            PosterCardArtworkView(
                item: item,
                apiClient: apiClient,
                imagePipeline: imagePipeline,
                layoutStyle: layoutStyle,
                namespace: namespace,
                transitionSourceID: transitionSourceID,
                ranking: nil,
                progress: usesTVContinueWatchingStyle ? nil : progress,
                optimizationStatus: optimizationStatus,
                showsProgressOverlay: !usesTVContinueWatchingStyle,
                showsTopTrailingBadges: false
            )

            LinearGradient(
                stops: gradientStops,
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            defaultOverlay
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color.white.opacity(0.03), in: cardShape)
        .overlay {
            cardShape
                .stroke(
                    Color.white.opacity(isFocused ? 0.18 : 0.08),
                    lineWidth: isFocused ? 1.2 : 0.9
                )
        }
        .clipShape(cardShape)
        .contentShape(cardShape)
        .tvMotionFocus(.posterCard, isFocused: isFocused)
        .scaleEffect(activationPhase ? 1.075 : 1, anchor: .center)
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isActivating)
        .animation(TVMotion.focusAnimation, value: isFocused)
        .accessibilityElement(children: .combine)
    }

    private var defaultOverlay: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            HStack(alignment: .center, spacing: 10) {
                Text(eyebrowText.uppercased())
                    .font(.system(size: eyebrowFontSize, weight: .medium, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(isFocused ? 0.82 : 0.66))

                Spacer(minLength: 0)

                playbackStatusBadge
            }

            Text(primaryTitle)
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(layoutStyle == .landscape ? 2 : 3)

            if let secondaryTitle {
                Text(secondaryTitle)
                    .font(.system(size: secondaryFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(isFocused ? 0.84 : 0.74))
                    .lineLimit(layoutStyle == .landscape ? 2 : 1)
            }

            HStack(spacing: 10) {
                if usesTVContinueWatchingStyle {
                    Image(systemName: "play.fill")
                        .font(.system(size: footerFontSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))

                    TVContinueWatchingInlineProgressTrack(
                        progress: resolvedProgress,
                        width: 54
                    )

                    if let footerText = continueWatchingFooterText {
                        Text(footerText)
                            .font(.system(size: footerFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                    }
                } else {
                    if let runtime = item.runtimeDisplayText {
                        Label(runtime, systemImage: "play.fill")
                            .font(.system(size: footerFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                    } else if let year = item.year {
                        Text(String(year))
                            .font(.system(size: footerFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                    }

                    if let metadataText {
                        Text(metadataText)
                            .font(.system(size: footerFontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var primaryTitle: String {
        if item.mediaType == .episode, let seriesName = item.seriesName, !seriesName.isEmpty {
            return seriesName
        }
        return item.name
    }

    private var secondaryTitle: String? {
        if layoutStyle == .landscape {
            return nil
        }
        guard item.mediaType == .episode, let episodeTitle = episodeTitle else { return nil }
        return episodeTitle
    }

    private var episodeTitle: String? {
        guard let seriesName = item.seriesName, !seriesName.isEmpty, seriesName != item.name else {
            return nil
        }
        return item.name
    }

    private var metadataText: String? {
        if item.mediaType == .episode,
           let season = item.parentIndexNumber,
           let episode = item.indexNumber {
            return "S\(season) • E\(episode)"
        }

        if let firstGenre = item.genres.first, layoutStyle == .landscape {
            return firstGenre
        }

        return nil
    }

    private var continueWatchingFooterText: String? {
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

    private var resolvedProgress: Double {
        min(max(progress ?? item.playbackProgress ?? 0, 0), 1)
    }

    private var usesTVContinueWatchingStyle: Bool {
        kind == .continueWatching && layoutStyle == .landscape
    }

    private var eyebrowText: String {
        if let ranking {
            return "#\(ranking) \(kind == .trending ? "Trending" : "Featured")"
        }

        switch item.mediaType {
        case .episode:
            if let episode = item.indexNumber {
                return "Episode \(episode)"
            }
            return "Episode"
        case .movie:
            return "Movie"
        case .series:
            return "Series"
        case .season:
            return "Season"
        case .unknown:
            return "Library"
        }
    }

    @ViewBuilder
    private var playbackStatusBadge: some View {
        if layoutStyle == .landscape {
            EmptyView()
        } else if item.isPlayed {
            TVHomePlaybackStatusBadge(
                text: "Watched",
                systemImage: "checkmark.circle.fill",
                tint: Color(red: 0.78, green: 0.95, blue: 0.82)
            )
        } else if let positionText = item.playbackPositionDisplayText {
            TVHomePlaybackStatusBadge(
                text: positionText,
                systemImage: "play.circle.fill",
                tint: Color.white.opacity(0.92)
            )
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: layoutStyle == .landscape ? 30 : 26, style: .continuous)
    }

    private var cardWidth: CGFloat {
        switch layoutStyle {
        case .row:
            return 220
        case .grid:
            return 240
        case .landscape:
            return 400
        }
    }

    private var cardHeight: CGFloat {
        switch layoutStyle {
        case .landscape:
            return cardWidth * (9.0 / 16.0)
        default:
            return cardWidth * 1.55
        }
    }

    private var contentPadding: CGFloat {
        layoutStyle == .landscape ? 22 : 18
    }

    private var contentSpacing: CGFloat {
        layoutStyle == .landscape ? 12 : 8
    }

    private var eyebrowFontSize: CGFloat {
        layoutStyle == .landscape ? 14 : 12
    }

    private var titleFontSize: CGFloat {
        layoutStyle == .landscape ? 28 : 22
    }

    private var secondaryFontSize: CGFloat {
        layoutStyle == .landscape ? 18 : 15
    }

    private var footerFontSize: CGFloat {
        layoutStyle == .landscape ? 14 : 13
    }

    private var gradientStops: [Gradient.Stop] {
        if layoutStyle == .landscape {
            return [
                .init(color: .clear, location: 0.10),
                .init(color: .black.opacity(0.10), location: 0.34),
                .init(color: .black.opacity(0.42), location: 0.58),
                .init(color: .black.opacity(0.82), location: 0.82),
                .init(color: .black.opacity(0.96), location: 1)
            ]
        }

        return [
            .init(color: .clear, location: 0.14),
            .init(color: .black.opacity(0.10), location: 0.44),
            .init(color: .black.opacity(0.48), location: 0.70),
            .init(color: .black.opacity(0.88), location: 0.92),
            .init(color: .black.opacity(0.96), location: 1)
        ]
    }
}

private struct TVContinueWatchingInlineProgressTrack: View {
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

private struct TVHomePlaybackStatusBadge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.24), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.9)
        }
    }
}

private enum TVHomeWarmupScope {
    static let hero = "home.hero"
    static let focus = "home.focus"
}

private enum TVHomeReturnTarget: Equatable {
    case featured(itemID: String)
    case row(rowID: String, itemID: String)
}

private struct TVHomeItemFocusModifier: ViewModifier {
    let itemID: String
    let focusedItemID: FocusState<String?>.Binding?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let focusedItemID {
            content.focused(focusedItemID, equals: itemID)
        } else {
            content
        }
    }
}
#endif

#if os(iOS)
private struct ImmersiveHomeRowCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.reelFinDisplayDensity) private var displayDensity

    let item: MediaItem
    let progress: Double?
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let namespace: Namespace.ID?
    let transitionSourceID: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.18),
                    .init(color: .black.opacity(0.12), location: 0.42),
                    .init(color: .black.opacity(0.48), location: 0.66),
                    .init(color: .black.opacity(0.84), location: 0.88),
                    .init(color: .black.opacity(0.96), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(cardShape)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                ImmersiveRowArtworkTitleView(
                    itemID: imageItemID,
                    fallbackTitle: primaryTitle,
                    apiClient: apiClient,
                    imagePipeline: imagePipeline,
                    maxWidth: titleMaxWidth,
                    maxHeight: titleMaxHeight,
                    fallbackFontSize: titleFontSize
                )
                .padding(.top, titleTopPadding)
                .padding(.horizontal, contentHorizontalPadding)

                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.94))

                    ImmersiveRowProgressTrack(
                        progress: resolvedProgress,
                        width: progressTrackWidth
                    )

                    if let footerText {
                        Text(footerText)
                            .font(.system(size: metadataFontSize, weight: .bold))
                            .foregroundStyle(.white.opacity(0.90))
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.26), radius: 2, x: 0, y: 1)
                    }
                }
                .padding(.horizontal, contentHorizontalPadding)
                .padding(.bottom, contentBottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color.white.opacity(0.04), in: cardShape)
        .overlay {
            cardShape
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        }
        .clipShape(cardShape)
        .modifier(MatchedCardModifier(itemID: transitionSourceID ?? item.id, namespace: namespace))
        .contentShape(cardShape)
        .shadow(color: .black.opacity(0.26), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var artwork: some View {
        let image = CachedRemoteImage(
            itemID: imageItemID,
            type: .backdrop,
            width: Int(cardWidth * 2),
            quality: 86,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
        .frame(width: cardWidth, height: cardHeight)
        .clipped()

        image
    }

    private var imageItemID: String {
        item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
    }

    private var primaryTitle: String {
        if item.mediaType == .episode, let seriesName = item.seriesName, !seriesName.isEmpty {
            return seriesName
        }
        return item.name
    }

    private var footerText: String? {
        var values: [String] = []

        if let season = item.parentIndexNumber, let episode = item.indexNumber {
            values.append("S\(season), E\(episode)")
        }

        if let runtime = item.runtimeDisplayText {
            values.append(runtime)
        } else if let position = item.playbackPositionDisplayText {
            values.append(position)
        } else if let year = item.year {
            values.append(String(year))
        }

        return values.isEmpty ? nil : values.joined(separator: " • ")
    }

    private var resolvedProgress: Double {
        min(max(progress ?? item.playbackProgress ?? 0, 0), 1)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }

    private var cardWidth: CGFloat {
        displayDensity.scaledVisualSize(horizontalSizeClass == .compact ? 296 : 420)
    }

    private var cardHeight: CGFloat {
        cardWidth * (9.0 / 16.0)
    }

    private var titleFontSize: CGFloat {
        displayDensity.scaledTextSize(horizontalSizeClass == .compact ? 22 : 28)
    }

    private var metadataFontSize: CGFloat {
        displayDensity.scaledTextSize(horizontalSizeClass == .compact ? 15 : 18)
    }

    private var progressTrackWidth: CGFloat {
        displayDensity.scaledVisualSize(horizontalSizeClass == .compact ? 38 : 46)
    }

    private var contentHorizontalPadding: CGFloat {
        displayDensity.scaledSpacing(horizontalSizeClass == .compact ? 16 : 20)
    }

    private var contentBottomPadding: CGFloat {
        displayDensity.scaledSpacing(horizontalSizeClass == .compact ? 14 : 18)
    }

    private var titleTopPadding: CGFloat {
        displayDensity.scaledSpacing(horizontalSizeClass == .compact ? 18 : 24)
    }

    private var titleMaxWidth: CGFloat {
        displayDensity.scaledVisualSize(horizontalSizeClass == .compact ? 190 : 250)
    }

    private var titleMaxHeight: CGFloat {
        displayDensity.scaledVisualSize(horizontalSizeClass == .compact ? 44 : 58)
    }
}

private struct ImmersiveRowArtworkTitleView: View {
    let itemID: String
    let fallbackTitle: String
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let fallbackFontSize: CGFloat

    @State private var logoImage: UIImage?

    var body: some View {
        Group {
            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .leading)
                    .shadow(color: .black.opacity(0.30), radius: 8, x: 0, y: 4)
                    .transition(.opacity)
            } else {
                Text(fallbackTitle.uppercased())
                    .font(.system(size: fallbackFontSize, weight: .heavy, design: .rounded))
                    .tracking(fallbackTracking)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: maxWidth, alignment: .leading)
                    .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 3)
            }
        }
        .task(id: itemID) {
            await loadLogo()
        }
    }

    private func loadLogo() async {
        logoImage = nil

        guard let url = await apiClient.imageURL(
            for: itemID,
            type: .logo,
            width: ArtworkRequestProfile.logo.width,
            quality: ArtworkRequestProfile.logo.quality
        ) else {
            return
        }

        // Mock screenshot mode serves opaque placeholder images for logo requests.
        // Generate a clean text-based wordmark for mock screenshots so the card
        // keeps the same composition as the production UI.
        if url.scheme == "mock-image" {
            logoImage = mockLogoImage()
            return
        }

        if let cached = await imagePipeline.cachedImage(for: url) {
            withAnimation(.easeInOut(duration: 0.18)) {
                logoImage = cached
            }
            return
        }

        do {
            let downloaded = try await imagePipeline.image(for: url)
            withAnimation(.easeInOut(duration: 0.18)) {
                logoImage = downloaded
            }
        } catch {
            return
        }
    }

    private var fallbackTracking: CGFloat {
        fallbackTitle.count <= 8 ? 5 : 1.4
    }

    private func mockLogoImage() -> UIImage {
        let size = CGSize(width: max(maxWidth * 2.6, 260), height: max(maxHeight * 2.4, 100))
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { _ in
            let text = fallbackTitle.uppercased() as NSString
            let style = NSMutableParagraphStyle()
            style.alignment = .left
            style.lineBreakMode = .byTruncatingTail

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fallbackFontSize * 1.4, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: style,
                .kern: fallbackTracking
            ]

            text.draw(
                in: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                withAttributes: attributes
            )
        }
    }
}

private struct ImmersiveRowProgressTrack: View {
    let progress: Double
    let width: CGFloat

    var body: some View {
        let clampedProgress = min(max(progress, 0), 1)

        Capsule()
            .fill(Color.white.opacity(0.28))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: clampedProgress > 0 ? max(width * clampedProgress, 10) : 0)
            }
            .frame(width: width, height: 6)
        .accessibilityHidden(true)
    }
}
#endif

public struct SectionRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.reelFinDisplayDensity) private var displayDensity

    private let title: String
    private let items: [MediaItem]
    private let kind: HomeSectionKind
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let namespaceProvider: (String) -> Namespace.ID?
    private let transitionSourceIDProvider: (String, String?) -> String
    private let focusedItemID: FocusState<String?>.Binding?
    private let optimizationStatusProvider: ((MediaItem) -> ApplePlaybackOptimizationStatus?)?
    private let isLoadingMore: Bool
    private let onFocus: ((MediaItem, [MediaItem]) -> Void)?
    private let onMoveUpFromContinueWatching: (() -> Void)?
    private let onOpenSection: (() -> Void)?
    private let onItemAppear: ((MediaItem) -> Void)?
    private let onSelect: (MediaItem, String) -> Void

    public init(
        title: String,
        items: [MediaItem],
        kind: HomeSectionKind,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        namespaceProvider: @escaping (String) -> Namespace.ID?,
        transitionSourceIDProvider: @escaping (String, String?) -> String = { itemID, _ in itemID },
        focusedItemID: FocusState<String?>.Binding? = nil,
        optimizationStatusProvider: ((MediaItem) -> ApplePlaybackOptimizationStatus?)? = nil,
        isLoadingMore: Bool = false,
        onFocus: ((MediaItem, [MediaItem]) -> Void)? = nil,
        onMoveUpFromContinueWatching: (() -> Void)? = nil,
        onOpenSection: (() -> Void)? = nil,
        onItemAppear: ((MediaItem) -> Void)? = nil,
        onSelect: @escaping (MediaItem, String) -> Void
    ) {
        self.title = title
        self.items = items
        self.kind = kind
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.namespaceProvider = namespaceProvider
        self.transitionSourceIDProvider = transitionSourceIDProvider
        self.focusedItemID = focusedItemID
        self.optimizationStatusProvider = optimizationStatusProvider
        self.isLoadingMore = isLoadingMore
        self.onFocus = onFocus
        self.onMoveUpFromContinueWatching = onMoveUpFromContinueWatching
        self.onOpenSection = onOpenSection
        self.onItemAppear = onItemAppear
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: sectionHeaderSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(sectionTitleFont)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .leading)

#if os(iOS)
                Button {
                    onOpenSection?()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(sectionChevronFont)
                        .foregroundStyle(sectionChevronColor)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(title)")
#endif
            }
            .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: cardSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let transitionSourceID = transitionSourceIDProvider(item.id, nil)
                        let optimizationStatus = optimizationStatusProvider?(item)
#if os(tvOS)
                        TVCardButton(
                            item: item,
                            index: index,
                            kind: kind,
                            isTop10: isTop10,
                            apiClient: apiClient,
                            imagePipeline: imagePipeline,
                            namespaceProvider: namespaceProvider,
                            transitionSourceID: transitionSourceID,
                            focusedItemID: focusedItemID,
                            isLandscapeRail: isLandscapeRail,
                            progress: progress(for: item),
                            optimizationStatus: optimizationStatus,
                            onFocus: { focusedItem in
                                onFocus?(focusedItem, items)
                            },
                            onMoveUpFromContinueWatching: onMoveUpFromContinueWatching,
                            onSelect: { selectedItem in
                                onSelect(selectedItem, transitionSourceID)
                            }
                        )
                        .onAppear {
                            onItemAppear?(item)
                        }
#else
                        Button {
                            onSelect(item, transitionSourceID)
                        } label: {
                            if usesImmersiveLandscapeRowStyle {
                                ImmersiveHomeRowCard(
                                    item: item,
                                    progress: progress(for: item),
                                    apiClient: apiClient,
                                    imagePipeline: imagePipeline,
                                    namespace: namespaceProvider(item.id),
                                    transitionSourceID: transitionSourceID
                                )
                                .scrollTransition(axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.95)
                                }
                            } else {
                                PosterCardView(
                                    item: item,
                                    apiClient: apiClient,
                                    imagePipeline: imagePipeline,
                                    layoutStyle: isLandscapeRail ? .landscape : .row,
                                    namespace: namespaceProvider(item.id),
                                    transitionSourceID: transitionSourceID,
                                    ranking: isTop10 ? (index + 1) : nil,
                                    progress: progress(for: item),
                                    optimizationStatus: optimizationStatus,
                                    showsArtworkProgress: true,
                                    showsInlineProgress: false
                                )
                                .scrollTransition(axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.95)
                                }
                            }
                        }
                        .accessibilityIdentifier("media_card_button_\(kind.rawValue)_\(item.id)")
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                        .onAppear {
                            onItemAppear?(item)
                        }
#endif
                    }

                    if isLoadingMore {
                        ProgressView()
                            .tint(.white)
                            .frame(width: loadingMoreWidth, height: loadingMoreHeight)
                            .accessibilityLabel("Loading more")
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, railVerticalPadding)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var cardSpacing: CGFloat {
#if os(tvOS)
        return ReelFinTheme.tvRailSpacing
#else
        if usesImmersiveLandscapeRowStyle {
            return displayDensity.scaledSpacing(18)
        }
        return displayDensity.scaledSpacing(16)
#endif
    }

    private var isTop10: Bool {
        title.lowercased().contains("top 10") || title.lowercased().contains("trending")
    }

    private var isLandscapeRail: Bool {
        kind == .continueWatching || kind == .nextUp
    }

    private var usesImmersiveLandscapeRowStyle: Bool {
        isLandscapeRail
    }

    private func progress(for item: MediaItem) -> Double? {
        if kind == .continueWatching || kind == .nextUp {
            return item.playbackProgress
        }
        return nil
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return ReelFinTheme.tvSectionHorizontalPadding
        #else
        return displayDensity.scaledSpacing(horizontalSizeClass == .compact ? 24 : 40)
        #endif
    }

    private var sectionHeaderSpacing: CGFloat {
        #if os(tvOS)
        return ReelFinTheme.tvSectionHeaderSpacing
        #else
        return displayDensity.scaledSpacing(usesImmersiveLandscapeRowStyle ? 12 : 14)
        #endif
    }

    private var railVerticalPadding: CGFloat {
        #if os(tvOS)
        return ReelFinTheme.tvRailVerticalPadding
        #else
        return displayDensity.scaledSpacing(usesImmersiveLandscapeRowStyle ? 10 : 14)
        #endif
    }

    private var loadingMoreWidth: CGFloat {
        isLandscapeRail
            ? displayDensity.scaledVisualSize(86)
            : PosterCardMetrics.posterWidth(
                for: .row,
                compact: horizontalSizeClass == .compact,
                displayDensity: displayDensity
            )
    }

    private var loadingMoreHeight: CGFloat {
        if isLandscapeRail {
            return loadingMoreWidth * (9.0 / 16.0)
        }

        return PosterCardMetrics.posterWidth(
            for: .row,
            compact: horizontalSizeClass == .compact,
            displayDensity: displayDensity
        ) * 1.55
    }

    private var sectionTitleFont: Font {
        #if os(tvOS)
        return .system(size: 24, weight: .bold, design: .rounded)
        #else
        if usesImmersiveLandscapeRowStyle {
            return .system(size: displayDensity.scaledTextSize(30), weight: .heavy)
        }
        return .system(size: displayDensity.scaledTextSize(24), weight: .bold, design: .rounded)
        #endif
    }

    private var sectionChevronFont: Font {
        #if os(tvOS)
        return .body.weight(.semibold)
        #else
        return usesImmersiveLandscapeRowStyle
            ? .system(size: displayDensity.scaledTextSize(28), weight: .bold)
            : .system(size: displayDensity.scaledTextSize(17), weight: .semibold)
        #endif
    }

    private var sectionChevronColor: Color {
        #if os(tvOS)
        return .white.opacity(0.4)
        #else
        return usesImmersiveLandscapeRowStyle ? .white.opacity(0.7) : .white.opacity(0.4)
        #endif
    }
}

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.reelFinDisplayDensity) private var displayDensity
    @State private var viewModel: HomeViewModel
    @Namespace private var posterNamespace
#if os(tvOS)
    @FocusState private var focusedHomeItemID: String?
#endif

    private let dependencies: ReelFinDependencies
    private let tvRefreshRequest: Int
    private let tvHeroFocusRequest: Int
    @State private var scrollInterval: SignpostInterval?
    @State private var isCustomizationPresented = false
    @State private var selectedDetailNamespace: Namespace.ID?
    @State private var selectedDetailTransitionSourceID: String?
    @State private var selectedDetailContextItems: [MediaItem] = []
    @State private var selectedDetailContextTitle: String?
    @State private var selectedHomeSectionRow: HomeRow?
#if os(tvOS)
    @State private var lastSelectedHomeRowID: String?
    @State private var lastSelectedHomeItemID: String?
    @State private var featuredHeroItemID: String?
    @State private var homeReturnTarget: TVHomeReturnTarget?
    @State private var homeReturnRequest = 0
    @State private var localHeroFocusRequest = 0
    @State private var tvOpeningArtworkItem: MediaItem?
    @State private var tvOpeningArtworkVisible = false
    @State private var tvDetailFocusRequest = 0
#endif
    @State private var playerSession: PlaybackSessionController?
    @State private var customEngine: CustomPlaybackEngine?
    @State private var playerPresentation: HomePlayerPresentation?
    @State private var customPrewarmer: CustomPlayerPrewarmer?
    @State private var isPreparingPlayback = false
    @State private var playbackErrorMessage: String?
    @State private var liveUITestTargetOpenAttempted = false
    @State private var warmupTask: Task<Void, Never>?
    @State private var appleOptimizationStatuses: [String: ApplePlaybackOptimizationStatus] = [:]

#if os(iOS)
    @State private var ambientItem: MediaItem?
#elseif os(tvOS)
    @StateObject private var tvScreenState: TVHomeScreenState
#endif

    init(dependencies: ReelFinDependencies, tvRefreshRequest: Int = 0, tvHeroFocusRequest: Int = 0) {
        _viewModel = State(initialValue: HomeViewModel(dependencies: dependencies))
#if os(tvOS)
        _tvScreenState = StateObject(
            wrappedValue: TVHomeScreenState(
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline
            )
        )
#endif
        self.dependencies = dependencies
        self.tvRefreshRequest = tvRefreshRequest
        self.tvHeroFocusRequest = tvHeroFocusRequest
    }

    var body: some View {
        let visibleRows = viewModel.visibleRows

        mainContent(visibleRows: visibleRows)
        .onDisappear {
            handleHomeDisappear()
        }
        .navigationDestination(
            isPresented: nativeDetailNavigationBinding
        ) {
            if let item = viewModel.selectedItem {
                DetailView(
                    dependencies: dependencies,
                    item: item,
                    preferredEpisode: viewModel.selectedEpisode,
                    contextItems: selectedDetailContextItems,
                    contextTitle: selectedDetailContextTitle,
                    namespace: selectedDetailNamespace,
                    transitionSourceID: selectedDetailTransitionSourceID,
                    onDisplayedSourceItemChange: handleDisplayedDetailSourceItemChange,
                    onDismissRequest: dismissDetailPresentation
                )
            }
        }
        .navigationDestination(
            isPresented: Binding(
                get: { selectedHomeSectionRow != nil },
                set: { newValue in
                    if !newValue {
                        selectedHomeSectionRow = nil
                    }
                }
            )
        ) {
            if let selectedHomeSectionRow {
                HomeSectionLibraryView(
                    dependencies: dependencies,
                    homeViewModel: viewModel,
                    row: selectedHomeSectionRow
                )
            }
        }
        .task {
            await viewModel.load()
            await preloadOptimizationStatuses()
            await openLiveUITestTargetIfRequested()
#if os(tvOS)
            if let item = viewModel.feed.featured.first {
                tvScreenState.scheduleNavigationAppearance(for: item)
            } else {
                tvScreenState.navigationAppearance = .neutral
            }
#endif
        }
#if os(tvOS)
        .onChange(of: tvRefreshRequest) { _, newValue in
            guard newValue > 0 else { return }
            triggerTVHomeRefresh()
        }
#endif
#if os(iOS)
        .fullScreenCover(item: $playerPresentation, onDismiss: handlePlayerDismissal) { presentation in
            homePlayerContent(for: presentation)
        }
#else
        // Match DetailView's proven tvOS host. A fullScreenCover from the inline Home/detail stack
        // can retain a frozen navigation snapshot above live playback on physical Apple TV.
        .disabled(playerPresentation != nil)
        .overlay {
            tvHomePlayerPresentation
                .zIndex(100)
        }
        .preference(
            key: TVTopNavigationVisibilityPreferenceKey.self,
            value: HomePlayerPresentationPolicy.showsTopNavigation(
                hasActivePlayer: playerPresentation != nil
            )
        )
#endif
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { playbackErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        playbackErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                playbackErrorMessage = nil
            }
        } message: {
            Text(playbackErrorMessage ?? "Unknown error")
        }
        .alert("Personalization is coming soon", isPresented: $isCustomizationPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Home customization will be available in an upcoming update.")
        }
#if os(iOS) && !targetEnvironment(macCatalyst)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }

    @ViewBuilder
    private func homePlayerContent(for presentation: HomePlayerPresentation) -> some View {
        switch presentation.content {
        case .custom(let engine):
            CustomPlayerView(
                engine: engine,
                launchContext: CustomPlayerView.LaunchContext(
                    item: engine.currentMediaItem ?? presentation.item,
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline
                ),
                onRequestDismiss: { handlePlayerDismissal() }
            )
        case .legacy(let session):
            PlayerView(
                session: session,
                item: presentation.item,
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline
            )
        }
    }

#if os(tvOS)
    @ViewBuilder
    private var tvHomePlayerPresentation: some View {
        if let playerPresentation {
            ZStack {
                Color.black.ignoresSafeArea()
                homePlayerContent(for: playerPresentation)
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .onExitCommand {
                handlePlayerDismissal()
            }
        }
    }
#endif

    @ViewBuilder
    private func mainContent(
        visibleRows: [HomeRow]
    ) -> some View {
#if os(tvOS)
        TVHomeScreen(navigationAppearance: tvScreenState.navigationAppearance) {
            ZStack(alignment: .topTrailing) {
                // No live Gaussian blur over the whole image-dense home while a detail is open —
                // that held a heavy GPU pass for the entire presentation and slowed open/close.
                // Scale + dim + a flat scrim reads the same from 3 m for a fraction of the cost.
                homeScrollContent(visibleRows: visibleRows)
                    // The detail is an inline overlay on tvOS, so the Home focus tree otherwise
                    // stays alive behind it. Select then activates the hidden shelf card again
                    // instead of the visible Play button. Removing Home from focus participation
                    // lets DetailView's default focus resolve immediately and deterministically.
                    .disabled(viewModel.selectedItem != nil)
                    .scaleEffect(viewModel.selectedItem == nil ? 1 : 0.982)
                    .opacity(viewModel.selectedItem == nil ? 1 : 0.34)
                    .overlay {
                        Color.black.opacity(viewModel.selectedItem == nil ? 0 : 0.45)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
                    .animation(tvDetailPresentationAnimation, value: viewModel.selectedItem?.id)

                TVHomeRefreshStatusView(isRefreshing: viewModel.isRefreshing && !viewModel.isInitialLoading)
                    .padding(.top, tvRefreshStatusTopPadding)
                    .padding(.trailing, tvRefreshStatusTrailingPadding)
                    .zIndex(2)

                tvInlineDetailPresentation
            }
        }
#else
        ZStack(alignment: .bottom) {
            CinematicBackdropView(
                item: ambientItem,
                fallbackItem: viewModel.feed.featured.first,
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline,
                sharpnessOpacity: 0.78,
                blurOpacity: 0.56,
                bottomFadeStart: 0.5,
                leadingScrimOpacity: tvHomeLeadingScrimOpacity,
                edgeVignetteOpacity: tvHomeEdgeVignetteOpacity
            )
            .ignoresSafeArea(edges: .top)

            homeScrollContent(visibleRows: visibleRows)
        }
#endif
    }

    private func homeScrollContent(visibleRows: [HomeRow]) -> some View {
#if os(iOS)
        StickyBlurHeader(
            maxBlurRadius: 12,
            fadeExtension: 84,
            tintOpacityTop: 0.18,
            tintOpacityMiddle: 0.06,
            statusBarBlurOpacity: 0.52,
            contentTopInset: 0,
            visibility: .revealOnScroll(distance: 124, minimumEffectOpacity: 0.02),
            refreshAction: {
                await viewModel.manualRefresh()
            }
        ) { progress in
            homeStickyChrome
                .opacity(homeHeaderOpacity(for: progress))
                .offset(y: (1 - homeHeaderOpacity(for: progress)) * -8)
                .padding(.top, stickyHeaderTopPadding)
                .padding(.bottom, 12)
                .accessibilityIdentifier("home_sticky_blur_header")
        } content: {
            homeScrollSections(visibleRows: visibleRows)
        }
        .background(ReelFinTheme.pageGradient.ignoresSafeArea())
        .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { _ in
                    if scrollInterval == nil {
                        scrollInterval = SignpostInterval(signposter: Signpost.homeScroll, name: "home_scroll_session")
                    }
                }
                .onEnded { _ in
                    scrollInterval?.end(name: "home_scroll_session")
                    scrollInterval = nil
                }
        )
#else
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                homeScrollSections(visibleRows: visibleRows)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            #if os(tvOS)
            .onChange(of: homeReturnRequest) { _, _ in
                restoreHomeSelection(using: proxy)
            }
            .onChange(of: tvHeroFocusRequest) { _, _ in
                focusFeaturedAction(using: proxy)
            }
            .onChange(of: localHeroFocusRequest) { _, _ in
                focusFeaturedAction(using: proxy)
            }
            #endif
        }
        .background(ReelFinTheme.pageGradient.ignoresSafeArea())
#if os(tvOS)
        .contentMargins(.zero, for: .scrollContent)
#endif
#endif
    }

    @ViewBuilder
    private func homeScrollSections(visibleRows: [HomeRow]) -> some View {
        LazyVStack(alignment: .leading, spacing: sectionSpacing) {
            if viewModel.isInitialLoading && visibleRows.isEmpty {
                loadingSkeleton
                    .padding(.top, 48)
            } else if visibleRows.isEmpty && viewModel.feed.featured.isEmpty {
                emptyState
                    .padding(.top, 48)
            } else {
                featuredSection

                ForEach(visibleRows) { row in
                    SectionRow(
                        title: row.title,
                        items: row.items,
                        kind: row.kind,
                        apiClient: dependencies.apiClient,
                        imagePipeline: dependencies.imagePipeline,
                        namespaceProvider: { _ in
                            posterNamespace
                        },
                        transitionSourceIDProvider: { itemID, occurrenceID in
                            HomeCardTransitionSource.id(
                                rowID: row.id,
                                itemID: itemID,
                                occurrenceID: occurrenceID
                            )
                        },
                        focusedItemID: homeFocusedItemBinding,
                        optimizationStatusProvider: { item in
                            appleOptimizationStatuses[item.id]
                        },
                        isLoadingMore: viewModel.isLoadingMore(rowID: row.id),
                        onFocus: { item, neighbors in
                            handleFocusedItem(item, neighbors: neighbors)
                        },
                        onMoveUpFromContinueWatching: continueWatchingHeroFocusAction(for: row.kind),
                        onOpenSection: {
                            selectedHomeSectionRow = row
                        },
                        onItemAppear: { item in
                            Task {
                                await viewModel.loadMoreIfNeeded(rowID: row.id, visibleItemID: item.id)
                            }
                        },
                        onSelect: { item, transitionSourceID in
                            selectedDetailNamespace = posterNamespace
                            selectedDetailTransitionSourceID = transitionSourceID
                            selectedDetailContextItems = row.items
                            selectedDetailContextTitle = row.title
#if os(tvOS)
                            lastSelectedHomeRowID = row.id
                            lastSelectedHomeItemID = item.id
                            homeReturnTarget = .row(rowID: row.id, itemID: item.id)
#endif
#if os(iOS)
                            ambientItem = item
                            scheduleWarmup(
                                for: item,
                                neighbors: row.items,
                                settleDelayNanoseconds: 0
                            )
#endif
                            let detailItemID = item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
                            Task {
                                await DetailPresentationTelemetry.shared.beginNavigation(for: detailItemID)
                            }
                            presentDetail(item)
                        }
                    )
                    .id(row.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

#if os(iOS)
            Color.clear
                .frame(height: 116)
                .accessibilityHidden(true)
#endif
        }
    }

    @ViewBuilder
    private var featuredSection: some View {
        if !viewModel.feed.featured.isEmpty {
            #if os(tvOS)
            HeroCarouselView(
                items: featuredItems,
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline,
                selectedItemID: $featuredHeroItemID,
                transitionNamespace: posterNamespace,
                transitionSourceID: { item in
                    HomeFeaturedTransitionSource.id(itemID: item.id)
                },
                usesTVInlineDetailTransition: true,
                tvFocusedItemID: homeFocusedItemBinding,
                tvPrimaryActionFocusID: featuredPrimaryActionFocusID,
                onVisibleItemChange: { item in
                    scheduleWarmup(
                        for: item,
                        neighbors: featuredContextItems(around: item),
                        scope: TVHomeWarmupScope.hero,
                        settleDelayNanoseconds: 0
                    )
                    featuredHeroItemID = item.id
                    tvScreenState.scheduleNavigationAppearance(for: item)
                },
                onPlay: handleFeaturedPlay,
                onTap: handleFeaturedSelection
            )
            .id(featuredScrollAnchorID)
            #else
            HeroCarouselView(
                items: Array(viewModel.feed.featured.prefix(10)),
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline,
                transitionNamespace: posterNamespace,
                transitionSourceID: { item in
                    HomeFeaturedTransitionSource.id(itemID: item.id)
                },
                onPlay: handleFeaturedPlay,
                onToggleWatchlist: viewModel.toggleFeaturedWatchlist,
                onTap: handleFeaturedSelection
            )
            #endif
        }
    }

    private var topChrome: some View {
        HStack(alignment: .top) {
            Text("ReelFin")
                .reelFinTitleStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            HStack(spacing: 12) {
                if viewModel.isRefreshing || viewModel.isInitialLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 4)
                }

#if os(iOS)
                Button {
                    isCustomizationPresented = true
                } label: {
                    topIcon(symbol: "slider.horizontal.3", accessibilityLabel: "Customize Home")
                }
                .buttonStyle(.plain)
#endif
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .shadow(color: .black.opacity(0.3), radius: 6)
    }

    private var homeStickyChrome: some View {
        HStack(spacing: 12) {
            Spacer()

            if viewModel.isRefreshing || viewModel.isInitialLoading {
                ProgressView()
                    .tint(.white)
                    .padding(.trailing, 4)
            }

            Button {
                isCustomizationPresented = true
            } label: {
                topIcon(symbol: "slider.horizontal.3", accessibilityLabel: "Customize Home")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, horizontalPadding)
        .shadow(color: .black.opacity(0.24), radius: 5)
    }

    private var sectionSpacing: CGFloat {
        #if os(tvOS)
        return ReelFinTheme.tvSectionSpacing
        #else
        return displayDensity.scaledSpacing(24)
        #endif
    }

    private var stickyHeaderTopPadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 12
    }

    private func homeHeaderOpacity(for progress: CGFloat) -> CGFloat {
        let easedProgress = max(0, min((progress - 0.82) / 0.14, 1))
        return easedProgress * easedProgress
    }

    private func topIcon(symbol: String, accessibilityLabel: String) -> some View {
        Image(systemName: symbol)
            .font(.headline.weight(.semibold))
            .frame(width: 44, height: 44)
            .foregroundStyle(.white)
            .glassPanelStyle(cornerRadius: 22)
            .accessibilityLabel(accessibilityLabel)
    }

    private var featuredItems: [MediaItem] {
        Array(viewModel.feed.featured.prefix(10))
    }

    private var homeFocusedItemBinding: FocusState<String?>.Binding? {
#if os(tvOS)
        $focusedHomeItemID
#else
        nil
#endif
    }

    private var nativeDetailNavigationBinding: Binding<Bool> {
        Binding(
            get: {
#if os(tvOS)
                false
#else
                viewModel.selectedItem != nil
#endif
            },
            set: { isPresented in
                guard !isPresented else { return }
                dismissDetailPresentation()
            }
        )
    }

#if os(tvOS)
    @ViewBuilder
    private var tvInlineDetailPresentation: some View {
        if let item = viewModel.selectedItem {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                DetailView(
                    dependencies: dependencies,
                    item: item,
                    preferredEpisode: viewModel.selectedEpisode,
                    contextItems: selectedDetailContextItems,
                    contextTitle: selectedDetailContextTitle,
                    namespace: selectedDetailNamespace,
                    transitionSourceID: selectedDetailTransitionSourceID,
                    tvPresentationFocusRequest: tvDetailFocusRequest,
                    onDisplayedSourceItemChange: handleDisplayedDetailSourceItemChange,
                    onDismissRequest: dismissDetailPresentation
                )
                .ignoresSafeArea()

                if let tvOpeningArtworkItem {
                    TVDetailOpeningArtworkView(
                        item: tvOpeningArtworkItem,
                        apiClient: dependencies.apiClient,
                        imagePipeline: dependencies.imagePipeline
                    )
                    .modifier(TVInlineDetailArtworkDestinationModifier(
                        namespace: selectedDetailNamespace,
                        sourceID: selectedDetailTransitionSourceID
                    ))
                    .opacity(tvOpeningArtworkVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .zIndex(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .transition(tvInlineDetailTransition)
            .zIndex(10)
        }
    }

    private var tvInlineDetailTransition: AnyTransition {
        // The detail FADES while it zooms, so the (dimmed, scaled) home stays visible through the
        // whole move — the iOS "same page" continuity. A bare scale popped an opaque black sheet
        // over the home on frame one, which read as a hard cut between two screens.
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
        )
    }

    private var tvDetailPresentationAnimation: Animation {
        .smooth(duration: 0.38, extraBounce: 0.04)
    }
#endif

    private func preloadOptimizationStatuses() async {
        guard let heroItem = featuredItems.first else { return }
        await refreshOptimizationStatuses(for: [heroItem])
    }

    private var tvHomeLeadingScrimOpacity: Double {
        #if os(tvOS)
        return 0.42
        #else
        return 0.82
        #endif
    }

    private var tvHomeEdgeVignetteOpacity: Double {
        #if os(tvOS)
        return 0.08
        #else
        return 0.58
        #endif
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoundedRectangle(cornerRadius: ReelFinTheme.glassPanelCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(height: heroSkeletonHeight)
                .overlay(ShimmerView())
                .padding(.horizontal, horizontalPadding)

            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 120, height: 24)
                        .padding(.horizontal, horizontalPadding)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: ReelFinTheme.cardCornerRadius, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(width: rowCardWidth, height: rowCardHeight)
                                    .overlay(ShimmerView())
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white.opacity(0.88))

            Text("Your Home Is Ready")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)

            Text("We could not load rows yet. Pull to refresh or update server settings.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            Button {
                Task { await viewModel.manualRefresh() }
            } label: {
                Label("Retry Sync", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .glassPanelStyle(cornerRadius: 16)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, minHeight: isCompact ? 380 : 480)
        .padding(24)
        .glassPanelStyle(cornerRadius: ReelFinTheme.glassPanelCornerRadius)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 10)
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return ReelFinTheme.tvSectionHorizontalPadding
        #else
        return displayDensity.scaledSpacing(isCompact ? 24 : 40)
        #endif
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    private var heroSkeletonHeight: CGFloat {
        displayDensity.scaledVisualSize(horizontalSizeClass == .compact ? 500 : 600)
    }

    private var rowCardWidth: CGFloat {
        PosterCardMetrics.posterWidth(
            for: .row,
            compact: isCompact,
            displayDensity: displayDensity
        )
    }

    private var rowCardHeight: CGFloat {
        rowCardWidth * 1.55
    }

    private func handleFocusedItem(_ item: MediaItem, neighbors: [MediaItem]) {
#if os(tvOS)
        // 600ms settle: focus travels across several cards per second on tvOS — 150ms fired the
        // whole warmup chain (detail fetch + image prefetch + NextUp) for cards merely passed over.
        scheduleWarmup(
            for: item,
            neighbors: neighbors,
            scope: TVHomeWarmupScope.focus,
            settleDelayNanoseconds: 600_000_000
        )
#else
        scheduleWarmup(
            for: item,
            neighbors: neighbors,
            settleDelayNanoseconds: 150_000_000
        )
#endif
    }

    private func dismissDetailPresentation() {
#if os(tvOS)
        let closingItem = viewModel.selectedItem
        tvOpeningArtworkItem = closingItem
        tvOpeningArtworkVisible = true

        withAnimation(tvDetailPresentationAnimation) {
            focusedHomeItemID = nil
            homeReturnRequest += 1
            tvOpeningArtworkVisible = false
            viewModel.dismissDetail()
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 460_000_000)
            if viewModel.selectedItem == nil {
                tvOpeningArtworkItem = nil
            }
        }
#else
        ambientItem = nil
        viewModel.dismissDetail()
#endif
    }

    private func presentDetail(_ item: MediaItem) {
#if os(tvOS)
        let presentedItemID = presentedDetailItemID(for: item)
        tvOpeningArtworkItem = item
        tvOpeningArtworkVisible = true

        withAnimation(tvDetailPresentationAnimation, completionCriteria: .logicallyComplete) {
            viewModel.select(item: item)
        } completion: {
            guard viewModel.selectedItem?.id == presentedItemID else { return }
            tvDetailFocusRequest &+= 1
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard viewModel.selectedItem?.id == presentedItemID else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                tvOpeningArtworkVisible = false
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard viewModel.selectedItem?.id == presentedItemID else { return }
            tvOpeningArtworkItem = nil
        }
#else
        viewModel.select(item: item)
#endif
    }

#if os(iOS) || os(tvOS)
    private var liveUITestTargetItemID: String? {
        if let argumentValue = liveUITestArgumentValue(after: "-reelfin-live-ui-open-target") {
            return normalizedLiveUITestItemID(argumentValue)
        }
        guard isLiveUITestDirectTargetOpenEnabled else { return nil }
        let rawValue = ProcessInfo.processInfo.environment["REELFIN_LIVE_UI_TARGET_ITEM_ID"] ?? ""
        return normalizedLiveUITestItemID(rawValue)
    }

    private var isLiveUITestDirectTargetOpenEnabled: Bool {
        if liveUITestArgumentValue(after: "-reelfin-live-ui-open-target") != nil {
            return true
        }
        let rawValue = ProcessInfo.processInfo.environment["REELFIN_LIVE_UI_OPEN_TARGET_DIRECTLY"] ?? ""
        return ["1", "true", "yes", "on"].contains(rawValue.lowercased())
    }

    private func liveUITestArgumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = arguments.firstIndex(of: flag),
            arguments.indices.contains(arguments.index(after: flagIndex))
        else {
            return nil
        }
        let rawValue = arguments[arguments.index(after: flagIndex)]
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func normalizedLiveUITestItemID(_ rawValue: String) -> String? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }

        let patterns = [
            #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#,
            #"[0-9a-fA-F]{32}"#
        ]
        for pattern in patterns {
            if let range = trimmedValue.range(of: pattern, options: .regularExpression) {
                return trimmedValue[range].filter { $0 != "-" }.lowercased()
            }
        }
        return trimmedValue
    }

    @MainActor
    private func openLiveUITestTargetIfRequested() async {
        guard !liveUITestTargetOpenAttempted, let itemID = liveUITestTargetItemID else { return }
        liveUITestTargetOpenAttempted = true

        do {
            let item = try await dependencies.detailRepository.refreshItem(id: itemID)
            selectedDetailNamespace = nil
            selectedDetailTransitionSourceID = nil
            selectedDetailContextItems = [item]
            selectedDetailContextTitle = "Live UI Target"
            AppLog.ui.info("live_ui_target.open item=\(AppLogFormat.shortIdentifier(item.id), privacy: .public)")
            presentDetail(item)
        } catch {
            AppLog.ui.error("live_ui_target.open_failed item=\(AppLogFormat.shortIdentifier(itemID), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }
#endif

#if os(tvOS)
    private func presentedDetailItemID(for item: MediaItem) -> String {
        if item.mediaType == .episode, let parentID = item.parentID {
            return parentID
        }
        return item.id
    }
#endif

    private func featuredContextItems(around item: MediaItem) -> [MediaItem] {
        TVHeroPagingPolicy.contextItems(around: item, in: featuredItems)
    }

    private func handleFeaturedSelection(_ item: MediaItem) {
#if os(iOS)
        ambientItem = item
        scheduleWarmup(
            for: item,
            neighbors: featuredItems,
            settleDelayNanoseconds: 0
        )
#endif
        selectedDetailNamespace = posterNamespace
        selectedDetailTransitionSourceID = HomeFeaturedTransitionSource.id(itemID: item.id)
        selectedDetailContextItems = featuredItems
        selectedDetailContextTitle = "Featured"
#if os(tvOS)
        lastSelectedHomeRowID = nil
        lastSelectedHomeItemID = nil
        featuredHeroItemID = item.id
        homeReturnTarget = .featured(itemID: item.id)
#endif

        let detailItemID = item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
        Task {
            await DetailPresentationTelemetry.shared.beginNavigation(for: detailItemID)
        }

        presentDetail(item)
    }

    private func handleFeaturedPlay(_ item: MediaItem) {
        guard !isPreparingPlayback else { return }
        isPreparingPlayback = true

        Task {
            let playbackItem = await resolvePlaybackItem(for: item)
            await MainActor.run {
                isPreparingPlayback = false
            }

            guard let playbackItem else {
                await MainActor.run {
                    handleFeaturedSelection(item)
                }
                return
            }

            await launchPlayback(for: playbackItem)
        }
    }

    private func resolvePlaybackItem(for item: MediaItem) async -> MediaItem? {
        guard item.mediaType == .series else { return item }

        do {
            return try await dependencies.detailRepository.loadNextUpEpisode(seriesID: item.id)
        } catch {
            return nil
        }
    }

    @MainActor
    private func launchPlayback(for item: MediaItem) async {
        switch HomePlaybackRoute.preferred(
            useCustomPlayerEngine: dependencies.settingsStore.useCustomPlayerEngine
        ) {
        case .custom:
            startHomeCustomPlayback(item: item)
        case .legacy:
            await startHomeLegacyPlayback(item: item)
        }
    }

    @MainActor
    private func ensureHomeCustomPrewarmer() -> CustomPlayerPrewarmer? {
        if let customPrewarmer { return customPrewarmer }
        guard let store = try? CustomPlaybackEngine.sharedStore() else { return nil }
        let coordinator = PlaybackCoordinator(apiClient: dependencies.apiClient)
        let prewarmer = CustomPlayerPrewarmer(
            resolver: JellyfinOriginalSourceResolver(coordinator: coordinator),
            store: store
        )
        customPrewarmer = prewarmer
        return prewarmer
    }

    @MainActor
    private func startHomeCustomPlayback(item: MediaItem) {
        guard let store = try? CustomPlaybackEngine.sharedStore() else {
            playbackErrorMessage = "Cache local indisponible."
            return
        }

        let coordinator = PlaybackCoordinator(apiClient: dependencies.apiClient)
        let engine = CustomPlaybackEngine(
            resolver: JellyfinOriginalSourceResolver(coordinator: coordinator),
            store: store,
            reporter: JellyfinCustomPlaybackReporter(apiClient: dependencies.apiClient),
            prewarmer: customPrewarmer,
            markers: JellyfinCustomPlaybackMarkers(apiClient: dependencies.apiClient)
        )
        engine.onPlaybackEnded = {
            handlePlayerDismissal()
        }
        engine.onRequiresNativePlayback = { [weak engine] in
            guard let engine, customEngine === engine else { return }
            AppLog.playback.notice(
                "home.player.native_handoff — item=\(item.id.prefix(8), privacy: .public)"
            )
            Task { @MainActor in
                await startHomeLegacyPlayback(item: item, forceNativeOriginalPlayback: true)
            }
        }
        engine.currentMediaItem = item
        engine.nextEpisodeQueue = []

        playerSession = nil
        customEngine = engine
#if os(iOS)
        OrientationManager.shared.prepareLandscapeForPlayerCoverPresentation()
#endif
        presentHomePlayer(
            HomePlayerPresentation(item: item, content: .custom(engine))
        )
        engine.load(
            itemID: item.id,
            startTimeTicks: item.playbackPositionTicks,
            autoPlay: true
        )
    }

    @MainActor
    private func startHomeLegacyPlayback(
        item: MediaItem,
        forceNativeOriginalPlayback: Bool = false
    ) async {
        let session = dependencies.makePlaybackSession()
#if os(iOS)
        OrientationManager.shared.prepareLandscapeForPlayerCoverPresentation()
#endif
        if forceNativeOriginalPlayback {
            customEngine?.stop()
            customEngine = nil
        }
        playerSession = session
        presentHomePlayer(
            HomePlayerPresentation(item: item, content: .legacy(session))
        )

        do {
            try await session.load(
                item: item,
                startPosition: .resumeIfAvailable,
                forceNativeOriginalPlayback: forceNativeOriginalPlayback
            )
        } catch {
            playerSession = nil
            dismissHomePlayer()
            playbackErrorMessage = error.localizedDescription
        }
    }

    private func primePresentationDetailShell(for item: MediaItem) async {
        let detailItemID = item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
        await dependencies.detailRepository.primeItem(id: detailItemID)
        guard !Task.isCancelled else { return }
        await dependencies.detailRepository.primeDetail(id: detailItemID)
    }

    private func prefetchPresentationArtwork(for item: MediaItem, neighbors: [MediaItem]) async {
        let detailItemID = item.mediaType == .episode ? (item.parentID ?? item.id) : item.id
        let nearbyItems = Array(neighbors.prefix(2))
        await dependencies.apiClient.prefetchImages(for: nearbyItems)
        guard !Task.isCancelled else { return }

        if let heroURL = await dependencies.apiClient.imageURL(
            for: detailItemID,
            type: item.backdropTag == nil ? .primary : .backdrop,
            width: ArtworkRequestProfile.heroBackdropHigh.width,
            quality: ArtworkRequestProfile.heroBackdropHigh.quality
        ) {
            await dependencies.imagePipeline.prefetch(urls: [heroURL])
        }
    }

    private func warmPresentationPlayback(for item: MediaItem, neighbors: [MediaItem]) async {
        if dependencies.settingsStore.useCustomPlayerEngine {
            guard let playbackItem = await optimizationPlaybackItem(for: item) else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                ensureHomeCustomPrewarmer()?.prewarm(
                    itemID: playbackItem.id,
                    startTimeTicks: playbackItem.playbackPositionTicks
                )
            }
            return
        }

        let nearbyItems = Array(neighbors.prefix(2))
        guard !Task.isCancelled else { return }

        await dependencies.playbackWarmupManager.trim(keeping: [item.id] + nearbyItems.map(\.id))
        guard !Task.isCancelled else { return }
        await hydrateOptimizationStatus(for: item)
    }

    private func refreshOptimizationStatuses(for items: [MediaItem]) async {
        for item in items {
            guard !Task.isCancelled else { return }
            await hydrateOptimizationStatus(for: item)
        }
    }

    private func hydrateOptimizationStatus(for item: MediaItem) async {
        if await MainActor.run(body: { appleOptimizationStatuses[item.id] != nil }) {
            return
        }

        guard let playbackItem = await optimizationPlaybackItem(for: item) else { return }

        await dependencies.playbackWarmupManager.warm(
            itemID: playbackItem.id,
            resumeSeconds: Self.resumeSeconds(for: playbackItem),
            runtimeSeconds: Self.runtimeSeconds(for: playbackItem),
            isTVOS: Self.isTVOSPlatform
        )
        let selection = await dependencies.playbackWarmupManager.selection(for: playbackItem.id)
        let status = ApplePlaybackOptimizationStatus(selection: selection)

        await MainActor.run {
            appleOptimizationStatuses[item.id] = status
        }
    }

    private static var isTVOSPlatform: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    private static func resumeSeconds(for item: MediaItem) -> Double {
        guard let ticks = item.playbackPositionTicks, ticks > 0 else {
            return 0
        }
        return Double(ticks) / 10_000_000
    }

    private static func runtimeSeconds(for item: MediaItem) -> Double? {
        guard let ticks = item.runtimeTicks, ticks > 0 else {
            return nil
        }
        return Double(ticks) / 10_000_000
    }

    private func optimizationPlaybackItem(for item: MediaItem) async -> MediaItem? {
        guard item.mediaType == .series else {
            return item
        }

        do {
            return try await dependencies.detailRepository.loadNextUpEpisode(seriesID: item.id)
        } catch {
            return nil
        }
    }

    private func scheduleWarmup(
        for item: MediaItem,
        neighbors: [MediaItem],
        scope: String? = nil,
        settleDelayNanoseconds: UInt64
    ) {
#if os(tvOS)
        if let scope, let coordinator = dependencies.tvFocusWarmupCoordinator {
            Task(priority: .background) {
                await coordinator.schedule(
                    scope: scope,
                    settleDelayNanoseconds: settleDelayNanoseconds,
                    detailShell: {
                        await primePresentationDetailShell(for: item)
                    },
                    artworkPrefetch: {
                        await prefetchPresentationArtwork(for: item, neighbors: neighbors)
                    },
                    playbackWarmup: {
                        await warmPresentationPlayback(for: item, neighbors: neighbors)
                    }
                )
            }
            return
        }
#endif
        warmupTask?.cancel()
        warmupTask = Task(priority: .background) {
            if settleDelayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: settleDelayNanoseconds)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            await primePresentationDetailShell(for: item)
            guard !Task.isCancelled else { return }
            await prefetchPresentationArtwork(for: item, neighbors: neighbors)
            guard !Task.isCancelled else { return }
            await warmPresentationPlayback(for: item, neighbors: neighbors)
        }
    }

    private func handleHomeDisappear() {
        warmupTask?.cancel()
        if playerPresentation == nil {
            customPrewarmer?.discardIfUnused()
        }
#if os(tvOS)
        tvScreenState.cancel()
        if let coordinator = dependencies.tvFocusWarmupCoordinator {
            Task {
                await coordinator.cancel(scope: TVHomeWarmupScope.hero)
                await coordinator.cancel(scope: TVHomeWarmupScope.focus)
            }
        }
#endif
    }

    @MainActor
    private func handlePlayerDismissal() {
        playerSession?.stop()
        playerSession = nil
        customEngine?.stop()
        customEngine = nil
        dismissHomePlayer()
        isPreparingPlayback = false
    }

    private func presentHomePlayer(_ presentation: HomePlayerPresentation) {
#if os(iOS)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            playerPresentation = presentation
        }
#else
        playerPresentation = presentation
#endif
    }

    private func dismissHomePlayer() {
#if os(iOS)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            playerPresentation = nil
        }
#else
        playerPresentation = nil
#endif
    }

#if os(tvOS)
    private func triggerTVHomeRefresh() {
        guard !viewModel.isRefreshing else { return }
        Task { await viewModel.manualRefresh() }
    }

    private func restoreHomeSelection(using proxy: ScrollViewProxy) {
        guard let homeReturnTarget else { return }

        switch homeReturnTarget {
        case let .featured(itemID):
            featuredHeroItemID = itemID
            withAnimation(.easeInOut(duration: 0.34)) {
                proxy.scrollTo(featuredScrollAnchorID, anchor: .top)
            }
        case let .row(rowID, itemID):
            withAnimation(.easeInOut(duration: 0.34)) {
                proxy.scrollTo(rowID, anchor: .top)
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                focusedHomeItemID = itemID
            }
        }
    }

    private func focusFeaturedAction(using proxy: ScrollViewProxy) {
        guard !featuredItems.isEmpty else { return }

        focusedHomeItemID = nil
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(featuredScrollAnchorID, anchor: .top)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            focusedHomeItemID = featuredPrimaryActionFocusID
        }
    }
#endif

    private var featuredScrollAnchorID: String {
        "home.featured.anchor"
    }

    private var tvRefreshStatusTopPadding: CGFloat {
        ReelFinTheme.tvTopNavigationBarHeight + 90
    }

    private var tvRefreshStatusTrailingPadding: CGFloat {
        96
    }

    private func continueWatchingHeroFocusAction(for kind: HomeSectionKind) -> (() -> Void)? {
#if os(tvOS)
        guard kind == .continueWatching else { return nil }
        return {
            localHeroFocusRequest += 1
        }
#else
        return nil
#endif
    }

    private var featuredPrimaryActionFocusID: String {
        "home.featured.primaryAction"
    }

    private func handleDisplayedDetailSourceItemChange(_ item: MediaItem) {
#if os(tvOS)
        if featuredItems.contains(where: { $0.id == item.id }) {
            selectedDetailNamespace = posterNamespace
            selectedDetailTransitionSourceID = HomeFeaturedTransitionSource.id(itemID: item.id)
            featuredHeroItemID = item.id
            homeReturnTarget = .featured(itemID: item.id)
            lastSelectedHomeRowID = nil
            lastSelectedHomeItemID = nil
            return
        }

        guard let rowID = viewModel.rowIDByItemID[item.id] else {
            // Keep the last valid transition anchors. Nil-ing them flipped the structural branch
            // in DetailZoomTransitionModifier and REMOUNTED the whole inline DetailView mid-
            // interaction — the just-presented player's state (showPlayer/customEngine) died with
            // the old instance: pressing an EPISODE froze the screen while the engine played
            // unseen (tvOS device log 2026-07-03, double 'Detail navigation started').
            return
        }

        selectedDetailNamespace = posterNamespace
        selectedDetailTransitionSourceID = HomeCardTransitionSource.id(rowID: rowID, itemID: item.id)
        lastSelectedHomeRowID = rowID
        lastSelectedHomeItemID = item.id
        homeReturnTarget = .row(rowID: rowID, itemID: item.id)
#endif
    }
}

#if os(tvOS)
@MainActor
private final class TVHomeScreenState: ObservableObject {
    @Published var navigationAppearance = TVTopNavigationAppearance.neutral

    private let resolver: TVTopNavigationAppearanceResolver
    private var appearanceTask: Task<Void, Never>?

    init(
        apiClient: any JellyfinAPIClientProtocol,
        imagePipeline: any ImagePipelineProtocol
    ) {
        self.resolver = TVTopNavigationAppearanceResolver(
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
    }

    func scheduleNavigationAppearance(for item: MediaItem) {
        appearanceTask?.cancel()
        navigationAppearance = TVTopNavigationAppearance.fallback(for: item)
        appearanceTask = Task(priority: .utility) { [resolver] in
            let appearance = await resolver.appearance(for: item)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(TVMotion.overlayFadeAnimation) {
                    self.navigationAppearance = appearance
                }
            }
        }
    }

    func cancel() {
        appearanceTask?.cancel()
    }
}

private struct TVHomeRefreshStatusView: View {
    let isRefreshing: Bool

    var body: some View {
        Group {
            if isRefreshing {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)

                    Text("Refreshing")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background { background }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Refreshing Home")
                .accessibilityIdentifier("home_tv_refresh_status")
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.18), value: isRefreshing)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var background: some View {
        if #available(tvOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
                .glassEffect(
                    Glass.regular.tint(Color.white.opacity(0.12)),
                    in: .capsule
                )
        } else {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.46))
        }
    }
}

private struct TVDetailOpeningArtworkView: View {
    let item: MediaItem
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                CachedRemoteImage(
                    itemID: imageItemID,
                    type: .backdrop,
                    width: Int(max(proxy.size.width, 1)),
                    quality: 90,
                    apiClient: apiClient,
                    imagePipeline: imagePipeline
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.10),
                        .init(color: .black.opacity(0.18), location: 0.56),
                        .init(color: .black.opacity(0.82), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }

    private var imageItemID: String {
        if item.mediaType == .episode, let parentID = item.parentID {
            return parentID
        }
        return item.id
    }
}

private struct TVInlineDetailArtworkDestinationModifier: ViewModifier {
    let namespace: Namespace.ID?
    let sourceID: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace, let sourceID {
            content.matchedGeometryEffect(id: "poster-\(sourceID)", in: namespace, isSource: false)
        } else {
            content
        }
    }
}

private struct TVHomeScreen<Content: View>: View {
    let navigationAppearance: TVTopNavigationAppearance
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            TVHomeBackdropView()
            content()
        }
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(.container, edges: [.top, .horizontal])
        .preference(key: TVTopNavigationAppearancePreferenceKey.self, value: navigationAppearance)
    }
}
#endif

private struct HomeCustomizationSheet: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            List {
#if os(iOS)
                Section("Order") {
                    ForEach(viewModel.sectionCustomizationKinds, id: \.self) { kind in
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: kind))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 20)
                            Text(viewModel.sectionTitle(for: kind))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                    .onMove(perform: viewModel.moveSectionKinds(from:to:))
                }
#endif

                Section("Visible Sections") {
                    ForEach(viewModel.sectionCustomizationKinds, id: \.self) { kind in
                        Toggle(isOn: Binding(
                            get: { viewModel.isSectionVisible(kind) },
                            set: { viewModel.setSectionVisibility(kind, isVisible: $0) }
                        )) {
                            Text(viewModel.sectionTitle(for: kind))
                                .foregroundStyle(.white)
                        }
                        .tint(.white)
                    }
                }
            }
            .environment(\.editMode, $editMode)
#if os(iOS) && !targetEnvironment(macCatalyst)
            .scrollContentBackground(.hidden)
#endif
            .background(ReelFinTheme.pageGradient.ignoresSafeArea())
            .navigationTitle("Customize Home")
#if os(iOS) && !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        viewModel.resetSectionCustomization()
                    }
                    .tint(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(.white)
                }
            }
#else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
#endif
        }
        .preferredColorScheme(.dark)
    }

    private func icon(for kind: HomeSectionKind) -> String {
        switch kind {
        case .continueWatching:
            return "play.circle"
        case .recentlyReleasedMovies:
            return "sparkles"
        case .recentlyReleasedSeries:
            return "sparkles"
        case .nextUp:
            return "forward.end.circle"
        case .recentlyAddedMovies:
            return "film.stack"
        case .recentlyAddedSeries:
            return "tv"
        case .popular:
            return "flame"
        case .trending:
            return "chart.line.uptrend.xyaxis"
        case .movies:
            return "film"
        case .shows:
            return "play.tv"
        case .latest:
            return "clock"
        }
    }
}

// MARK: - UI Checklist
// - Safe areas OK (edges ignored for Hero, bottom inset added for scrolling)
// - No text clipping (titles use minimumScaleFactor and fixedSize where necessary)
// - Tab bar overlay OK (ignoresSafeArea .keyboard)
// - Hero paging OK (uses .scrollTargetBehavior(.paging))
// - Matched geometry OK (posterNamespace preserved)
// - Dark gradient scrims OK (ReelFinTheme.heroGradientScrim applied)

#Preview("Home - iPhone SE") {
    NavigationStack {
        HomeView(dependencies: ReelFinPreviewFactory.dependencies())
    }
}

#Preview("Home - iPhone Pro Max") {
    NavigationStack {
        HomeView(dependencies: ReelFinPreviewFactory.dependencies())
    }
}

#Preview("Home - Accessibility XXXL") {
    NavigationStack {
        HomeView(dependencies: ReelFinPreviewFactory.dependencies())
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Home - Apple TV", traits: .fixedLayout(width: 1920, height: 1080)) {
    NavigationStack {
        HomeView(dependencies: ReelFinPreviewFactory.dependencies())
    }
    .preferredColorScheme(.dark)
}
