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
    private static let sectionPreferencesKey = "home.sectionPreferences.v3"
    private static let supportedSectionKinds: [HomeSectionKind] = [
        .continueWatching,
        .recentlyReleasedMovies,
        .recentlyReleasedSeries,
        .recentlyAddedMovies,
        .recentlyAddedSeries
    ]
    private static let defaultSectionOrder: [HomeSectionKind] = [
        .continueWatching,
        .recentlyReleasedMovies,
        .recentlyReleasedSeries,
        .recentlyAddedMovies,
        .recentlyAddedSeries
    ]

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
        let stored = Self.loadSectionPreferences()
        self.orderedSectionKinds = Self.sanitizedSectionOrder(from: stored.orderedKinds)
        self.hiddenSectionKinds = []
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

    func toggleFeaturedWatchlist(for item: MediaItem) {
        let targetValue = !(resolvedItemState(for: item.id)?.isFavorite ?? item.isFavorite)
        let previousFeed = feed
        let previousSelectedItem = selectedItem
        let previousSelectedEpisode = selectedEpisode

        errorMessage = nil
        applyFavoriteState(targetValue, to: item.id)

        Task {
            do {
                try await dependencies.apiClient.setFavorite(itemID: item.id, isFavorite: targetValue)
            } catch {
                await MainActor.run {
                    self.feed = previousFeed
                    self.selectedItem = previousSelectedItem
                    self.selectedEpisode = previousSelectedEpisode
                    self.rebuildVisibleRowsCache()
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    var sectionCustomizationKinds: [HomeSectionKind] {
        Self.supportedSectionKinds
    }

    func sectionTitle(for kind: HomeSectionKind) -> String {
        if let title = feed.rows.first(where: { $0.kind == kind })?.title {
            return title
        }

        switch kind {
        case .continueWatching:
            return "Continue Watching"
        case .recentlyReleasedMovies:
            return "Recently Released Movies"
        case .recentlyReleasedSeries:
            return "Recently Released TV Shows"
        case .nextUp:
            return "Next Up"
        case .recentlyAddedMovies:
            return "Recently Added Movies"
        case .recentlyAddedSeries:
            return "Recently Added TV"
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
        let merged = mergeEnrichedFeed(current: feed, processed: processed)
        guard feed != merged else { return }
        ensureKnownSectionKinds(from: merged.rows)
        feed = merged
        rebuildVisibleRowsCache()
    }

    private func mergeEnrichedFeed(current: HomeFeed, processed: HomeFeed) -> HomeFeed {
        let currentRowIDs = Set(current.rows.map(\.id))
        let processedRowIDs = Set(processed.rows.map(\.id))

        guard
            !current.rows.isEmpty,
            processed.rows.count < current.rows.count,
            processedRowIDs.isSubset(of: currentRowIDs)
        else {
            return processed
        }

        let processedRowsByID = Dictionary(uniqueKeysWithValues: processed.rows.map { ($0.id, $0) })
        let mergedRows = current.rows.map { processedRowsByID[$0.id] ?? $0 }

        let mergedFeatured: [MediaItem]
        if current.featured.isEmpty, !processed.featured.isEmpty {
            mergedFeatured = processed.featured
        } else {
            mergedFeatured = current.featured
        }

        return HomeFeed(featured: mergedFeatured, rows: mergedRows)
    }

    private func ensureKnownSectionKinds(from rows: [HomeRow]) {
        let knownKinds = Set(orderedSectionKinds)
        let missing = rows
            .map(\.kind)
            .filter { Self.supportedSectionKinds.contains($0) && !knownKinds.contains($0) }
        if !missing.isEmpty {
            orderedSectionKinds.append(contentsOf: missing)
            rebuildVisibleRowsCache()
            persistSectionPreferences()
        }
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

    private func resolvedItemState(for itemID: String) -> MediaItem? {
        if let featured = feed.featured.first(where: { $0.id == itemID }) {
            return featured
        }

        for row in feed.rows {
            if let item = row.items.first(where: { $0.id == itemID }) {
                return item
            }
        }

        return selectedItem?.id == itemID ? selectedItem : selectedEpisode?.id == itemID ? selectedEpisode : nil
    }

    private func applyFavoriteState(_ isFavorite: Bool, to itemID: String) {
        feed.featured = feed.featured.map { item in
            var updated = item
            if updated.id == itemID {
                updated.isFavorite = isFavorite
            }
            return updated
        }

        feed.rows = feed.rows.map { row in
            var updatedRow = row
            updatedRow.items = row.items.map { item in
                var updated = item
                if updated.id == itemID {
                    updated.isFavorite = isFavorite
                }
                return updated
            }
            return updatedRow
        }

        if selectedItem?.id == itemID {
            selectedItem?.isFavorite = isFavorite
        }

        if selectedEpisode?.id == itemID {
            selectedEpisode?.isFavorite = isFavorite
        }

        rebuildVisibleRowsCache()
    }

    private func persistSectionPreferences() {
        let preferences = HomeSectionPreferences(
            orderedKinds: Self.sanitizedSectionOrder(from: orderedSectionKinds),
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

    private static func sanitizedSectionOrder(from kinds: [HomeSectionKind]) -> [HomeSectionKind] {
        var seen = Set<HomeSectionKind>()
        let supported = Set(supportedSectionKinds)

        let preserved = kinds.filter { kind in
            supported.contains(kind) && seen.insert(kind).inserted
        }

        let missing = supportedSectionKinds.filter { !seen.contains($0) }
        return preserved + missing
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
            Self.supportedSectionKinds.contains(row.kind) && !hiddenSectionKinds.contains(row.kind)
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
            .recentlyReleasedMovies,
            .recentlyReleasedSeries,
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
