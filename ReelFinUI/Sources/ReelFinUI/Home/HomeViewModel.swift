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
    @Published var orderedSectionKinds: [HomeSectionKind]
    @Published var hiddenSectionKinds: Set<HomeSectionKind>

    private let dependencies: ReelFinDependencies
    private static let sectionPreferencesKey = "home.sectionPreferences.v1"
    private static let defaultSectionOrder: [HomeSectionKind] = [
        .continueWatching,
        .nextUp,
        .recentlyAddedMovies,
        .recentlyAddedSeries,
        .popular,
        .trending,
        .movies,
        .shows,
        .latest
    ]

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
        let stored = Self.loadSectionPreferences()
        self.orderedSectionKinds = stored.orderedKinds.isEmpty ? Self.defaultSectionOrder : stored.orderedKinds
        self.hiddenSectionKinds = Set(stored.hiddenKinds)
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

    var sectionCustomizationKinds: [HomeSectionKind] {
        let dynamicKinds = feed.rows.map(\.kind)
        return uniqueKinds(orderedSectionKinds + dynamicKinds + Self.defaultSectionOrder)
    }

    var visibleRows: [HomeRow] {
        let filtered = feed.rows.filter { !hiddenSectionKinds.contains($0.kind) && !$0.items.isEmpty }
        guard !filtered.isEmpty else { return [] }

        var rowsByKind = Dictionary(grouping: filtered, by: \.kind)
        var orderedRows: [HomeRow] = []

        for kind in orderedSectionKinds {
            if let rows = rowsByKind.removeValue(forKey: kind) {
                orderedRows.append(contentsOf: rows)
            }
        }

        if !rowsByKind.isEmpty {
            let leftovers = rowsByKind.values
                .flatMap { $0 }
                .sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            orderedRows.append(contentsOf: leftovers)
        }

        return orderedRows
    }

    func sectionTitle(for kind: HomeSectionKind) -> String {
        if let title = feed.rows.first(where: { $0.kind == kind })?.title {
            return title
        }

        switch kind {
        case .continueWatching:
            return "Continue Watching"
        case .nextUp:
            return "Next Up"
        case .recentlyAddedMovies:
            return "Recently Added Movies"
        case .recentlyAddedSeries:
            return "Recently Added Series"
        case .popular:
            return "Popular"
        case .trending:
            return "Trending"
        case .movies:
            return "Movies"
        case .shows:
            return "Shows"
        case .latest:
            return "Latest"
        }
    }

    func isSectionVisible(_ kind: HomeSectionKind) -> Bool {
        !hiddenSectionKinds.contains(kind)
    }

    func setSectionVisibility(_ kind: HomeSectionKind, isVisible: Bool) {
        withAnimation(.snappy(duration: 0.25)) {
            if isVisible {
                hiddenSectionKinds.remove(kind)
            } else {
                hiddenSectionKinds.insert(kind)
            }
        }
        persistSectionPreferences()
    }

    func moveSectionKinds(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty else { return }
        withAnimation(.snappy(duration: 0.25)) {
            orderedSectionKinds.move(fromOffsets: source, toOffset: destination)
        }
        persistSectionPreferences()
    }

    func resetSectionCustomization() {
        withAnimation(.snappy(duration: 0.3)) {
            orderedSectionKinds = Self.defaultSectionOrder
            hiddenSectionKinds = []
        }
        persistSectionPreferences()
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
                let processed = await processFeed(cached)
                ensureKnownSectionKinds(from: processed.rows)
                feed = processed
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
        let apiClient = dependencies.apiClient
        Task.detached(priority: .background) {
            await apiClient.prefetchImages(for: allItems)
        }
    }

    private func ensureKnownSectionKinds(from rows: [HomeRow]) {
        let knownKinds = Set(orderedSectionKinds)
        let missing = rows
            .map(\.kind)
            .filter { !knownKinds.contains($0) }
        if !missing.isEmpty {
            orderedSectionKinds.append(contentsOf: missing)
            persistSectionPreferences()
        }
    }

    private func uniqueKinds(_ kinds: [HomeSectionKind]) -> [HomeSectionKind] {
        var seen = Set<HomeSectionKind>()
        var result: [HomeSectionKind] = []
        for kind in kinds where !seen.contains(kind) {
            seen.insert(kind)
            result.append(kind)
        }
        return result
    }

    private func persistSectionPreferences() {
        let preferences = HomeSectionPreferences(
            orderedKinds: uniqueKinds(orderedSectionKinds),
            hiddenKinds: Array(hiddenSectionKinds)
        )
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: Self.sectionPreferencesKey)
    }

    private static func loadSectionPreferences() -> HomeSectionPreferences {
        guard
            let data = UserDefaults.standard.data(forKey: sectionPreferencesKey),
            let prefs = try? JSONDecoder().decode(HomeSectionPreferences.self, from: data)
        else {
            return HomeSectionPreferences(orderedKinds: defaultSectionOrder, hiddenKinds: [])
        }
        return prefs
    }
}

private struct HomeSectionPreferences: Codable {
    var orderedKinds: [HomeSectionKind]
    var hiddenKinds: [HomeSectionKind]
}
