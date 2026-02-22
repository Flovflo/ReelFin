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
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSeasons() async {
        do {
            let fetchedSeasons = try await dependencies.apiClient.fetchSeasons(seriesID: detail.item.id)
            self.seasons = fetchedSeasons
            
            if let firstSeason = fetchedSeasons.first {
                await select(season: firstSeason)
            }
        } catch {
            print("Failed to load seasons: \(error)")
        }
    }

    func select(season: MediaItem) async {
        selectedSeason = season
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        
        do {
            let fetchedEpisodes = try await dependencies.apiClient.fetchEpisodes(seriesID: detail.item.id, seasonID: season.id)
            self.episodes = fetchedEpisodes
        } catch {
            print("Failed to load episodes: \(error)")
        }
    }

    var shouldShowResume: Bool {
        guard let playbackProgress else { return false }
        return playbackProgress.positionTicks > 0 && playbackProgress.progressRatio < 0.97
    }

    func toggleWatchlist() {
        isInWatchlist.toggle()
    }

    func toggleWatched() {
        isWatched.toggle()
    }
}
