import Foundation
import Shared
import SwiftUI

struct LibraryCriteria: Equatable, Sendable {
    let searchQuery: String
    let filter: MediaType
    let sortMode: LibraryViewModel.SortMode

    init(
        searchQuery: String,
        filter: MediaType,
        sortMode: LibraryViewModel.SortMode
    ) {
        self.searchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        self.filter = filter
        self.sortMode = sortMode
    }
}

@MainActor
@Observable
final class LibraryViewModel {
    enum SortMode: String, CaseIterable, Sendable {
        case recent = "Recent"
        case title = "Title"
    }

    var items: [MediaItem] = []
    var searchQuery = ""
    var selectedFilter: MediaType = .movie
    var sortMode: SortMode = .recent
    private(set) var isLoadingPage = false
    private(set) var isRefreshing = false
    var selectedItem: MediaItem?

    private let dependencies: ReelFinDependencies

    private var currentPage = 0
    private let pageSize = 48
    private var isLastPage = false

    private var criteriaGeneration = 0
    private var paginationRequestID = 0
    private var loadingToken = 0
    private var activeCriteria: LibraryCriteria
    private var criteriaTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var loadingOwner: LoadingOwner?

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
        activeCriteria = LibraryCriteria(
            searchQuery: "",
            filter: .movie,
            sortMode: .recent
        )
    }

    @discardableResult
    func submitCriteria() -> Task<Void, Never> {
        let criteria = LibraryCriteria(
            searchQuery: searchQuery,
            filter: selectedFilter,
            sortMode: sortMode
        )

        criteriaGeneration &+= 1
        paginationRequestID &+= 1
        criteriaTask?.cancel()
        paginationTask?.cancel()
        criteriaTask = nil
        paginationTask = nil
        activeCriteria = criteria
        currentPage = 0
        isLastPage = false

        let request = CriteriaRequest(
            generation: criteriaGeneration,
            criteria: criteria,
            loadingToken: beginLoading(
                generation: criteriaGeneration,
                paginationRequestID: nil
            )
        )
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await perform(request)
        }
        criteriaTask = task
        return task
    }

    @discardableResult
    func submitPaginationIfNeeded() -> Task<Void, Never>? {
        let generation = criteriaGeneration
        let criteria = activeCriteria

        guard !isCriteriaLoading(generation: generation),
              searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              criteria.searchQuery.isEmpty,
              !isLastPage,
              paginationTask == nil else {
            return nil
        }

        paginationRequestID &+= 1
        let request = PaginationRequest(
            generation: generation,
            requestID: paginationRequestID,
            criteria: criteria,
            page: currentPage,
            loadingToken: beginLoading(
                generation: generation,
                paginationRequestID: paginationRequestID
            )
        )
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await perform(request)
        }
        paginationTask = task
        return task
    }

    func cancelIntents() {
        criteriaGeneration &+= 1
        paginationRequestID &+= 1
        criteriaTask?.cancel()
        paginationTask?.cancel()
        criteriaTask = nil
        paginationTask = nil
        loadingOwner = nil
        isLoadingPage = false
    }

    func loadInitial() async {
        let task = submitCriteria()
        await task.value
    }

    func manualRefresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let task = submitCriteria()
        await task.value
    }

    func searchChanged() async {
        let task = submitCriteria()
        await task.value
    }

    var paginationTriggerItemID: String? {
        guard !isLoadingPage,
              !isLastPage,
              searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              activeCriteria.searchQuery.isEmpty else {
            return nil
        }
        return TVLibraryPaginationPolicy.triggerItemID(in: items)
    }

    func loadMoreIfNeeded() async {
        guard let task = submitPaginationIfNeeded() else { return }
        await task.value
    }

    func select(item: MediaItem, animated: Bool = true) {
        updateSelection(animated: animated) {
            selectedItem = item
        }
    }

    func dismissDetail(animated: Bool = true) {
        updateSelection(animated: animated) {
            selectedItem = nil
        }
    }

    private func updateSelection(animated: Bool, update: () -> Void) {
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                update()
            }
        } else {
            update()
        }
    }

    private func perform(_ request: CriteriaRequest) async {
        defer { finish(request) }
        guard !Task.isCancelled, owns(request) else { return }

        if request.criteria.searchQuery.isEmpty {
            await loadCachedLibrary(for: request)
            guard !Task.isCancelled, owns(request) else { return }
            await loadRemoteLibrary(for: request)
        } else {
            await loadSearch(for: request)
        }
    }

    private func loadCachedLibrary(for request: CriteriaRequest) async {
        let ownership = RequestOwnership.criteria(request)

        do {
            guard let query = try await makeLibraryQuery(
                criteria: request.criteria,
                page: 0,
                pageSize: max(pageSize, 120),
                ownership: ownership
            ) else {
                return
            }
            guard !Task.isCancelled, owns(request) else { return }

            let local = try await dependencies.repository.fetchLibraryItems(query: query)
            guard !Task.isCancelled, owns(request) else { return }
            items = sorted(local, criteria: request.criteria)
        } catch {
            guard !Task.isCancelled, owns(request) else { return }
            AppLog.ui.error("Local library load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadRemoteLibrary(for request: CriteriaRequest) async {
        let ownership = RequestOwnership.criteria(request)

        do {
            guard let query = try await makeLibraryQuery(
                criteria: request.criteria,
                page: 0,
                pageSize: pageSize,
                ownership: ownership
            ) else {
                return
            }
            guard !Task.isCancelled, owns(request) else { return }

            let remoteItems = try await dependencies.apiClient.fetchLibraryItems(query: query)
            guard !Task.isCancelled, owns(request) else { return }

            isLastPage = remoteItems.count < pageSize
            items = sorted(remoteItems, criteria: request.criteria)
            currentPage = 1

            guard !Task.isCancelled, owns(request) else { return }
            try await dependencies.repository.upsertItems(remoteItems)
            guard !Task.isCancelled, owns(request) else { return }
        } catch {
            guard !Task.isCancelled, owns(request) else { return }
            AppLog.ui.error("Remote library load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadSearch(for request: CriteriaRequest) async {
        let ownership = RequestOwnership.criteria(request)

        do {
            let local = try await dependencies.repository.searchItems(
                query: request.criteria.searchQuery,
                limit: 100
            )
            guard !Task.isCancelled, owns(request) else { return }
            let committedLocal = sorted(local, criteria: request.criteria)
            items = committedLocal

            guard let query = try await makeLibraryQuery(
                criteria: request.criteria,
                page: 0,
                pageSize: pageSize,
                ownership: ownership
            ) else {
                return
            }
            guard !Task.isCancelled, owns(request) else { return }

            let remote = try await dependencies.apiClient.fetchLibraryItems(query: query)
            guard !Task.isCancelled, owns(request) else { return }

            try await dependencies.repository.upsertItems(remote)
            guard !Task.isCancelled, owns(request) else { return }
            items = sorted(committedLocal + remote, criteria: request.criteria)
        } catch {
            guard !Task.isCancelled, owns(request) else { return }
            AppLog.ui.error("Search failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func perform(_ request: PaginationRequest) async {
        defer { finish(request) }
        guard !Task.isCancelled, owns(request) else { return }
        let ownership = RequestOwnership.pagination(request)

        do {
            guard let query = try await makeLibraryQuery(
                criteria: request.criteria,
                page: request.page,
                pageSize: pageSize,
                ownership: ownership
            ) else {
                return
            }
            guard !Task.isCancelled, owns(request) else { return }

            let remoteItems = try await dependencies.apiClient.fetchLibraryItems(query: query)
            guard !Task.isCancelled, owns(request) else { return }

            isLastPage = remoteItems.count < pageSize
            items = sorted(items + remoteItems, criteria: request.criteria)
            currentPage = request.page + 1

            guard !Task.isCancelled, owns(request) else { return }
            try await dependencies.repository.upsertItems(remoteItems)
            guard !Task.isCancelled, owns(request) else { return }
        } catch {
            guard !Task.isCancelled, owns(request) else { return }
            AppLog.ui.error("Remote library load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeLibraryQuery(
        criteria: LibraryCriteria,
        page: Int,
        pageSize: Int,
        ownership: RequestOwnership
    ) async throws -> LibraryQuery? {
        guard !Task.isCancelled, owns(ownership) else { return nil }
        guard let scopedViewIDs = try await resolvedLibraryViewIDs(
            criteria: criteria,
            ownership: ownership
        ) else {
            return nil
        }
        guard !Task.isCancelled, owns(ownership) else { return nil }

        if scopedViewIDs.isEmpty {
            return LibraryQuery(
                viewID: nil,
                page: page,
                pageSize: pageSize,
                query: criteria.searchQuery.isEmpty ? nil : criteria.searchQuery,
                mediaType: criteria.filter,
                sortBy: querySortBy(for: criteria),
                sortDescending: querySortDescending(for: criteria)
            )
        }

        return LibraryQuery(
            viewIDs: scopedViewIDs,
            page: page,
            pageSize: pageSize,
            query: criteria.searchQuery.isEmpty ? nil : criteria.searchQuery,
            mediaType: criteria.filter,
            sortBy: querySortBy(for: criteria),
            sortDescending: querySortDescending(for: criteria)
        )
    }

    private func resolvedLibraryViewIDs(
        criteria: LibraryCriteria,
        ownership: RequestOwnership
    ) async throws -> [String]? {
        guard !Task.isCancelled, owns(ownership) else { return nil }
        let cachedViews = try await dependencies.repository.fetchLibraryViews()
        guard !Task.isCancelled, owns(ownership) else { return nil }

        let cachedMatches = matchingLibraryViewIDs(in: cachedViews, criteria: criteria)
        if !cachedMatches.isEmpty {
            return cachedMatches
        }

        guard !Task.isCancelled, owns(ownership) else { return nil }
        let remoteViews = try await dependencies.apiClient.fetchUserViews()
        guard !Task.isCancelled, owns(ownership) else { return nil }

        if !remoteViews.isEmpty {
            guard !Task.isCancelled, owns(ownership) else { return nil }
            try await dependencies.repository.saveLibraryViews(remoteViews)
            guard !Task.isCancelled, owns(ownership) else { return nil }
        }

        return matchingLibraryViewIDs(in: remoteViews, criteria: criteria)
    }

    private func matchingLibraryViewIDs(
        in views: [Shared.LibraryView],
        criteria: LibraryCriteria
    ) -> [String] {
        views
            .filter { $0.supports(mediaType: criteria.filter) }
            .map(\.id)
    }

    private func querySortBy(for criteria: LibraryCriteria) -> LibraryItemSort {
        switch criteria.sortMode {
        case .recent:
            return .dateCreated
        case .title:
            return .sortName
        }
    }

    private func querySortDescending(for criteria: LibraryCriteria) -> Bool {
        switch criteria.sortMode {
        case .recent:
            return true
        case .title:
            return false
        }
    }

    private func sorted(_ values: [MediaItem], criteria: LibraryCriteria) -> [MediaItem] {
        let matchingType = values.filter { $0.mediaType == criteria.filter }
        let unique = deduped(matchingType)
        switch criteria.sortMode {
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
        var byID: [String: MediaItem] = [:]
        var orderedIDs: [String] = []

        for item in values {
            if let existing = byID[item.id] {
                byID[item.id] = Self.preferredItem(between: existing, and: item)
                continue
            }

            byID[item.id] = item
            orderedIDs.append(item.id)
        }

        var grouped: [String: MediaItem] = [:]
        var orderedKeys: [String] = []

        for item in orderedIDs.compactMap({ byID[$0] }) {
            let key = canonicalKey(for: item)
            if let existing = grouped[key] {
                grouped[key] = Self.preferredItem(between: existing, and: item)
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

    private static func preferredItem(between lhs: MediaItem, and rhs: MediaItem) -> MediaItem {
        let lhsScore = qualityScore(for: lhs)
        let rhsScore = qualityScore(for: rhs)
        if lhsScore == rhsScore {
            return lhs.id <= rhs.id ? lhs : rhs
        }
        return lhsScore > rhsScore ? lhs : rhs
    }

    private static func qualityScore(for item: MediaItem) -> Int {
        var score = 0
        score += item.hasDolbyVision ? 60 : 0
        score += item.has4K ? 40 : 0
        score += item.overview?.isEmpty == false ? 5 : 0
        score += item.posterTag == nil ? 0 : 4
        score += item.backdropTag == nil ? 0 : 3
        score += item.communityRating == nil ? 0 : 2
        score += item.playbackPositionTicks == nil ? 0 : 2
        score += item.hasClosedCaptions ? 1 : 0
        score += item.isFavorite ? 1 : 0
        score += item.isPlayed ? 1 : 0
        score += min(item.genres.count, 3)
        return score
    }

    private func beginLoading(
        generation: Int,
        paginationRequestID: Int?
    ) -> Int {
        loadingToken &+= 1
        loadingOwner = LoadingOwner(
            token: loadingToken,
            generation: generation,
            paginationRequestID: paginationRequestID
        )
        isLoadingPage = true
        return loadingToken
    }

    private func isCriteriaLoading(generation: Int) -> Bool {
        guard let loadingOwner else { return false }
        return loadingOwner.generation == generation && loadingOwner.paginationRequestID == nil
    }

    private func owns(_ request: CriteriaRequest) -> Bool {
        criteriaGeneration == request.generation && activeCriteria == request.criteria
    }

    private func owns(_ request: PaginationRequest) -> Bool {
        criteriaGeneration == request.generation &&
            paginationRequestID == request.requestID &&
            activeCriteria == request.criteria
    }

    private func owns(_ ownership: RequestOwnership) -> Bool {
        switch ownership {
        case let .criteria(request):
            return owns(request)
        case let .pagination(request):
            return owns(request)
        }
    }

    private func finish(_ request: CriteriaRequest) {
        guard owns(request) else { return }
        criteriaTask = nil
        clearLoading(token: request.loadingToken)
    }

    private func finish(_ request: PaginationRequest) {
        guard owns(request) else { return }
        paginationTask = nil
        clearLoading(token: request.loadingToken)
    }

    private func clearLoading(token: Int) {
        guard loadingOwner?.token == token else { return }
        loadingOwner = nil
        isLoadingPage = false
    }
}

private struct CriteriaRequest: Equatable, Sendable {
    let generation: Int
    let criteria: LibraryCriteria
    let loadingToken: Int
}

private struct PaginationRequest: Equatable, Sendable {
    let generation: Int
    let requestID: Int
    let criteria: LibraryCriteria
    let page: Int
    let loadingToken: Int
}

private enum RequestOwnership: Equatable, Sendable {
    case criteria(CriteriaRequest)
    case pagination(PaginationRequest)
}

private struct LoadingOwner: Equatable, Sendable {
    let token: Int
    let generation: Int
    let paginationRequestID: Int?
}
