import Foundation
import Shared
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var feed: HomeFeed = .empty
    @Published var isInitialLoading = true
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var selectedItem: MediaItem?

    private let dependencies: ReelFinDependencies

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
    }

    func load() async {
        if isInitialLoading {
            await loadFromCache()
        }

        await refresh(reason: .appLaunch)
        isInitialLoading = false
    }

    func manualRefresh() async {
        await refresh(reason: .manualRefresh)
    }

    func select(item: MediaItem) {
        if item.mediaType == .episode, let seriesId = item.parentID {
            Task {
                do {
                    let series = try await dependencies.seriesCache.getSeries(id: seriesId)
                    await MainActor.run {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            selectedItem = series
                        }
                    }
                } catch {
                    await MainActor.run {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            selectedItem = item
                        }
                    }
                }
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                selectedItem = item
            }
        }
    }

    func dismissDetail() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            selectedItem = nil
        }
    }

    private func refresh(reason: SyncReason) async {
        isRefreshing = true
        defer { isRefreshing = false }

        await dependencies.syncEngine.sync(reason: reason)
        await loadFromCache()
    }

    private func loadFromCache() async {
        do {
            let cached = try await dependencies.repository.fetchHomeFeed()
            if !cached.rows.isEmpty || !cached.featured.isEmpty {
                feed = await processFeed(cached)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func processFeed(_ feed: HomeFeed) async -> HomeFeed {
        var newRows = feed.rows
        for i in newRows.indices {
            let items = newRows[i].items
            var newItems: [MediaItem] = []
            for item in items {
                if item.mediaType == .episode {
                    if let seriesId = item.parentID {
                        do {
                            let series = try await dependencies.seriesCache.getSeries(id: seriesId)
                            var updatedItem = item
                            updatedItem.seriesName = updatedItem.seriesName ?? series.name
                            updatedItem.seriesPosterTag = updatedItem.seriesPosterTag ?? series.posterTag
                            newItems.append(updatedItem)
                        } catch {
                            newItems.append(item)
                        }
                    } else {
                        newItems.append(item)
                    }
                } else {
                    newItems.append(item)
                }
            }
            newRows[i].items = newItems
        }
        let feed = HomeFeed(featured: feed.featured, rows: newRows)
        prefetchImages(for: feed)
        return feed
    }

    private func prefetchImages(for feed: HomeFeed) {
        let allItems = feed.featured + feed.rows.flatMap { $0.items }
        Task.detached(priority: .background) {
            await self.dependencies.apiClient.prefetchImages(for: allItems)
        }
    }
}
