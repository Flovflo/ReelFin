import PlaybackEngine
import Shared
import SwiftUI
import ImageCache
import JellyfinAPI

struct DetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DetailViewModel
    private let dependencies: ReelFinDependencies
    private let namespace: Namespace.ID?

    @State private var playerSession: PlaybackSessionController?
    @State private var showPlayer = false
    @State private var isLoadingPlayback = false
    @State private var isDescriptionExpanded = false

    init(
        dependencies: ReelFinDependencies,
        item: MediaItem,
        namespace: Namespace.ID? = nil
    ) {
        _viewModel = StateObject(wrappedValue: DetailViewModel(item: item, dependencies: dependencies))
        self.dependencies = dependencies
        self.namespace = namespace
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                // Hero Banner
                MediaHeroHeaderView(
                    item: viewModel.detail.item,
                    heroHeight: heroHeight,
                    isLoadingPlayback: isLoadingPlayback,
                    isInWatchlist: viewModel.isInWatchlist,
                    isDescriptionExpanded: $isDescriptionExpanded,
                    playButtonLabel: viewModel.playButtonLabel,
                    onPlay: startPlayback,
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
                    CastRow(cast: viewModel.detail.cast)
                }

                if !viewModel.detail.similar.isEmpty {
                    SimilarRow(
                        similar: viewModel.detail.similar,
                        onSelect: { item in
                            viewModel.detail = MediaDetail(item: item)
                            Task {
                                await viewModel.load()
                            }
                        },
                        apiClient: dependencies.apiClient,
                        imagePipeline: dependencies.imagePipeline
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 64)
        }
        .background(ReelFinTheme.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
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
            VStack(alignment: .leading, spacing: 14) {
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
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(viewModel.episodes) { episode in
                            EpisodeCardView(
                                episode: episode,
                                width: episodeCardWidth,
                                onSelect: {
                                    viewModel.detail = MediaDetail(item: episode)
                                    Task { await viewModel.load() }
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

    private func startPlayback() {
        guard !isLoadingPlayback else { return }
        isLoadingPlayback = true
        let session = dependencies.makePlaybackSession()
        playerSession = session

        Task {
            do {
                // Play the resolved item (nextUp episode for series, or the item itself)
                try await session.load(item: viewModel.itemToPlay)
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
            return dynamicTypeSize.isAccessibilitySize ? 560 : 500
        }
        return dynamicTypeSize.isAccessibilitySize ? 700 : 640
    }



    private var episodeCardWidth: CGFloat {
        horizontalSizeClass == .compact ? 320 : 400
    }
}

// MARK: - Apple TV Aesthetic Detail Components

public struct HeroScrimView: View {
    public init() {}
    
    public var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.8), location: 0),
                .init(color: .clear, location: 0.25),
                .init(color: .clear, location: 0.5),
                .init(color: .black.opacity(0.7), location: 0.8),
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
                        if let runtime = episode.runtimeMinutes {
                            Label("\(runtime)m", systemImage: "play.fill")
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
    
    let item: MediaItem
    let heroHeight: CGFloat
    let isLoadingPlayback: Bool
    let isInWatchlist: Bool
    let playButtonLabel: String
    @Binding var isDescriptionExpanded: Bool
    let onPlay: () -> Void
    let onToggleWatchlist: () -> Void
    let onMoreActions: () -> Void
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let namespace: Namespace.ID?
    
    public init(item: MediaItem, heroHeight: CGFloat, isLoadingPlayback: Bool, isInWatchlist: Bool, isDescriptionExpanded: Binding<Bool>, playButtonLabel: String = "Play", onPlay: @escaping () -> Void, onToggleWatchlist: @escaping () -> Void, onMoreActions: @escaping () -> Void, apiClient: any JellyfinAPIClientProtocol, imagePipeline: any ImagePipelineProtocol, namespace: Namespace.ID? = nil) {
        self.item = item
        self.heroHeight = heroHeight
        self.isLoadingPlayback = isLoadingPlayback
        self.isInWatchlist = isInWatchlist
        self.playButtonLabel = playButtonLabel
        self._isDescriptionExpanded = isDescriptionExpanded
        self.onPlay = onPlay
        self.onToggleWatchlist = onToggleWatchlist
        self.onMoreActions = onMoreActions
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.namespace = namespace
    }
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(height: heroHeight)
                .overlay(alignment: .center) {
                    CachedRemoteImage(
                        itemID: item.id,
                        type: .backdrop,
                        width: 1300,
                        quality: 85,
                        apiClient: apiClient,
                        imagePipeline: imagePipeline
                    )
                    .modifier(MatchedPosterModifier(itemID: item.id, namespace: namespace))
                    .frame(height: heroHeight)
                    .clipped()
                }
                .clipped()

            HeroScrimView()
                .frame(height: heroHeight)
            
            VStack(alignment: .center, spacing: 12) {
                if let airDays = item.airDays, !airDays.isEmpty {
                    if airDays.count == 1 {
                        BadgePill(text: "New Episode Every \(airDays[0])")
                    } else {
                        BadgePill(text: "New Episodes on \(airDays.joined(separator: ", "))")
                    }
                }
                
                Text(item.name)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 36 : 56, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .textSelection(.disabled)
                    .shadow(color: .black.opacity(0.4), radius: 6)
                    .accessibilityAddTraits(.isHeader)
                
                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
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
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                if let overview = item.overview, !overview.isEmpty {
                    VStack(spacing: 8) {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineLimit(isDescriptionExpanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isDescriptionExpanded.toggle()
                            }
                        }) {
                            Text(isDescriptionExpanded ? "LESS" : "MORE")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(white: 0.2))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                
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
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    private var metadataText: String {
        var entries: [String] = []
        if let year = item.year {
            entries.append(String(year))
        }
        if let runtime = item.runtimeMinutes {
            entries.append("\(runtime)m")
        }
        if !item.genres.isEmpty {
            entries.append(item.genres.prefix(2).joined(separator: ", "))
        }
        return entries.joined(separator: " • ")
    }
    
    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 24 : 40
    }
}

public struct CastRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let cast: [PersonCredit]
    
    public init(cast: [PersonCredit]) {
        self.cast = cast
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cast")
                .reelFinSectionStyle()
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(cast.enumerated()), id: \.offset) { _, person in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(person.name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if let role = person.role {
                                Text(role)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .glassPanelStyle(cornerRadius: 16)
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
    .previewDevice("iPhone SE (3rd generation)")
}

#Preview("Detail - iPhone Pro Max") {
    NavigationStack {
        DetailView(
            dependencies: ReelFinPreviewFactory.dependencies(),
            item: .detailPreviewSample
        )
    }
    .previewDevice("iPhone 15 Pro Max")
}

#Preview("Detail - Accessibility XXXL") {
    NavigationStack {
        DetailView(
            dependencies: ReelFinPreviewFactory.dependencies(),
            item: .detailPreviewSample
        )
    }
    .environment(\.dynamicTypeSize, .accessibility5)
    .previewDevice("iPhone SE (3rd generation)")
}
