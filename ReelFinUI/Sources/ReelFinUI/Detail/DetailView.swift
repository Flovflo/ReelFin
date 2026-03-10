import PlaybackEngine
import Shared
import SwiftUI
import ImageCache
import JellyfinAPI
#if os(iOS)
import UIKit
#endif

struct DetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel: DetailViewModel
    private let dependencies: ReelFinDependencies
    private let autoplayOnLoad: Bool
    private let namespace: Namespace.ID?

    @State private var playerSession: PlaybackSessionController?
    @State private var showPlayer = false
    @State private var isLoadingPlayback = false
    @State private var isDescriptionExpanded = false
    @State private var hasTriggeredAutoplay = false

    init(
        dependencies: ReelFinDependencies,
        item: MediaItem,
        preferredEpisode: MediaItem? = nil,
        autoplayOnLoad: Bool = false,
        namespace: Namespace.ID? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: DetailViewModel(
                item: item,
                preferredEpisode: preferredEpisode,
                dependencies: dependencies
            )
        )
        self.dependencies = dependencies
        self.autoplayOnLoad = autoplayOnLoad
        self.namespace = namespace
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Hero Banner
                MediaHeroHeaderView(
                    item: viewModel.detail.item,
                    heroHeight: heroHeight,
                    isLoadingPlayback: isLoadingPlayback,
                    isInWatchlist: viewModel.isInWatchlist,
                    isDescriptionExpanded: $isDescriptionExpanded,
                    playButtonLabel: viewModel.playButtonLabel,
                    playbackStatusText: viewModel.playbackStatusText,
                    onPlay: { startPlayback() },
                    onToggleWatchlist: { viewModel.toggleWatchlist() },
                    onMoreActions: { /* More actions */ },
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline,
                    namespace: namespace
                )

                if viewModel.detail.item.mediaType == .series {
                    seasonSection
                    episodeSection
                }

                if !viewModel.detail.cast.isEmpty {
                    CastRow(
                        cast: viewModel.detail.cast,
                        apiClient: dependencies.apiClient,
                        imagePipeline: dependencies.imagePipeline
                    )
                }

                if !viewModel.detail.similar.isEmpty {
                    SimilarRow(
                        similar: viewModel.detail.similar,
                        onSelect: { item in
                            viewModel.setDetailItem(item)
                            Task {
                                await viewModel.load()
                            }
                        },
                        apiClient: dependencies.apiClient,
                        imagePipeline: dependencies.imagePipeline
                    )
                }

                fileDetailsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 56)
        }
        .background(ReelFinTheme.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbarBackground(.hidden, for: .navigationBar)
#endif
        .task {
            await viewModel.load()
            guard autoplayOnLoad, !hasTriggeredAutoplay else { return }
            hasTriggeredAutoplay = true
            startPlayback()
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let playerSession {
                PlayerView(session: playerSession, item: viewModel.itemToPlay) {
                    showPlayer = false
                }
            }
        }
    }



    @ViewBuilder
    private var seasonSection: some View {
        if !viewModel.seasons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Seasons")
                    .reelFinSectionStyle()
                    .padding(.horizontal, horizontalPadding)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(viewModel.seasons) { season in
                            Button {
                                Task {
                                    await viewModel.select(season: season)
                                }
                            } label: {
                                Text(season.name)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(viewModel.selectedSeason?.id == season.id ? .black : .white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(
                                        viewModel.selectedSeason?.id == season.id
                                            ? AnyShapeStyle(Color.white)
                                            : AnyShapeStyle(.ultraThinMaterial)
                                    )
                                    .clipShape(Capsule())
                                    .overlay {
                                        if viewModel.selectedSeason?.id != season.id {
                                            Capsule()
                                                .stroke(ReelFinTheme.glassStrokeColor, lineWidth: ReelFinTheme.glassStrokeWidth)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
            }
        }
    }

    @ViewBuilder
    private var episodeSection: some View {
        if viewModel.isLoadingEpisodes {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if !viewModel.episodes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(viewModel.episodes) { episode in
                            EpisodeCardView(
                                episode: episode,
                                width: episodeCardWidth,
                                onSelect: {
                                    viewModel.prepareEpisodePlayback(episode)
                                    startPlayback(item: episode)
                                },
                                apiClient: dependencies.apiClient,
                                imagePipeline: dependencies.imagePipeline
                            )
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
            }
        }
    }

    private func startPlayback(item: MediaItem? = nil) {
        guard !isLoadingPlayback else { return }
        let session = dependencies.makePlaybackSession()
        let targetItem = item ?? viewModel.itemToPlay

        isLoadingPlayback = true
        playerSession = session

        Task {
            do {
                try await session.load(item: targetItem)
                isLoadingPlayback = false
                showPlayer = true
            } catch {
                isLoadingPlayback = false
                await MainActor.run {
                    viewModel.errorMessage = error.localizedDescription
                    showPlayer = false
                }
            }
        }
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 24 : 40
    }

    private var heroHeight: CGFloat {
        if horizontalSizeClass == .compact {
            return dynamicTypeSize.isAccessibilitySize ? 520 : 420
        }
        return dynamicTypeSize.isAccessibilitySize ? 660 : 560
    }



    private var episodeCardWidth: CGFloat {
        horizontalSizeClass == .compact ? 320 : 400
    }

    @ViewBuilder
    private var fileDetailsSection: some View {
        if let source = viewModel.preferredPlaybackSource {
            FileDetailsSection(source: source)
                .padding(.horizontal, horizontalPadding)
        }
    }
}

// MARK: - Apple TV Aesthetic Detail Components

public struct HeroScrimView: View {
    public init() {}
    
    public var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.08), location: 0.35),
                .init(color: .black.opacity(0.42), location: 0.68),
                .init(color: .black.opacity(0.82), location: 0.9),
                .init(color: .black, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

public struct BadgePill: View {
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(white: 0.2))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            }
    }
}

