import Foundation
import JellyfinAPI
import Shared
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var feed: HomeFeed = .empty
    @Published var isInitialLoading = true
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var selectedItem: MediaItem?
    @Published var selectedEpisode: MediaItem?
    @Published var orderedSectionKinds: [HomeSectionKind]
    @Published var hiddenSectionKinds: Set<HomeSectionKind>
    @Published private(set) var visibleRows: [HomeRow] = []
    @Published private(set) var rowIDByItemID: [String: String] = [:]
    @Published private(set) var visibleRowsRevision = 0

    private let dependencies: ReelFinDependencies
    private var feedEnrichmentTask: Task<Void, Never>?
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
            let immediateSeriesShell = MediaItem(
                id: seriesId,
                name: item.seriesName ?? item.name,
                overview: item.overview,
                mediaType: .series,
                year: item.year,
                runtimeTicks: item.runtimeTicks,
                genres: item.genres,
                communityRating: item.communityRating,
                posterTag: item.seriesPosterTag ?? item.posterTag,
                backdropTag: item.backdropTag,
                libraryID: item.libraryID
            )

            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                selectedEpisode = item
                selectedItem = immediateSeriesShell
            }

            Task {
                do {
                    let series = try await dependencies.seriesCache.getSeries(id: seriesId)
                    await MainActor.run {
                        guard self.selectedItem?.id == seriesId else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            selectedItem = mergedSeriesShell(current: immediateSeriesShell, incoming: series)
                        }
                    }
                } catch {
                    AppLog.ui.error("Series shell enrichment failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                selectedEpisode = nil
                selectedItem = item
            }
        }
    }

    func dismissDetail() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            selectedEpisode = nil
            selectedItem = nil
        }
    }

    var sectionCustomizationKinds: [HomeSectionKind] {
        let dynamicKinds = feed.rows.map(\.kind)
        return uniqueKinds(orderedSectionKinds + dynamicKinds + Self.defaultSectionOrder)
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
        rebuildVisibleRowsCache()
        persistSectionPreferences()
    }

    func moveSectionKinds(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty else { return }
        withAnimation(.snappy(duration: 0.25)) {
            orderedSectionKinds.move(fromOffsets: source, toOffset: destination)
        }
        rebuildVisibleRowsCache()
        persistSectionPreferences()
    }

    func resetSectionCustomization() {
        withAnimation(.snappy(duration: 0.3)) {
            orderedSectionKinds = Self.defaultSectionOrder
            hiddenSectionKinds = []
        }
        rebuildVisibleRowsCache()
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
            guard !cached.rows.isEmpty || !cached.featured.isEmpty else { return }

            ensureKnownSectionKinds(from: cached.rows)
            if feed != cached {
                feed = cached
                rebuildVisibleRowsCache()
            }
            scheduleFeedEnrichment(for: cached)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleFeedEnrichment(for feed: HomeFeed) {
        feedEnrichmentTask?.cancel()

        let seriesCache = dependencies.seriesCache
        feedEnrichmentTask = Task(priority: .utility) { [weak self] in
            let visibleRowLimit = min(feed.rows.count, 3)
            let visibleFeed = HomeFeed(
                featured: feed.featured,
                rows: Array(feed.rows.prefix(visibleRowLimit))
            )

            let visibleProcessed = await HomeFeedProcessor.process(visibleFeed, seriesCache: seriesCache)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                self.applyEnrichedFeed(visibleProcessed)
            }

            guard feed.rows.count > visibleRowLimit else { return }

            do {
                try await Task.sleep(nanoseconds: 1_250_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            let processed = await HomeFeedProcessor.process(feed, seriesCache: seriesCache)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                self.applyEnrichedFeed(processed)
            }
        }
    }

    private func applyEnrichedFeed(_ processed: HomeFeed) {
        guard feed != processed else { return }
        ensureKnownSectionKinds(from: processed.rows)
        feed = processed
        rebuildVisibleRowsCache()
    }

    private func ensureKnownSectionKinds(from rows: [HomeRow]) {
        let knownKinds = Set(orderedSectionKinds)
        let missing = rows
            .map(\.kind)
            .filter { !knownKinds.contains($0) }
        if !missing.isEmpty {
            orderedSectionKinds.append(contentsOf: missing)
            rebuildVisibleRowsCache()
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

    private func rebuildVisibleRowsCache() {
        let derived = Self.deriveVisibleRows(
            from: feed.rows,
            orderedSectionKinds: orderedSectionKinds,
            hiddenSectionKinds: hiddenSectionKinds
        )

        var didChange = false
        if visibleRows != derived.rows {
            visibleRows = derived.rows
            didChange = true
        }

        if rowIDByItemID != derived.rowIDByItemID {
            rowIDByItemID = derived.rowIDByItemID
            didChange = true
        }

        if didChange {
            visibleRowsRevision &+= 1
        }
    }

    private func mergedSeriesShell(current: MediaItem, incoming: MediaItem) -> MediaItem {
        var merged = incoming
        if merged.posterTag == nil {
            merged.posterTag = current.posterTag
        }
        if merged.backdropTag == nil {
            merged.backdropTag = current.backdropTag
        }
        if merged.overview == nil {
            merged.overview = current.overview
        }
        if merged.genres.isEmpty {
            merged.genres = current.genres
        }
        return merged
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

    private static func deriveVisibleRows(
        from rows: [HomeRow],
        orderedSectionKinds: [HomeSectionKind],
        hiddenSectionKinds: Set<HomeSectionKind>
    ) -> (rows: [HomeRow], rowIDByItemID: [String: String]) {
        let normalizedRows = rows.compactMap { row -> HomeRow? in
            var normalizedRow = row

#if os(tvOS)
            switch row.kind {
            case .continueWatching:
                normalizedRow.items = row.items.filter { item in
                    !item.isPlayed && ((item.playbackProgress ?? 0) > 0 || (item.playbackPositionTicks ?? 0) > 0)
                }
            case .nextUp:
                normalizedRow.items = row.items.filter { !$0.isPlayed }
            default:
                break
            }
#endif

            return normalizedRow.items.isEmpty ? nil : normalizedRow
        }

        let filteredRows = normalizedRows.filter { row in
#if os(tvOS)
            switch row.kind {
            case .popular, .trending:
                return false
            case .recentlyAddedMovies, .recentlyAddedSeries:
                return true
            default:
                break
            }
#endif

            return !hiddenSectionKinds.contains(row.kind)
        }
        guard !filteredRows.isEmpty else {
            return ([], [:])
        }

        var rowsByKind = Dictionary(grouping: filteredRows, by: \.kind)
        var orderedRows: [HomeRow] = []

        for kind in orderedSectionKinds {
            if let matchedRows = rowsByKind.removeValue(forKey: kind) {
                orderedRows.append(contentsOf: matchedRows)
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

        var rowIDByItemID: [String: String] = [:]
        rowIDByItemID.reserveCapacity(orderedRows.reduce(into: 0) { $0 += $1.items.count })

        for row in orderedRows {
            for item in row.items where rowIDByItemID[item.id] == nil {
                rowIDByItemID[item.id] = row.id
            }
        }

        return (orderedRows, rowIDByItemID)
    }
}

private struct HomeSectionPreferences: Codable {
    var orderedKinds: [HomeSectionKind]
    var hiddenKinds: [HomeSectionKind]
}

private enum HomeFeedProcessor {
    static func process(_ feed: HomeFeed, seriesCache: SeriesLookupCache) async -> HomeFeed {
        let seriesIDs: Set<String> = Set(
            feed.rows.flatMap { row in
                row.items.compactMap { item in
                    guard item.mediaType == .episode else { return nil }
                    return item.parentID
                }
            }
        )

        var updatedRows = feed.rows
        if !seriesIDs.isEmpty {
            var seriesByID: [String: MediaItem] = [:]

            await withTaskGroup(of: (String, MediaItem?).self) { group in
                for seriesID in seriesIDs {
                    group.addTask {
                        do {
                            return (seriesID, try await seriesCache.getSeries(id: seriesID))
                        } catch {
                            return (seriesID, nil)
                        }
                    }
                }

                for await (seriesID, series) in group {
                    if let series {
                        seriesByID[seriesID] = series
                    }
                }
            }

            if !seriesByID.isEmpty {
                for rowIndex in updatedRows.indices {
                    updatedRows[rowIndex].items = updatedRows[rowIndex].items.map { item in
                        guard
                            item.mediaType == .episode,
                            let seriesID = item.parentID,
                            let series = seriesByID[seriesID]
                        else {
                            return item
                        }

                        var updatedItem = item
                        updatedItem.seriesName = updatedItem.seriesName ?? series.name
                        updatedItem.seriesPosterTag = updatedItem.seriesPosterTag ?? series.posterTag
                        return updatedItem
                    }
                }
            }
        }

        let normalizedFeatured = feed.featured.isEmpty ? fallbackFeatured(from: updatedRows) : feed.featured
        return HomeFeed(featured: normalizedFeatured, rows: updatedRows)
    }

    private static func fallbackFeatured(from rows: [HomeRow]) -> [MediaItem] {
        let priority: [HomeSectionKind] = [
            .recentlyAddedMovies,
            .recentlyAddedSeries,
            .popular,
            .trending,
            .movies,
            .shows,
            .continueWatching,
            .nextUp,
            .latest
        ]

        var seen = Set<String>()
        var collected: [MediaItem] = []

        for kind in priority {
            guard let row = rows.first(where: { $0.kind == kind }) else { continue }
            for item in row.items where !seen.contains(item.id) {
                seen.insert(item.id)
                collected.append(item)
                if collected.count >= 10 {
                    return collected
                }
            }
        }

        return collected
    }
}
