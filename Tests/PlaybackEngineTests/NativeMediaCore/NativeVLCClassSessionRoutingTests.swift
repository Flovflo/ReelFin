@testable import PlaybackEngine
import Foundation
import Shared
import XCTest

@MainActor
final class NativeVLCClassSessionRoutingTests: XCTestCase {
    func testNativeModeMigrationClearsStoredForceH264ProfilePins() {
        let suiteName = "NativeVLCClassSessionRoutingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            ["item-1": TranscodeURLProfile.forceH264Transcode.rawValue],
            forKey: PlaybackSessionController.preferredProfileStorageKey
        )

        PlaybackSessionController.clearStoredPreferredTranscodeProfiles(defaults: defaults)

        XCTAssertNil(defaults.dictionary(forKey: PlaybackSessionController.preferredProfileStorageKey))
    }

    func testDebugRuntimeNativeModeBypassesLegacyAVPlayerAndTranscodeSelection() async throws {
        let defaultsKey = NativeVLCClassPlayerRuntimeDefaults.enabledKey
        let previousOverride = UserDefaults.standard.object(forKey: defaultsKey)
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer {
            if let previousOverride {
                UserDefaults.standard.set(previousOverride, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }

        let itemID = "item-1"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let streamURL = root.appendingPathComponent("Videos").appendingPathComponent(itemID).appendingPathComponent("stream")
        try FileManager.default.createDirectory(at: streamURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await MP4PlaybackFixture.makeTinyH264AACMP4(at: streamURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let config = NativeVLCClassPlayerConfig(enabled: false, allowServerTranscodeFallback: true)
        let apiClient = NativeSessionRoutingAPIClient(
            configuration: ServerConfiguration(serverURL: root, nativeVLCClassPlayerConfig: config),
            source: MediaSource(
                id: "source-1",
                itemID: itemID,
                name: "Original",
                fileSize: Int64((try? FileManager.default.attributesOfItem(atPath: streamURL.path)[.size] as? NSNumber)?.intValue ?? 0),
                container: "mp4",
                videoCodec: "h264",
                audioCodec: "aac",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                transcodeURL: URL(string: "https://jellyfin.example/videos/item/master.m3u8?VideoCodec=h264&RequireAvc=true")
            )
        )
        let controller = PlaybackSessionController(apiClient: apiClient, repository: NativeSessionRoutingRepository())

        try await controller.load(item: MediaItem(id: itemID, name: "Fixture", mediaType: .movie), autoPlay: false)

        XCTAssertTrue(controller.isNativeVLCClassPlayerActive)
        XCTAssertEqual(controller.nativeVLCPlaybackURL?.path, streamURL.path)
        XCTAssertNil(controller.player.currentItem)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.allowTranscoding, false)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.enableDirectStream, false)
        XCTAssertFalse(controller.nativeVLCDiagnosticsOverlayLines.joined().contains(".m3u8"))
        XCTAssertTrue(controller.nativeVLCDiagnosticsOverlayLines.contains("originalMediaRequested=true"))
        XCTAssertTrue(controller.nativeVLCDiagnosticsOverlayLines.contains("serverTranscodeUsed=false"))
        XCTAssertTrue(controller.nativeVLCDiagnosticsOverlayLines.contains { $0.contains("demuxer=MP4Demuxer") })
    }

    func testNativeModeStopReportsNativePlaybackTime() async throws {
        let defaultsKey = NativeVLCClassPlayerRuntimeDefaults.enabledKey
        let previousOverride = UserDefaults.standard.object(forKey: defaultsKey)
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer {
            if let previousOverride {
                UserDefaults.standard.set(previousOverride, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }

        let itemID = "item-progress"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let streamURL = root.appendingPathComponent("Videos").appendingPathComponent(itemID).appendingPathComponent("stream")
        try FileManager.default.createDirectory(at: streamURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await MP4PlaybackFixture.makeTinyH264AACMP4(at: streamURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let stoppedExpectation = expectation(description: "native stopped progress reported")
        let apiClient = NativeSessionRoutingAPIClient(
            configuration: ServerConfiguration(serverURL: root, nativeVLCClassPlayerConfig: NativeVLCClassPlayerConfig(enabled: true)),
            source: MediaSource(
                id: "source-progress",
                itemID: itemID,
                name: "Original",
                fileSize: Int64((try? FileManager.default.attributesOfItem(atPath: streamURL.path)[.size] as? NSNumber)?.intValue ?? 0),
                container: "mp4",
                videoCodec: "h264",
                audioCodec: "aac",
                supportsDirectPlay: false,
                supportsDirectStream: false
            ),
            stoppedExpectation: stoppedExpectation
        )
        let repository = NativeSessionRoutingRepository()
        let controller = PlaybackSessionController(apiClient: apiClient, repository: repository)

        try await controller.load(item: MediaItem(id: itemID, name: "Fixture", mediaType: .movie), autoPlay: false)
        controller.updateNativeVLCPlaybackTime(42.25)
        controller.stop()

        await fulfillment(of: [stoppedExpectation], timeout: 1.0)
        let stopped = await apiClient.stoppedUpdates
        let saved = await repository.savedProgress

        XCTAssertEqual(stopped.first?.positionTicks, 422_500_000)
        XCTAssertEqual(saved.first?.positionTicks, 422_500_000)
    }
}

private final class NativeSessionRoutingAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    private let configuration: ServerConfiguration
    private let source: MediaSource
    private let stoppedExpectation: XCTestExpectation?
    private(set) var lastPlaybackInfoOptions: PlaybackInfoOptions?
    private let lock = NSLock()
    private var _stoppedUpdates: [PlaybackProgressUpdate] = []

    init(configuration: ServerConfiguration, source: MediaSource, stoppedExpectation: XCTestExpectation? = nil) {
        self.configuration = configuration
        self.source = source
        self.stoppedExpectation = stoppedExpectation
    }

    var stoppedUpdates: [PlaybackProgressUpdate] {
        get async {
            lock.lock()
            defer { lock.unlock() }
            return _stoppedUpdates
        }
    }

    func currentConfiguration() async -> ServerConfiguration? { configuration }
    func currentSession() async -> UserSession? { UserSession(userID: "user", username: "user", token: "secret") }
    func configure(server: ServerConfiguration) async throws {}
    func testConnection(serverURL: URL) async throws {}
    func authenticate(credentials: UserCredentials) async throws -> UserSession { throw AppError.unknown }
    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { nil }
    func fetchUserViews() async throws -> [LibraryView] { [] }
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed { .empty }
    func fetchItem(id: String) async throws -> MediaItem { MediaItem(id: id, name: id) }
    func fetchItemDetail(id: String) async throws -> MediaDetail { MediaDetail(item: MediaItem(id: id, name: id)) }
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { [] }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? { nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { [] }
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] { [source] }
    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] {
        lastPlaybackInfoOptions = options
        return [source]
    }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? { nil }
    func reportPlayback(progress: PlaybackProgressUpdate) async throws {}
    func reportPlaybackStopped(progress: PlaybackProgressUpdate) async throws {
        lock.lock()
        _stoppedUpdates.append(progress)
        lock.unlock()
        stoppedExpectation?.fulfill()
    }
    func reportPlayed(itemID: String) async throws {}
}

private actor NativeSessionRoutingRepository: MetadataRepositoryProtocol {
    private(set) var savedProgress: [PlaybackProgress] = []

    func saveLibraryViews(_ views: [LibraryView]) async throws {}
    func fetchLibraryViews() async throws -> [LibraryView] { [] }
    func saveHomeFeed(_ feed: HomeFeed) async throws {}
    func fetchHomeFeed() async throws -> HomeFeed { .empty }
    func upsertItems(_ items: [MediaItem]) async throws {}
    func fetchItem(id: String) async throws -> MediaItem? { nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { [] }
    func searchItems(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func savePlaybackProgress(_ progress: PlaybackProgress) async throws {
        savedProgress.append(progress)
    }
    func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? { nil }
    func fetchLastSyncDate() async throws -> Date? { nil }
    func setLastSyncDate(_ date: Date) async throws {}
}