public struct PrimaryPlayButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    public init(title: String, isLoading: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "play.fill")
                        .font(.headline)
                    Text(title)
                        .font(.headline.weight(.semibold))
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .sensoryFeedback(.impact(weight: .medium), trigger: isLoading)
    }
}

public struct GlassCircleButton: View {
    let systemImage: String
    let action: () -> Void

    public init(systemImage: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
    }
}

public struct SeasonHeaderView: View {
    let title: String
    
    public init(title: String) {
        self.title = title
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 40)
    }
}

public struct EpisodeCardView: View {
    let episode: MediaItem
    let width: CGFloat
    let onSelect: () -> Void
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    public init(
        episode: MediaItem, 
        width: CGFloat, 
        onSelect: @escaping () -> Void,
        apiClient: any JellyfinAPIClientProtocol,
        imagePipeline: any ImagePipelineProtocol
    ) {
        self.episode = episode
        self.width = width
        self.onSelect = onSelect
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
    }

    public var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                // Background Image
                Color.clear
                    .frame(width: width, height: width * (9.0 / 16.0))
                    .overlay(alignment: .center) {
                        CachedRemoteImage(
                            itemID: episode.id,
                            type: .primary,
                            width: 600,
                            apiClient: apiClient,
                            imagePipeline: imagePipeline
                        )
                        .frame(width: width, height: width * (9.0 / 16.0))
                        .clipped()
                    }
                    .overlay(alignment: .topTrailing) {
                        if episode.isPlayed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay {
                                    Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                }
                                .padding(12)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if !episode.isPlayed, let progress = episode.playbackProgress, progress > 0 {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(.white.opacity(0.3))
                                    .frame(height: 4)
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(ReelFinTheme.accent)
                                            .frame(width: geo.size.width * CGFloat(progress))
                                    }
                            }
                            .frame(height: 4)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                        }
                    }
                
                // Dark bottom gradient overlay
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black.opacity(0.4), location: 0.5),
                                .init(color: .black.opacity(0.85), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    
                    Text("EPISODE \(episode.indexNumber ?? 0)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.8))
                    
                    Text(episode.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                            .lineSpacing(2)
                            .padding(.bottom, 4)
                    }
                    
                    HStack {
                        if let runtime = episode.runtimeDisplayText {
                            Label(runtime, systemImage: "play.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(20)
                .frame(width: width, height: width * (9.0 / 16.0), alignment: .bottomLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
}

struct MatchedPosterModifier: ViewModifier {
    let itemID: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "poster-\(itemID)", in: namespace, isSource: false)
        } else {
            content
        }
    }
}

public struct MediaHeroHeaderView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.displayScale) private var displayScale
    
    let item: MediaItem
    let heroHeight: CGFloat
    let isLoadingPlayback: Bool
    let isInWatchlist: Bool
    let playButtonLabel: String
    let playbackStatusText: String?
    @Binding var isDescriptionExpanded: Bool
    let onPlay: () -> Void
    let onToggleWatchlist: () -> Void
    let onMoreActions: () -> Void
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let namespace: Namespace.ID?
    
    public init(item: MediaItem, heroHeight: CGFloat, isLoadingPlayback: Bool, isInWatchlist: Bool, isDescriptionExpanded: Binding<Bool>, playButtonLabel: String = "Play", playbackStatusText: String? = nil, onPlay: @escaping () -> Void, onToggleWatchlist: @escaping () -> Void, onMoreActions: @escaping () -> Void, apiClient: any JellyfinAPIClientProtocol, imagePipeline: any ImagePipelineProtocol, namespace: Namespace.ID? = nil) {
        self.item = item
        self.heroHeight = heroHeight
        self.isLoadingPlayback = isLoadingPlayback
        self.isInWatchlist = isInWatchlist
        self.playButtonLabel = playButtonLabel
        self.playbackStatusText = playbackStatusText
        self._isDescriptionExpanded = isDescriptionExpanded
        self.onPlay = onPlay
        self.onToggleWatchlist = onToggleWatchlist
        self.onMoreActions = onMoreActions
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.namespace = namespace
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .center, spacing: 12) {
                if let airDays = item.airDays, !airDays.isEmpty {
                    if airDays.count == 1 {
                        BadgePill(text: "New Episode Every \(airDays[0])")
                    } else {
                        BadgePill(text: "New Episodes on \(airDays.joined(separator: ", "))")
                    }
                }

                Text(item.name)
                    .font(.system(size: titleFontSize, weight: .heavy, design: .rounded))
                    .tracking(titleTracking)
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
#if os(iOS)
                    .textSelection(.disabled)
#endif
                    .shadow(color: .black.opacity(0.45), radius: 8)
                    .accessibilityAddTraits(.isHeader)

                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    PrimaryPlayButton(
                        title: playButtonLabel,
                        isLoading: isLoadingPlayback,
                        action: onPlay
                    )
                    .frame(maxWidth: 320)

                    GlassCircleButton(
                        systemImage: isInWatchlist ? "checkmark" : "plus",
                        action: onToggleWatchlist
                    )

                    GlassCircleButton(
                        systemImage: "ellipsis",
                        action: onMoreActions
                    )
                }
                .padding(.top, 8)

                HStack(spacing: 8) {
                    if item.has4K {
                        BadgePill(text: "4K")
                    }
                    if item.hasDolbyVision {
                        BadgePill(text: "Dolby Vision")
                    }
                    if item.hasClosedCaptions {
                        BadgePill(text: "CC")
                    }
                    if item.isPlayed, playbackStatusText == "Watched" {
                        BadgePill(text: "Watched")
                    }
                }
                .padding(.top, 2)

                if let playbackStatusText, !playbackStatusText.isEmpty {
                    Text(playbackStatusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }

                if let overview = item.overview, !overview.isEmpty {
                    ExpandableOverviewSection(
                        overview: overview,
                        isExpanded: $isDescriptionExpanded
                    )
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topInset)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, minHeight: heroHeight, alignment: .top)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    DetailHeroArtworkView(
                        item: item,
                        containerWidth: proxy.size.width,
                        width: max(Int((proxy.size.width * displayScale).rounded(.up)), heroImageWidth),
                        height: proxy.size.height,
                        apiClient: apiClient,
                        imagePipeline: imagePipeline,
                        namespace: namespace
                    )

                    HeroScrimView()
                }
            }
        }
        .clipped()
    }
    
    private var metadataText: String {
        var entries: [String] = []
        if let year = item.year {
            entries.append(String(year))
        }
        if let runtime = item.runtimeMinutes {
            entries.append(item.runtimeDisplayText ?? "\(runtime)m")
        }
        if !item.genres.isEmpty {
            entries.append(item.genres.prefix(2).joined(separator: ", "))
        }
        return entries.joined(separator: " • ")
    }
    
    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 24 : 40
    }

    private var heroImageWidth: Int {
        let estimatedWidth = horizontalSizeClass == .compact ? 430.0 : 900.0
        let requestedWidth = Int((estimatedWidth * displayScale).rounded(.up))
        return min(max(requestedWidth, 900), 1600)
    }

    private var topInset: CGFloat {
        if horizontalSizeClass == .compact {
            return dynamicTypeSize.isAccessibilitySize ? 120 : 104
        }
        return dynamicTypeSize.isAccessibilitySize ? 148 : 124
    }

    private var titleFontSize: CGFloat {
        let count = item.name.count
        if dynamicTypeSize.isAccessibilitySize {
            if count > 42 { return 28 }
            if count > 30 { return 31 }
            return 34
        }

        if horizontalSizeClass == .compact {
            if count > 42 { return 36 }
            if count > 30 { return 42 }
            if count > 20 { return 48 }
            return 56
        }

        if count > 48 { return 42 }
        if count > 34 { return 48 }
        if count > 22 { return 52 }
        return 60
    }

    private var titleTracking: CGFloat {
        titleFontSize <= 38 ? 0.2 : 0.8
    }
}

