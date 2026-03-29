import Foundation
import Shared

public actor DefaultSyncEngine: SyncEngineProtocol {
    private let apiClient: any JellyfinAPIClientProtocol & Sendable
    private let repository: any MetadataRepositoryProtocol & Sendable
    private let imagePipeline: any ImagePipelineProtocol & Sendable

    private var isSyncing = false
    private var lastForegroundLikeSyncAt: Date?
    private let foregroundLikeCooldown: TimeInterval = 45

    public init(
        apiClient: any JellyfinAPIClientProtocol & Sendable,
        repository: any MetadataRepositoryProtocol & Sendable,
        imagePipeline: any ImagePipelineProtocol & Sendable
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.imagePipeline = imagePipeline
    }

    public func sync(reason: SyncReason) async {
        if shouldSkipForegroundLikeSync(reason: reason) {
            AppLog.sync.debug("Skipping sync: foreground cooldown active.")
            return
        }

        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let interval = SignpostInterval(signposter: Signpost.sync, name: "metadata_sync")
        AppLog.sync.debug("Starting sync: \(reason.rawValue, privacy: .public)")

        do {
            let lastSyncDate = try await repository.fetchLastSyncDate()
            let views = try await apiClient.fetchUserViews()
            try await repository.saveLibraryViews(views)

            var feed = try await apiClient.fetchHomeFeed(since: lastSyncDate)

            // Incremental feed can be degraded (for example only "Continue Watching").
            // In that case, fetch a full feed before overwriting cache.
            if lastSyncDate != nil, shouldRefreshWithFullFeed(feed) {
                do {
                    let fullFeed = try await apiClient.fetchHomeFeed(since: nil)
                    if isEmpty(fullFeed) {
                        let cached = try await repository.fetchHomeFeed()
                        if !isEmpty(cached) {
                            feed = cached
                        }
                    } else if homeFeedScore(fullFeed) >= homeFeedScore(feed) {
                        feed = fullFeed
                    }
                } catch {
                    AppLog.sync.warning(
                        "Full-feed refresh fallback failed: \(error.localizedDescription, privacy: .public). Keeping incremental feed."
                    )
                }
            }

            try await repository.saveHomeFeed(feed)
            try await repository.setLastSyncDate(Date())
            markForegroundLikeSyncIfNeeded(reason: reason)

            let prefetchLimit = reason == .appLaunch ? 8 : 16
            let posterURLs = await buildPrefetchURLs(feed: feed, limit: prefetchLimit)
            if !posterURLs.isEmpty {
                let imagePipeline = imagePipeline
                Task.detached(priority: .background) {
                    await imagePipeline.prefetch(urls: posterURLs)
                }
            }

            let feedItems = feed.featured + feed.rows.flatMap(\.items)
            AppLog.sync.debug("Home feed rows: \(feed.rows.count, privacy: .public), items: \(feedItems.count, privacy: .public)")
            interval.end(name: "metadata_sync", message: "success")
            AppLog.sync.debug("Sync finished")
        } catch {
            interval.end(name: "metadata_sync", message: "failure")
            AppLog.sync.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func shouldSkipForegroundLikeSync(reason: SyncReason) -> Bool {
        guard reason == .appForeground else { return false }
        guard let last = lastForegroundLikeSyncAt else { return false }
        return Date().timeIntervalSince(last) < foregroundLikeCooldown
    }

    private func markForegroundLikeSyncIfNeeded(reason: SyncReason) {
        switch reason {
        case .appLaunch, .appForeground:
            lastForegroundLikeSyncAt = Date()
        case .manualRefresh, .backgroundRefresh:
            break
        }
    }

    private func buildPrefetchURLs(feed: HomeFeed, limit: Int) async -> [URL] {
        var urls = [URL]()
        let items = feed.featured + feed.rows.flatMap(\.items)
        for item in items.prefix(limit) {
            if let url = await apiClient.imageURL(for: item.id, type: .primary, width: 420, quality: 85) {
                urls.append(url)
            }
        }
        return urls
    }

    private func isEmpty(_ feed: HomeFeed) -> Bool {
        !feed.featured.isEmpty ? false : feed.rows.allSatisfy { $0.items.isEmpty }
    }

    private func shouldRefreshWithFullFeed(_ feed: HomeFeed) -> Bool {
        if isEmpty(feed) {
            return true
        }

        let nonEmptyRows = feed.rows.filter { !$0.items.isEmpty }
        if nonEmptyRows.isEmpty {
            return true
        }

        let contentKinds: Set<HomeSectionKind> = [
            .recentlyAddedMovies,
            .recentlyAddedSeries,
            .popular,
            .trending,
            .movies,
            .shows,
            .latest
        ]
        let hasContentRows = nonEmptyRows.contains { contentKinds.contains($0.kind) }

        // Incremental feeds can contain only resume/next-up rails, which degrades Home.
        if !hasContentRows {
            return true
        }

        if feed.featured.isEmpty, nonEmptyRows.count <= 1 {
            return true
        }

        return false
    }

    private func homeFeedScore(_ feed: HomeFeed) -> Int {
        let featuredScore = feed.featured.count * 3
        let nonEmptyRows = feed.rows.filter { !$0.items.isEmpty }.count * 2
        let rowItems = feed.rows.reduce(0) { partial, row in
            partial + min(row.items.count, 20)
        }
        return featuredScore + nonEmptyRows + rowItems
    }
}
