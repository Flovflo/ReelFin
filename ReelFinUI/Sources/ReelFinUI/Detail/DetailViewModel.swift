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

    @Published var seasons: [MediaItem] = []
    @Published var episodes: [MediaItem] = []
    @Published var selectedSeason: MediaItem?
    @Published var isLoadingEpisodes = false
    /// For series: the episode that should be played (either in-progress or first episode)
    @Published var nextUpEpisode: MediaItem?

    private let dependencies: ReelFinDependencies

    init(item: MediaItem, dependencies: ReelFinDependencies) {
        self.detail = MediaDetail(item: item)
        self.dependencies = dependencies
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let cached = try await dependencies.repository.fetchItem(id: detail.item.id) {
                detail.item = cached
            }
            playbackProgress = try await dependencies.repository.fetchPlaybackProgress(itemID: detail.item.id)

            let freshDetail = try await dependencies.apiClient.fetchItemDetail(id: detail.item.id)
            detail = freshDetail
            try await dependencies.repository.upsertItems([freshDetail.item] + freshDetail.similar)
            
            if freshDetail.item.mediaType == .series {
                await loadSeasons()
            } else {
                // Speculative loading: fetch playback info early to warm up the transcode engine.
                prefetchPlaybackInfo(for: freshDetail.item.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prefetchPlaybackInfo(for itemID: String) {
        let apiClient = dependencies.apiClient
        Task.detached(priority: .background) {
            // This warms up the Jellyfin transcode decision and any potential fMP4 manifest generation.
            _ = try? await apiClient.fetchPlaybackSources(itemID: itemID)
        }
    }

    private func loadSeasons() async {
        do {
            let fetchedSeasons = try await dependencies.apiClient.fetchSeasons(seriesID: detail.item.id)
            self.seasons = fetchedSeasons
            
            if let firstSeason = fetchedSeasons.first {
                await select(season: firstSeason)
            }
            
            // Find the in-progress or next episode across all seasons
            await resolveNextUpEpisode()
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
            // Update nextUpEpisode if we don't have one yet
            if nextUpEpisode == nil {
                nextUpEpisode = fetchedEpisodes.first
            }
        } catch {
            print("Failed to load episodes: \(error)")
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
    
    /// The item that should actually be passed to the player when the main button is tapped
    var itemToPlay: MediaItem {
        if detail.item.mediaType == .series, let ep = nextUpEpisode {
            return ep
        }
        return detail.item
    }

    func toggleWatchlist() {
        isInWatchlist.toggle()
    }

    func toggleWatched() {
        isWatched.toggle()
    }
}