private struct DetailHeroArtworkView: View {
    let item: MediaItem
    let containerWidth: CGFloat
    let width: Int
    let height: CGFloat
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let namespace: Namespace.ID?

    var body: some View {
        ZStack {
            Color.black
            if showsForegroundArtwork {
                backgroundArtwork
                foregroundArtwork
            } else {
                fullBleedArtwork
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: max(height, 0))
    }

    private var artworkItemID: String {
        if item.mediaType == .episode, let parentID = item.parentID {
            return parentID
        }
        return item.id
    }

    private var backgroundImageType: JellyfinImageType {
        if item.backdropTag != nil {
            return .backdrop
        }
        return .primary
    }

    private var foregroundImageType: JellyfinImageType {
        .primary
    }

    private var showsForegroundArtwork: Bool {
        backgroundImageType == .primary
    }

    private var backgroundArtwork: some View {
        CachedRemoteImage(
            itemID: artworkItemID,
            type: backgroundImageType,
            width: width,
            quality: 82,
            contentMode: .fill,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
        .scaleEffect(1.24)
        .blur(radius: 28)
        .opacity(0.42)
        .offset(x: backdropOffsetX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .clipped()
    }

    private var fullBleedArtwork: some View {
        CachedRemoteImage(
            itemID: artworkItemID,
            type: backgroundImageType,
            width: width,
            quality: 85,
            contentMode: .fill,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
        .offset(x: backdropOffsetX)
        .frame(width: containerWidth, height: height, alignment: .center)
        .clipped()
    }

    private var foregroundArtwork: some View {
        CachedRemoteImage(
            itemID: artworkItemID,
            type: foregroundImageType,
            width: width,
            quality: 85,
            contentMode: .fit,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
        .modifier(MatchedPosterModifier(itemID: item.id, namespace: namespace))
        .frame(
            width: foregroundWidth,
            height: foregroundHeight,
            alignment: .center
        )
        .offset(x: foregroundOffsetX, y: foregroundOffsetY)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var foregroundWidth: CGFloat {
        if foregroundImageType == .primary {
            return min(containerWidth * 0.82, 360)
        }
        return containerWidth
    }

    private var foregroundHeight: CGFloat {
        if foregroundImageType == .primary {
            return height * 0.92
        }
        return height * 0.82
    }

    private var foregroundOffsetY: CGFloat {
        foregroundImageType == .primary ? height * 0.03 : 0
    }

    private var foregroundOffsetX: CGFloat {
        foregroundImageType == .primary ? 0 : backdropOffsetX
    }

    private var backdropOffsetX: CGFloat {
        backgroundImageType == .backdrop ? -(containerWidth * 0.12) : 0
    }
}

private struct ExpandableOverviewSection: View {
    let overview: String
    @Binding var isExpanded: Bool

    @State private var availableWidth: CGFloat = 0

    var body: some View {
        let showToggle = shouldShowToggle

        VStack(spacing: 10) {
            Text(overview)
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(showToggle && !isExpanded ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .background(widthReader)

            if showToggle {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "LESS" : "MORE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var shouldShowToggle: Bool {
        guard availableWidth > 0 else { return false }
        return lineCount > 3
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    availableWidth = proxy.size.width
                }
                .onChange(of: proxy.size.width) { _, newWidth in
                    availableWidth = newWidth
                }
        }
    }

    private func measuredHeight(lineLimit: Int?) -> CGFloat {
        guard availableWidth > 0 else { return 0 }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let font = measurementFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSAttributedString(string: overview, attributes: attributes)
        let boundingRect = attributedString.boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        if let lineLimit {
            return min(ceil(boundingRect.height), CGFloat(lineLimit) * font.lineHeight)
        }
        return ceil(boundingRect.height)
    }

    private var lineCount: Int {
        guard availableWidth > 0 else { return 0 }
        return Int(ceil(measuredHeight(lineLimit: nil) / measurementFont.lineHeight))
    }

    private var measurementFont: UIFont {
        UIFont.preferredFont(forTextStyle: .body)
    }
}

private struct FileDetailsSection: View {
    let source: MediaSource

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("File Details")
                .reelFinSectionStyle()

            VStack(alignment: .leading, spacing: 16) {
                if let fileName {
                    Text(fileName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                    if let codec = codecSummary {
                        compactMetric(label: "Codec", value: codec)
                    }
                    if let resolution = resolutionSummary {
                        compactMetric(label: "Resolution", value: resolution)
                    }
                    if let frameRate = frameRateSummary {
                        compactMetric(label: "Frame Rate", value: frameRate)
                    }
                    if let bitrate = formattedBitrate {
                        compactMetric(label: "Bitrate", value: bitrate)
                    }
                    if let size = formattedFileSize {
                        compactMetric(label: "Size", value: size)
                    }
                }
            }
            .padding(18)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
            }
        }
    }

    private var fileName: String? {
        if let path = source.filePath, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return source.name.isEmpty ? nil : source.name
    }

    private var codecSummary: String? {
        let video = source.videoCodec?.uppercased()
        let audio = source.audioCodec?.uppercased()
        let values = [video, audio].compactMap { $0 }.filter { !$0.isEmpty }
        return values.isEmpty ? nil : values.joined(separator: " / ")
    }

    private var resolutionSummary: String? {
        guard let width = source.videoWidth, let height = source.videoHeight else { return nil }
        return "\(width)x\(height)"
    }

    private var frameRateSummary: String? {
        guard let frameRate = source.videoFrameRate, frameRate > 0 else { return nil }
        return String(format: "%.2f fps", frameRate)
    }

    private var formattedBitrate: String? {
        guard let bitrate = source.bitrate, bitrate > 0 else { return nil }
        return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
    }

    private var formattedFileSize: String? {
        guard let fileSize = source.fileSize, fileSize > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 120), spacing: 12, alignment: .leading),
            GridItem(.flexible(minimum: 120), spacing: 12, alignment: .leading)
        ]
    }

    @ViewBuilder
    private func compactMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))

            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct CastRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let cast: [PersonCredit]
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    
    public init(cast: [PersonCredit], apiClient: any JellyfinAPIClientProtocol, imagePipeline: any ImagePipelineProtocol) {
        self.cast = cast
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cast")
                .reelFinSectionStyle()
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(cast) { person in
                        VStack(alignment: .center, spacing: 10) {
                            CastPortraitView(
                                person: person,
                                apiClient: apiClient,
                                imagePipeline: imagePipeline
                            )

                            Text(person.name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: cardWidth)

                            if let role = person.role, !role.isEmpty {
                                Text(role)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: cardWidth)
                            } else {
                                Spacer(minLength: 0)
                                    .frame(height: 0)
                            }
                        }
                        .frame(width: cardWidth, alignment: .top)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(accessibilityLabel(for: person))
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }
    
    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 24 : 40
    }

    private var cardWidth: CGFloat {
        horizontalSizeClass == .compact ? 108 : 124
    }

    private func accessibilityLabel(for person: PersonCredit) -> String {
        if let role = person.role, !role.isEmpty {
            return "\(person.name), \(role)"
        }
        return person.name
    }
}

