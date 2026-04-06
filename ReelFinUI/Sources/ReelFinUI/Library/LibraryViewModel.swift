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
#if os(tvOS)
    @Published var selectedFilter: MediaType? = .movie
#else
    @Published var selectedFilter: MediaType? = nil
#endif
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
            items = sorted(items + remote)
        } catch {
            AppLog.ui.error("Search failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var paginationTriggerItemID: String? {
        guard !isLoadingPage, !isLastPage, searchQuery.isEmpty else { return nil }
        return TVLibraryPaginationPolicy.triggerItemID(in: items)
    }

    func loadMoreIfNeeded() async {
        guard paginationTriggerItemID != nil else { return }
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
        var grouped: [String: MediaItem] = [:]
        var orderedKeys: [String] = []

        for item in values {
            let key = canonicalKey(for: item)
            if let existing = grouped[key] {
                grouped[key] = preferredItem(between: existing, and: item)
                continue
            }

            grouped[key] = item
            orderedKeys.append(key)
        }

        return orderedKeys.compactMap { grouped[$0] }
    }

    private func canonicalKey(for item: MediaItem) -> String {
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

    private func normalizedTitle(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let filtered = folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0)
        }
        return String(String.UnicodeScalarView(filtered))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func preferredItem(between lhs: MediaItem, and rhs: MediaItem) -> MediaItem {
        let lhsScore = qualityScore(for: lhs)
        let rhsScore = qualityScore(for: rhs)
        if lhsScore == rhsScore {
            return lhs.id <= rhs.id ? lhs : rhs
        }
        return lhsScore > rhsScore ? lhs : rhs
    }

    private func qualityScore(for item: MediaItem) -> Int {
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
}
