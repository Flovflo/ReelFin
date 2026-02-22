import PlaybackEngine
import Shared
import SwiftUI

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
                ZStack(alignment: .bottomLeading) {
                    poster
                        .frame(maxWidth: .infinity)
                        .frame(height: heroHeight)
                        .clipped()

                    Rectangle()
                        .fill(ReelFinTheme.heroGradientScrim)
                        .frame(height: heroHeight)

                    detailPanel
                        .padding(.bottom, 24)
                }

                if viewModel.detail.item.mediaType == .series {
                    seasonSection
                    episodeSection
                }

                if !viewModel.detail.cast.isEmpty {
                    castSection
                }

                if !viewModel.detail.similar.isEmpty {
                    similarSection
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
                PlayerView(session: playerSession, item: viewModel.detail.item) {
                    showPlayer = false
                }
            }
        }
    }

    private var poster: some View {
        CachedRemoteImage(
            itemID: viewModel.detail.item.id,
            type: .backdrop,
            width: 1300,
            quality: 85,
            apiClient: dependencies.apiClient,
            imagePipeline: dependencies.imagePipeline
        )
        .modifier(MatchedPosterModifier(itemID: viewModel.detail.item.id, namespace: namespace))
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.detail.item.name)
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 32 : 44, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .shadow(color: .black.opacity(0.4), radius: 4)
                .accessibilityAddTraits(.isHeader)

            if !metadataText.isEmpty {
                Text(metadataText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
            }

            if let overview = viewModel.detail.item.overview, !overview.isEmpty {
                Text(overview)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .accessibilityIdentifier("detail_overview")
            }

            actionButtons
                .padding(.top, 12)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        LazyVGrid(columns: actionColumns, spacing: 12) {
            Button {
                startPlayback()
            } label: {
                if isLoadingPlayback {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.white)
                        .clipShape(Capsule())
                } else {
                    Label("Play", systemImage: "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoadingPlayback)
            .sensoryFeedback(.impact(weight: .medium), trigger: isLoadingPlayback)

            Button {
                startPlayback()
            } label: {
                Label(viewModel.shouldShowResume ? "Resume" : "Start Over", systemImage: "goforward")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .glassPanelStyle(cornerRadius: 28)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.toggleWatchlist()
            } label: {
                Label(viewModel.isInWatchlist ? "In Watchlist" : "Watchlist", systemImage: "plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .glassPanelStyle(cornerRadius: 28)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.toggleWatched()
            } label: {
                Label(viewModel.isWatched ? "Watched" : "Mark Watched", systemImage: "checkmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .glassPanelStyle(cornerRadius: 28)
            }
            .buttonStyle(.plain)
        }
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cast")
                .reelFinSectionStyle()
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(viewModel.detail.cast.enumerated()), id: \.offset) { _, person in
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

    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Similar")
                .reelFinSectionStyle()
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(viewModel.detail.similar) { item in
                        Button {
                            viewModel.detail = MediaDetail(item: item)
                            Task {
                                await viewModel.load()
                            }
                        } label: {
                            PosterCardView(
                                item: item,
                                apiClient: dependencies.apiClient,
                                imagePipeline: dependencies.imagePipeline
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
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
                Text("Episodes")
                    .reelFinSectionStyle()
                    .padding(.horizontal, horizontalPadding)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(viewModel.episodes) { episode in
                            episodeCard(for: episode)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
            }
        }
    }

    private func episodeCard(for episode: MediaItem) -> some View {
        Button {
            viewModel.detail = MediaDetail(item: episode)
            Task {
                await viewModel.load()
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                CachedRemoteImage(
                    itemID: episode.id,
                    type: .primary,
                    width: 400,
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline
                )
                .frame(width: episodeCardWidth, height: episodeCardWidth * (9.0 / 16.0))
                .clipShape(RoundedRectangle(cornerRadius: ReelFinTheme.cardCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReelFinTheme.cardCornerRadius, style: .continuous)
                        .stroke(ReelFinTheme.glassStrokeColor, lineWidth: ReelFinTheme.glassStrokeWidth)
                }
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(episode.indexNumber.map { "\($0). " } ?? "")\(episode.name)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let runtime = episode.runtimeMinutes {
                        Text("\(runtime)m")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(3)
                            .lineSpacing(2)
                            .padding(.top, 2)
                    }
                }
                .frame(width: episodeCardWidth, alignment: .leading)
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
                try await session.load(item: viewModel.detail.item)
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

    private var metadataText: String {
        var entries: [String] = []
        if let year = viewModel.detail.item.year {
            entries.append(String(year))
        }
        if let runtime = viewModel.detail.item.runtimeMinutes {
            entries.append("\(runtime)m")
        }
        if !viewModel.detail.item.genres.isEmpty {
            entries.append(viewModel.detail.item.genres.prefix(2).joined(separator: ", "))
        }
        return entries.joined(separator: " • ")
    }

    private var actionColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12)]
        }

        return [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12)
        ]
    }

    private var episodeCardWidth: CGFloat {
        horizontalSizeClass == .compact ? 280 : 340
    }
}

private struct MatchedPosterModifier: ViewModifier {
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
