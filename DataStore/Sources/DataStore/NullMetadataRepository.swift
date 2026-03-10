import Foundation
import Shared

public actor NullMetadataRepository: MetadataRepositoryProtocol {
    public init() {}

    public func saveLibraryViews(_ views: [LibraryView]) async throws {}

    public func fetchLibraryViews() async throws -> [LibraryView] {
        []
    }

    public func saveHomeFeed(_ feed: HomeFeed) async throws {}

    public func fetchHomeFeed() async throws -> HomeFeed {
        .empty
    }

    public func upsertItems(_ items: [MediaItem]) async throws {}

    public func fetchItem(id: String) async throws -> MediaItem? {
        nil
    }

    public func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        []
    }

    public func searchItems(query: String, limit: Int) async throws -> [MediaItem] {
        []
    }

    public func savePlaybackProgress(_ progress: PlaybackProgress) async throws {}

    public func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? {
        nil
    }

    public func fetchLastSyncDate() async throws -> Date? {
        nil
    }

    public func setLastSyncDate(_ date: Date) async throws {}
}