private struct CastPortraitView: View {
    let person: PersonCredit
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }

            if person.primaryImageTag != nil {
                CachedRemoteImage(
                    itemID: person.id,
                    type: .primary,
                    width: 240,
                    quality: 82,
                    contentMode: .fill,
                    apiClient: apiClient,
                    imagePipeline: imagePipeline
                )
                .clipShape(Circle())
            } else {
                fallbackMonogram
            }
        }
        .frame(width: 92, height: 92)
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 6)
    }

    private var fallbackMonogram: some View {
        Text(initials(for: person.name))
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.88))
    }

    private func initials(for name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
        let letters = parts.compactMap { part in
            part.first.map { String($0).uppercased() }
        }
        return letters.joined()
    }
}

public struct SimilarRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let similar: [MediaItem]
    let onSelect: (MediaItem) -> Void
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    public init(similar: [MediaItem], onSelect: @escaping (MediaItem) -> Void, apiClient: any JellyfinAPIClientProtocol, imagePipeline: any ImagePipelineProtocol) {
        self.similar = similar
        self.onSelect = onSelect
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Similar")
                .reelFinSectionStyle()
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(similar) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            PosterCardView(
                                item: item,
                                apiClient: apiClient,
                                imagePipeline: imagePipeline
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 24 : 40
    }
}

