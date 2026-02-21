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
        } catch {
            errorMessage = error.localizedDescription
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
