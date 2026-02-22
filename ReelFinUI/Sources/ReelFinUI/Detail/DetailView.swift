import PlaybackEngine
import Shared
import SwiftUI

struct DetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.92).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    poster

                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.detail.item.name)
                            .font(.system(size: horizontalSizeClass == .compact ? 32 : 44, weight: .heavy, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .lineLimit(3)
                            .foregroundStyle(.white)

                        metadataLine

                        if let overview = viewModel.detail.item.overview {
                            Text(overview)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(6)
                                .lineSpacing(4)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)

                    actionButtons
                        .padding(.horizontal, horizontalPadding)

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
                .padding(.bottom, 30)
            }
        }
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
            quality: 82,
            apiClient: dependencies.apiClient,
            imagePipeline: dependencies.imagePipeline
        )
        .overlay(ReelFinTheme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(height: heroHeight)
        .padding(.horizontal, horizontalPadding)
        .modifier(MatchedPosterModifier(itemID: viewModel.detail.item.id, namespace: namespace))
    }

    private var metadataLine: some View {
        HStack(spacing: 8) {
            if let year = viewModel.detail.item.year {
                Text(String(year))
            }
            if let runtime = viewModel.detail.item.runtimeMinutes {
                Text("• \(runtime)m")
            }
            if !viewModel.detail.item.genres.isEmpty {
                Text("• \(viewModel.detail.item.genres.prefix(2).joined(separator: ", "))")
                    .lineLimit(1)
            }
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.75))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    startPlayback()
                } label: {
                    if isLoadingPlayback {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .disabled(isLoadingPlayback)

                Button {
                    startPlayback()
                } label: {
                    Label(viewModel.shouldShowResume ? "Resume" : "Start Over", systemImage: "goforward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.toggleWatchlist()
                } label: {
                    Label(viewModel.isInWatchlist ? "In Watchlist" : "Watchlist", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())

                Button {
                    viewModel.toggleWatched()
                } label: {
                    Label(viewModel.isWatched ? "Watched" : "Mark Watched", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
            }
        }
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cast")
                .reelFinSectionStyle()
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(viewModel.detail.cast.enumerated()), id: \.offset) { _, person in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            if let role = person.role {
                                Text(role)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(ReelFinTheme.card.opacity(0.88))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }

    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Similar")
                .reelFinSectionStyle()
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Seasons")
                    .reelFinSectionStyle()
                    .padding(.horizontal, horizontalPadding)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.seasons) { season in
                            Button {
                                Task {
                                    await viewModel.select(season: season)
                                }
                            } label: {
                                Text(season.name)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(viewModel.selectedSeason?.id == season.id ? Color.white : ReelFinTheme.card.opacity(0.88))
                                    .foregroundStyle(viewModel.selectedSeason?.id == season.id ? Color.black : Color.white)
                                    .clipShape(Capsule())
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Episodes")
                    .reelFinSectionStyle()
                    .padding(.horizontal, horizontalPadding)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
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
                .frame(width: 260, height: 146) // 16:9 ratio
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(episode.indexNumber.map { "\($0). " } ?? "")\(episode.name)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let runtime = episode.runtimeMinutes {
                        Text("\(runtime)m")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(3)
                            .lineSpacing(2)
                            .padding(.top, 2)
                    }
                }
                .frame(width: 260, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func startPlayback() {
        guard !isLoadingPlayback else { return }
        isLoadingPlayback = true
        let session = dependencies.makePlaybackSession()
        playerSession = session

        Task {
            do {
                try await session.load(item: viewModel.detail.item)
                // Show the player AFTER the item is loaded on the AVPlayer.
                // This ensures AVPlayerViewController is created with a player
                // that already has a current item, avoiding the XPC race condition
                // that causes black screen with audio on slow transcodes.
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
        horizontalSizeClass == .compact ? 16 : 24
    }

    private var heroHeight: CGFloat {
        horizontalSizeClass == .compact ? 320 : 420
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

private struct PrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [ReelFinTheme.accent, ReelFinTheme.accentSecondary],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(configuration.isPressed ? 0.8 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SecondaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(ReelFinTheme.card.opacity(configuration.isPressed ? 0.7 : 0.92))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
