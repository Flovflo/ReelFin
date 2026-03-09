import Foundation
import Shared

@MainActor
final class DetailViewModel: ObservableObject {
    @Published var detail: MediaDetail
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var playbackProgress: PlaybackProgress?
    @Published var isInWatchlist = false
    @Published var isWatched = false
    @Published var playbackSources: [MediaSource] = []

    @Published var seasons: [MediaItem] = []
    @Published var episodes: [MediaItem] = []
    @Published var selectedSeason: MediaItem?
    @Published var isLoadingEpisodes = false
    /// For series: the episode that should be played (either in-progress or first episode)
    @Published var nextUpEpisode: MediaItem?

    private let dependencies: ReelFinDependencies
    private var preferredEpisode: MediaItem?

    init(item: MediaItem, preferredEpisode: MediaItem? = nil, dependencies: ReelFinDependencies) {
        self.detail = MediaDetail(item: item)
        self.preferredEpisode = preferredEpisode
        self.dependencies = dependencies
    }

    func setDetailItem(_ item: MediaItem, preferredEpisode: MediaItem? = nil) {
        detail = MediaDetail(item: item)
        self.preferredEpisode = preferredEpisode
        playbackProgress = nil
        playbackSources = []
        seasons = []
        episodes = []
        selectedSeason = nil
        nextUpEpisode = nil
        errorMessage = nil
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let cached = try await dependencies.repository.fetchItem(id: detail.item.id) {
                detail.item = cached
            }
            playbackProgress = await resolvedPlaybackProgress(for: detail.item)

            let freshDetail = try await dependencies.apiClient.fetchItemDetail(id: detail.item.id)
            detail = freshDetail
            try await dependencies.repository.upsertItems([freshDetail.item] + freshDetail.similar)
            
            if freshDetail.item.mediaType == .series {
                await loadSeasons()
            } else {
                await loadPlaybackSources(for: freshDetail.item)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSeasons() async {
        do {
            let fetchedSeasons = try await dependencies.apiClient.fetchSeasons(seriesID: detail.item.id)
            self.seasons = fetchedSeasons

            let preferredSeason = preferredEpisode.flatMap { episode in
                seasonMatching(preferredEpisode: episode, seasons: fetchedSeasons)
            }

            if let preferredSeason {
                await select(season: preferredSeason)
                nextUpEpisode = episodes.first(where: { $0.id == preferredEpisode?.id }) ?? preferredEpisode
            } else if let firstSeason = fetchedSeasons.first {
                await select(season: firstSeason)
                await resolveNextUpEpisode()
            }

            if let episode = nextUpEpisode {
                playbackProgress = await resolvedPlaybackProgress(for: episode)
                await loadPlaybackSources(for: episode)
            } else {
                playbackSources = []
            }
        } catch {
            print("Failed to load seasons: \(error)")
        }
    }
    
    private func resolveNextUpEpisode() async {
        // Ask Jellyfin for the next episode to watch for this series.
        // The /Shows/NextUp endpoint returns the in-progress or next unplayed episode server-side.
        if let apiEpisode = try? await dependencies.apiClient.fetchNextUpEpisode(seriesID: detail.item.id) {
            nextUpEpisode = apiEpisode
        } else {
            // Fallback: first episode of the first season
            nextUpEpisode = episodes.first
        }
    }

    func select(season: MediaItem) async {
        selectedSeason = season
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        
        do {
            let fetchedEpisodes = try await dependencies.apiClient.fetchEpisodes(seriesID: detail.item.id, seasonID: season.id)
            self.episodes = fetchedEpisodes
            if let preferredEpisode,
               fetchedEpisodes.contains(where: { $0.id == preferredEpisode.id }) {
                if let matched = fetchedEpisodes.first(where: { $0.id == preferredEpisode.id }) {
                    nextUpEpisode = mergedEpisode(matched, preferred: preferredEpisode)
                } else {
                    nextUpEpisode = preferredEpisode
                }
                playbackProgress = await resolvedPlaybackProgress(for: nextUpEpisode ?? preferredEpisode)
            } else if nextUpEpisode == nil {
                nextUpEpisode = fetchedEpisodes.first
                if let nextUpEpisode {
                    playbackProgress = await resolvedPlaybackProgress(for: nextUpEpisode)
                }
            }
        } catch {
            print("Failed to load episodes: \(error)")
        }
    }

    func prepareEpisodePlayback(_ episode: MediaItem) {
        preferredEpisode = episode
        nextUpEpisode = episode
        Task {
            let progress = await resolvedPlaybackProgress(for: episode)
            await MainActor.run {
                self.playbackProgress = progress
            }
        }
    }

    var shouldShowResume: Bool {
        guard let playbackProgress else { return false }
        return playbackProgress.positionTicks > 0 && playbackProgress.progressRatio < 0.97
    }
    
    /// The label for the main play button
    var playButtonLabel: String {
        if detail.item.mediaType == .series {
            if let ep = nextUpEpisode,
               let s = ep.parentIndexNumber,
               let e = ep.indexNumber {
                return shouldShowResume ? "Resume S\(s) E\(e)" : "Play S\(s) E\(e)"
            }
            return shouldShowResume ? "Resume" : "Play"
        }
        return shouldShowResume ? "Resume" : "Play"
    }

    var playbackStatusText: String? {
        if shouldShowResume, let item = itemToPlay.playbackPositionDisplayText ?? playbackProgressDisplayText {
            return "Stopped at \(item)"
        }

        if itemToPlay.isPlayed || detail.item.isPlayed || isWatched {
            return "Watched"
        }

        return nil
    }
    
    /// The item that should actually be passed to the player when the main button is tapped
    var itemToPlay: MediaItem {
        if detail.item.mediaType == .series, let ep = nextUpEpisode {
            return ep
        }
        return detail.item
    }

    var preferredPlaybackSource: MediaSource? {
        playbackSources.sorted { lhs, rhs in
            playbackSourceRank(lhs) > playbackSourceRank(rhs)
        }.first
    }

    func toggleWatchlist() {
        isInWatchlist.toggle()
    }

    func toggleWatched() {
        isWatched.toggle()
    }

    private func loadPlaybackSources(for item: MediaItem) async {
        do {
            let sources = try await dependencies.apiClient.fetchPlaybackSources(itemID: item.id)
            playbackSources = sources
        } catch {
            playbackSources = []
        }
    }

    private func seasonMatching(preferredEpisode: MediaItem, seasons: [MediaItem]) -> MediaItem? {
        if let seasonNumber = preferredEpisode.parentIndexNumber,
           let exact = seasons.first(where: { $0.indexNumber == seasonNumber }) {
            return exact
        }
        return seasons.first
    }

    private func resolvedPlaybackProgress(for item: MediaItem) async -> PlaybackProgress? {
        if let local = try? await dependencies.repository.fetchPlaybackProgress(itemID: item.id) {
            return local
        }
        guard let positionTicks = item.playbackPositionTicks, positionTicks > 0 else {
            return nil
        }
        let totalTicks = max(item.runtimeTicks ?? 0, positionTicks)
        return PlaybackProgress(
            itemID: item.id,
            positionTicks: positionTicks,
            totalTicks: totalTicks,
            updatedAt: Date()
        )
    }

    private func mergedEpisode(_ item: MediaItem, preferred: MediaItem) -> MediaItem {
        var merged = item
        if merged.playbackPositionTicks == nil {
            merged.playbackPositionTicks = preferred.playbackPositionTicks
        }
        if merged.runtimeTicks == nil {
            merged.runtimeTicks = preferred.runtimeTicks
        }
        if merged.parentIndexNumber == nil {
            merged.parentIndexNumber = preferred.parentIndexNumber
        }
        if merged.indexNumber == nil {
            merged.indexNumber = preferred.indexNumber
        }
        return merged
    }

    private func playbackSourceRank(_ source: MediaSource) -> Int {
        var score = source.bitrate ?? 0
        if source.supportsDirectPlay {
            score += 10_000_000
        }
        if source.supportsDirectStream {
            score += 5_000_000
        }
        if source.isPremiumVideoSource {
            score += 100_000
        }
        return score
    }

    private var playbackProgressDisplayText: String? {
        guard let playbackProgress, playbackProgress.positionTicks > 0 else { return nil }
        let totalSeconds = Int(playbackProgress.positionTicks / 10_000_000)
        let totalMinutes = max(0, totalSeconds / 60)
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 {
            return "\(hours)h"
        }
        return String(format: "%dh%02d", hours, minutes)
    }
}
