import Foundation
import Shared
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    enum SortMode: String, CaseIterable {
        case recent = "Recent"
        case title = "Title"
    }

    @Published var items: [MediaItem] = []
    @Published var searchQuery = ""
    @Published var selectedFilter: MediaType? = nil
    @Published var sortMode: SortMode = .recent
    @Published var isLoadingPage = false
    @Published var selectedItem: MediaItem?

    private let dependencies: ReelFinDependencies

    private var currentPage = 0
    private let pageSize = 48
    private var isLastPage = false

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
    }

    func loadInitial() async {
        await loadFromCache(reset: true)
        await fetchRemote(reset: true)
    }

    func searchChanged() async {
        currentPage = 0
        isLastPage = false

        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await loadInitial()
            return
        }

        do {
            items = try await dependencies.repository.searchItems(query: searchQuery, limit: 100)
            let remote = try await dependencies.apiClient.fetchLibraryItems(
                query: LibraryQuery(
                    viewID: nil,
                    page: 0,
                    pageSize: pageSize,
                    query: searchQuery,
                    mediaType: selectedFilter
                )
            )
            try await dependencies.repository.upsertItems(remote)

            var merged = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            for item in remote {
                merged[item.id] = item
            }
            items = sorted(Array(merged.values))
        } catch {
            AppLog.ui.error("Search failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadMoreIfNeeded(for item: MediaItem) async {
        guard shouldLoadNextPage(triggerItem: item) else { return }
        await fetchRemote(reset: false)
    }

    func select(item: MediaItem) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedItem = item
        }
    }

    func dismissDetail() {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedItem = nil
        }
    }

    private func loadFromCache(reset: Bool) async {
        do {
            let local = try await dependencies.repository.fetchLibraryItems(
                query: LibraryQuery(
                    viewID: nil,
                    page: 0,
                    pageSize: max(pageSize, 120),
                    query: searchQuery.isEmpty ? nil : searchQuery,
                    mediaType: selectedFilter
                )
            )
            items = sorted(local)
            if reset {
                currentPage = 0
                isLastPage = false
            }
        } catch {
            AppLog.ui.error("Local library load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchRemote(reset: Bool) async {
        guard !isLoadingPage, !isLastPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        do {
            let page = reset ? 0 : currentPage
            let remoteItems = try await dependencies.apiClient.fetchLibraryItems(
                query: LibraryQuery(
                    viewID: nil,
                    page: page,
                    pageSize: pageSize,
                    query: searchQuery.isEmpty ? nil : searchQuery,
                    mediaType: selectedFilter
                )
            )

            if remoteItems.count < pageSize {
                isLastPage = true
            }

            if reset {
                items = sorted(remoteItems)
                currentPage = 1
            } else {
                let merged = sorted(items + remoteItems)
                items = deduped(merged)
                currentPage += 1
            }

            try await dependencies.repository.upsertItems(remoteItems)
        } catch {
            AppLog.ui.error("Remote library load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func shouldLoadNextPage(triggerItem: MediaItem) -> Bool {
        guard !isLoadingPage, !isLastPage, searchQuery.isEmpty else { return false }
        guard let index = items.firstIndex(where: { $0.id == triggerItem.id }) else { return false }
        return index >= max(0, items.count - 12)
    }

    private func sorted(_ values: [MediaItem]) -> [MediaItem] {
        let unique = deduped(values)
        switch sortMode {
        case .recent:
            return unique.sorted {
                ($0.year ?? 0, $0.name) > ($1.year ?? 0, $1.name)
            }
        case .title:
            return unique.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private func deduped(_ values: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return values.filter { item in
            if seen.contains(item.id) {
                return false
            }
            seen.insert(item.id)
            return true
        }
    }
}
