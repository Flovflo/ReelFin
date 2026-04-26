@testable import PlaybackEngine
import Foundation
import Shared
import XCTest

@MainActor
final class NativePlayerSessionRoutingTests: XCTestCase {
    func testNativeModeMigrationClearsStoredForceH264ProfilePins() {
        let suiteName = "NativePlayerSessionRoutingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            ["item-1": TranscodeURLProfile.forceH264Transcode.rawValue],
            forKey: PlaybackSessionController.preferredProfileStorageKey
        )

        PlaybackSessionController.clearStoredPreferredTranscodeProfiles(defaults: defaults)

        XCTAssertNil(defaults.dictionary(forKey: PlaybackSessionController.preferredProfileStorageKey))
    }

    func testDebugRuntimeNativeModeUsesAppleNativePlayerForCompatibleMP4Original() async throws {
        let defaultsKey = NativePlayerRuntimeDefaults.enabledKey
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

        let config = NativePlayerConfig(enabled: false, allowServerTranscodeFallback: true)
        let apiClient = NativeSessionRoutingAPIClient(
            configuration: ServerConfiguration(serverURL: root, nativePlayerConfig: config),
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

        XCTAssertFalse(controller.isNativePlayerActive)
        XCTAssertNil(controller.nativePlayerPlaybackURL)
        XCTAssertNotNil(controller.player.currentItem)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.allowTranscoding, false)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.enableDirectStream, false)
        XCTAssertEqual(controller.routeDescription, "Direct Play")
    }

    func testNativeModeStopReportsNativePlaybackTime() async throws {
        let defaultsKey = NativePlayerRuntimeDefaults.enabledKey
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
        try makeTinyMatroskaH264AAC().write(to: streamURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let stoppedExpectation = expectation(description: "native stopped progress reported")
        let apiClient = NativeSessionRoutingAPIClient(
            configuration: ServerConfiguration(serverURL: root, nativePlayerConfig: NativePlayerConfig(enabled: true)),
            source: MediaSource(
                id: "source-progress",
                itemID: itemID,
                name: "Original",
                fileSize: Int64((try? FileManager.default.attributesOfItem(atPath: streamURL.path)[.size] as? NSNumber)?.intValue ?? 0),
                container: "mkv",
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
        controller.updateNativePlayerPlaybackTime(42.25)
        controller.stop()

        await fulfillment(of: [stoppedExpectation], timeout: 1.0)
        let stopped = await apiClient.stoppedUpdates
        let saved = await repository.savedProgress

        XCTAssertEqual(stopped.first?.positionTicks, 422_500_000)
        XCTAssertEqual(saved.first?.positionTicks, 422_500_000)
    }

    private func makeTinyMatroskaH264AAC() -> Data {
        let videoTrack = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x01]) +
            element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8))
        )
        let audioTrack = element([0xAE], payload:
            element([0xD7], payload: [0x02]) +
            element([0x83], payload: [0x02]) +
            element([0x86], payload: Array("A_AAC".utf8)) +
            element([0xE1], payload:
                element([0xB5], payload: doublePayload(48_000)) +
                element([0x9F], payload: [0x02])
            )
        )
        let tracks = element([0x16, 0x54, 0xAE, 0x6B], payload: videoTrack + audioTrack)
        let videoBlock = element([0xA3], payload: [0x81, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x02, 0x65, 0x88])
        let audioBlock = element([0xA3], payload: [0x82, 0x00, 0x00, 0x80, 0x21, 0x10, 0x04, 0x60])
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + videoBlock + audioBlock)
        return Data(element([0x1A, 0x45, 0xDF, 0xA3], payload: []))
            + Data(element([0x18, 0x53, 0x80, 0x67], payload: tracks + cluster))
    }

    private func element(_ id: [UInt8], payload: [UInt8]) -> [UInt8] {
        id + vintSize(payload.count) + payload
    }

    private func vintSize(_ size: Int) -> [UInt8] {
        precondition(size < 16_383)
        return size < 127
            ? [UInt8(0x80 | size)]
            : [UInt8(0x40 | ((size >> 8) & 0x3F)), UInt8(size & 0xFF)]
    }

    private func doublePayload(_ value: Double) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.bigEndian, Array.init)
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
