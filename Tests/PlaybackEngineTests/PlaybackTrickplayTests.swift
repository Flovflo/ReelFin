import AVFoundation
@testable import PlaybackEngine
import Shared
import XCTest

@MainActor
final class PlaybackTrickplayTests: XCTestCase {
    func testTrickplayVariantMapsAbsoluteTimeToSpriteCoordinates() {
        let variant = TrickplayVariant(
            width: 320,
            height: 180,
            tileWidth: 5,
            tileHeight: 4,
            thumbnailCount: 80,
            intervalMilliseconds: 1_000,
            bandwidth: 512_000
        )

        let frame = variant.frame(for: 23.8)

        XCTAssertEqual(frame?.thumbnailIndex, 23)
        XCTAssertEqual(frame?.tileImageIndex, 1)
        XCTAssertEqual(frame?.column, 3)
        XCTAssertEqual(frame?.row, 0)
        XCTAssertEqual(frame?.cropRect.origin.x, 960)
        XCTAssertEqual(frame?.cropRect.origin.y, 0)
        XCTAssertEqual(frame?.cropRect.size.width, 320)
        XCTAssertEqual(frame?.cropRect.size.height, 180)
    }

    func testTrickplayManifestPrefersClosestWidthAtOrAboveRequestedSize() {
        let manifest = TrickplayManifest(
            itemID: "episode-1",
            sourceID: "source-1",
            variants: [
                TrickplayVariant(width: 160, height: 90, tileWidth: 5, tileHeight: 5, thumbnailCount: 100, intervalMilliseconds: 1_000),
                TrickplayVariant(width: 320, height: 180, tileWidth: 5, tileHeight: 5, thumbnailCount: 100, intervalMilliseconds: 1_000),
                TrickplayVariant(width: 640, height: 360, tileWidth: 5, tileHeight: 5, thumbnailCount: 100, intervalMilliseconds: 1_000)
            ]
        )

        XCTAssertEqual(manifest.preferredVariant(forThumbnailWidth: 200)?.width, 320)
        XCTAssertEqual(manifest.preferredVariant(forThumbnailWidth: 640)?.width, 640)
        XCTAssertEqual(manifest.preferredVariant(forThumbnailWidth: 900)?.width, 640)
    }

    func testTransportStateCarriesTrickplayManifestAndClearsOnStop() async throws {
        let controller = PlaybackSessionController(
            apiClient: TrickplayTransportStateAPIClient(),
            repository: TrickplayTransportStateRepository()
        )
        let manifest = TrickplayManifest(
            itemID: "episode-1",
            sourceID: "source-1",
            variants: [
                TrickplayVariant(width: 320, height: 180, tileWidth: 5, tileHeight: 5, thumbnailCount: 100, intervalMilliseconds: 1_000)
            ]
        )

        controller.activeTrickplayManifest = manifest
        controller.playbackTimeOffsetSeconds = 120
        try await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertEqual(controller.transportState.trickplayManifest, manifest)
        XCTAssertEqual(controller.transportState.playbackTimeOffsetSeconds, 120)

        controller.currentItemID = "episode-1"
        controller.player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: "https://example.com/video.mp4")!))
        controller.stop()

        XCTAssertNil(controller.transportState.trickplayManifest)
        XCTAssertEqual(controller.transportState.playbackTimeOffsetSeconds, 0)
    }
}

private actor TrickplayTransportStateRepository: MetadataRepositoryProtocol {
    func saveLibraryViews(_ views: [LibraryView]) async throws {}
    func fetchLibraryViews() async throws -> [LibraryView] { [] }
    func saveHomeFeed(_ feed: HomeFeed) async throws {}
    func fetchHomeFeed() async throws -> HomeFeed { .empty }
    func upsertItems(_ items: [MediaItem]) async throws {}
    func fetchItem(id: String) async throws -> MediaItem? { nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { [] }
    func searchItems(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func savePlaybackProgress(_ progress: PlaybackProgress) async throws {}
    func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? { nil }
    func fetchLastSyncDate() async throws -> Date? { nil }
    func setLastSyncDate(_ date: Date) async throws {}
}

private final class TrickplayTransportStateAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    func currentConfiguration() async -> ServerConfiguration? { nil }
    func currentSession() async -> UserSession? { nil }
    func configure(server: ServerConfiguration) async throws {}
    func testConnection(serverURL: URL) async throws {}
    func authenticate(credentials: UserCredentials) async throws -> UserSession { throw AppError.unknown }
    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { nil }
    func fetchUserViews() async throws -> [LibraryView] { [] }
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed { .empty }
    func fetchItem(id: String) async throws -> MediaItem { throw AppError.unknown }
    func fetchItemDetail(id: String) async throws -> MediaDetail { throw AppError.unknown }
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { [] }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? { nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { [] }
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] { [] }
    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] { [] }
    func fetchMediaSegments(itemID: String) async throws -> [MediaSegment] { [] }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? { nil }
    func prefetchImages(for items: [MediaItem]) async {}
    func reportPlayback(progress: PlaybackProgressUpdate) async throws {}
    func reportPlaybackStopped(progress: PlaybackProgressUpdate) async throws {}
    func reportPlayed(itemID: String) async throws {}
    func setPlayedState(itemID: String, isPlayed: Bool) async throws {}
    func setFavorite(itemID: String, isFavorite: Bool) async throws {}
}
