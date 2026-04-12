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
    nonisolated static let supportedSectionKinds: [HomeSectionKind] = [
        .continueWatching,
        .recentlyReleasedMovies,
        .recentlyReleasedSeries,
        .recentlyAddedMovies,
        .recentlyAddedSeries
    ]
    nonisolated static let defaultSectionOrder: [HomeSectionKind] = [
        .continueWatching,
        .recentlyReleasedMovies,
        .recentlyReleasedSeries,
        .recentlyAddedMovies,
        .recentlyAddedSeries
    ]

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
        let stored = HomeSectionPreferencesStore.load()
        self.orderedSectionKinds = Self.sanitizedSectionOrder(from: stored.orderedKinds)
        self.hiddenSectionKinds = Set(stored.hiddenKinds.filter { Self.supportedSectionKinds.contains($0) })
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
            let normalized = await normalizedFeed(cached)
            guard !normalized.rows.isEmpty || !normalized.featured.isEmpty else { return }

            ensureKnownSectionKinds(from: normalized.rows)
            if feed != normalized {
                feed = normalized
                rebuildVisibleRowsCache()
            }
            scheduleFeedEnrichment(for: normalized)
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
            guard let self else { return }
            await self.applyEnrichedFeed(visibleProcessed)

            guard feed.rows.count > visibleRowLimit else { return }

            do {
                try await Task.sleep(nanoseconds: 1_250_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            let processed = await HomeFeedProcessor.process(feed, seriesCache: seriesCache)
            guard !Task.isCancelled else { return }
            await self.applyEnrichedFeed(processed)
        }
    }

    private func applyEnrichedFeed(_ processed: HomeFeed) async {
        let merged = await normalizedFeed(mergeEnrichedFeed(current: feed, processed: processed))
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
        HomeSectionPreferencesStore.save(preferences)
    }

    nonisolated static func sanitizedSectionOrder(from kinds: [HomeSectionKind]) -> [HomeSectionKind] {
        var seen = Set<HomeSectionKind>()
        let supported = Set(supportedSectionKinds)

        let preserved = kinds.filter { kind in
            supported.contains(kind) && seen.insert(kind).inserted
        }

        let missing = supportedSectionKinds.filter { !seen.contains($0) }
        return preserved + missing
    }

    private func normalizedFeed(_ feed: HomeFeed) async -> HomeFeed {
        var normalizedRows: [HomeRow] = []
        normalizedRows.reserveCapacity(feed.rows.count)

        for row in feed.rows {
            var normalizedRow = row
            normalizedRow.items = await deduplicatedItems(row.items)
            normalizedRows.append(normalizedRow)
        }

        return HomeFeed(
            featured: await deduplicatedItems(feed.featured),
            rows: normalizedRows
        )
    }

    private func deduplicatedItems(_ items: [MediaItem]) async -> [MediaItem] {
        let uniqueByID = Self.deduplicatedItemsByID(items)
        var grouped: [String: MediaItem] = [:]
        var orderedKeys: [String] = []

        for item in uniqueByID {
            let key = Self.canonicalKey(for: item)
            if let existing = grouped[key] {
                grouped[key] = await preferredDuplicate(between: existing, and: item)
            } else {
                grouped[key] = item
                orderedKeys.append(key)
            }
        }

        return orderedKeys.compactMap { grouped[$0] }
    }

    private static func deduplicatedItemsByID(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private func preferredDuplicate(between lhs: MediaItem, and rhs: MediaItem) async -> MediaItem {
        let lhsOptimization = await optimizationPreferenceScore(for: lhs)
        let rhsOptimization = await optimizationPreferenceScore(for: rhs)
        if lhsOptimization != rhsOptimization {
            return lhsOptimization > rhsOptimization ? lhs : rhs
        }

        let lhsQuality = Self.qualityScore(for: lhs)
        let rhsQuality = Self.qualityScore(for: rhs)
        if lhsQuality == rhsQuality {
            return lhs.id <= rhs.id ? lhs : rhs
        }

        return lhsQuality > rhsQuality ? lhs : rhs
    }

    private func optimizationPreferenceScore(for item: MediaItem) async -> Int {
        guard let playbackItem = await optimizationPlaybackItem(for: item) else {
            return 0
        }

        await dependencies.playbackWarmupManager.warm(itemID: playbackItem.id)
        let selection = await dependencies.playbackWarmupManager.selection(for: playbackItem.id)

        switch ApplePlaybackOptimizationStatus(selection: selection) {
        case .optimized?:
            return 2
        case .needsServerPrep?:
            return 1
        case nil:
            return 0
        }
    }

    private func optimizationPlaybackItem(for item: MediaItem) async -> MediaItem? {
        guard item.mediaType == .series else {
            return item
        }

        do {
            return try await dependencies.detailRepository.loadNextUpEpisode(seriesID: item.id)
        } catch {
            return nil
        }
    }

    private static func canonicalKey(for item: MediaItem) -> String {
        switch item.mediaType {
        case .episode:
            return [
                "episode",
                item.parentID ?? normalizedTitle(item.seriesName ?? item.name),
                String(item.parentIndexNumber ?? -1),
                String(item.indexNumber ?? -1)
            ].joined(separator: "|")
        default:
            let runtimeBucket = item.runtimeTicks.map { String($0 / 600_000_000) } ?? "_"
            return [
                item.mediaType.rawValue,
                normalizedTitle(item.name),
                String(item.year ?? 0),
                runtimeBucket
            ].joined(separator: "|")
        }
    }

    private static func normalizedTitle(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let filtered = folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0)
        }
        return String(String.UnicodeScalarView(filtered))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func qualityScore(for item: MediaItem) -> Int {
        var score = 0
        score += item.overview?.isEmpty == false ? 5 : 0
        score += item.posterTag == nil ? 0 : 4
        score += item.backdropTag == nil ? 0 : 3
        score += item.communityRating == nil ? 0 : 2
        score += item.playbackPositionTicks == nil ? 0 : 2
        score += item.isFavorite ? 1 : 0
        score += item.isPlayed ? 1 : 0
        score += min(item.genres.count, 3)
        return score
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

struct HomeSectionPreferences: Codable {
    var orderedKinds: [HomeSectionKind]
    var hiddenKinds: [HomeSectionKind]
}

enum HomeSectionPreferencesStore {
    static let storageKey = "home.sectionPreferences.v3"

    static func load(defaults: UserDefaults = .standard) -> HomeSectionPreferences {
        guard
            let data = defaults.data(forKey: storageKey),
            let preferences = try? JSONDecoder().decode(HomeSectionPreferences.self, from: data)
        else {
            return HomeSectionPreferences(
                orderedKinds: HomeViewModel.defaultSectionOrder,
                hiddenKinds: []
            )
        }

        return preferences
    }

    static func save(_ preferences: HomeSectionPreferences, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
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