private extension MediaItem {
    static var detailPreviewSample: MediaItem {
        MediaItem(
            id: "detail-preview",
            name: "A Very Long Movie Title Designed To Validate Wrapping Across Small Screens",
            overview: """
            This overview intentionally contains enough text to validate wrapping behavior on compact devices and large Dynamic Type sizes. It should remain fully readable, never clipped on the left or right, and naturally scroll when the content is taller than the viewport.
            """,
            mediaType: .movie,
            year: 2026,
            runtimeTicks: Int64(130 * 60 * 10_000_000),
            genres: ["Sci-Fi", "Drama"],
            communityRating: 8.4,
            posterTag: "poster",
            backdropTag: "backdrop",
            libraryID: "movies"
        )
    }
}

#Preview("Detail - iPhone SE") {
    NavigationStack {
        DetailView(
            dependencies: ReelFinPreviewFactory.dependencies(),
            item: .detailPreviewSample
        )
    }
}

#Preview("Detail - iPhone Pro Max") {
    NavigationStack {
        DetailView(
            dependencies: ReelFinPreviewFactory.dependencies(),
            item: .detailPreviewSample
        )
    }
}

#Preview("Detail - Accessibility XXXL") {
    NavigationStack {
        DetailView(
            dependencies: ReelFinPreviewFactory.dependencies(),
            item: .detailPreviewSample
        )
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
