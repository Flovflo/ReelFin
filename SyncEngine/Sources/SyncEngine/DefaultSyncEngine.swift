import Foundation
import Shared

public actor DefaultSyncEngine: SyncEngineProtocol {
    private let apiClient: JellyfinAPIClientProtocol
    private let repository: MetadataRepositoryProtocol
    private let imagePipeline: ImagePipelineProtocol

    private var isSyncing = false

    public init(
        apiClient: JellyfinAPIClientProtocol,
        repository: MetadataRepositoryProtocol,
        imagePipeline: ImagePipelineProtocol
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.imagePipeline = imagePipeline
    }

    public func sync(reason: SyncReason) async {
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

            // Incremental sync can legitimately return empty data; avoid replacing an existing home feed with blanks.
            if lastSyncDate != nil, isEmpty(feed) {
                let fullFeed = try await apiClient.fetchHomeFeed(since: nil)
                if isEmpty(fullFeed) {
                    let cached = try await repository.fetchHomeFeed()
                    if !isEmpty(cached) {
                        feed = cached
                    }
                } else {
                    feed = fullFeed
                }
            }

            try await repository.saveHomeFeed(feed)
            let feedItems = feed.featured + feed.rows.flatMap(\.items)
            try await repository.upsertItems(feedItems)
            try await repository.setLastSyncDate(Date())

            let posterURLs = await buildPrefetchURLs(feed: feed)
            await imagePipeline.prefetch(urls: posterURLs)

            AppLog.sync.debug("Home feed rows: \(feed.rows.count, privacy: .public), items: \(feedItems.count, privacy: .public)")
            interval.end(name: "metadata_sync", message: "success")
            AppLog.sync.debug("Sync finished")
        } catch {
            interval.end(name: "metadata_sync", message: "failure")
            AppLog.sync.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func buildPrefetchURLs(feed: HomeFeed) async -> [URL] {
        var urls = [URL]()
        let items = feed.featured + feed.rows.flatMap(\.items)
        for item in items.prefix(60) {
            if let url = await apiClient.imageURL(for: item.id, type: .primary, width: 420, quality: 85) {
                urls.append(url)
            }
        }
        return urls
    }

    private func isEmpty(_ feed: HomeFeed) -> Bool {
        !feed.featured.isEmpty ? false : feed.rows.allSatisfy { $0.items.isEmpty }
    }
}
