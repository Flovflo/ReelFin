@testable import PlaybackEngine
import Shared
import XCTest

final class NativePlayerRouteGuardTests: XCTestCase {
    func testAllowsStaticOriginalStreamURL() throws {
        let url = try XCTUnwrap(URL(string: "https://jellyfin.example/Videos/item/stream?static=true&MediaSourceId=source&api_key=secret"))

        let violations = NativePlayerRouteGuard.validateOriginalPlaybackURL(url)

        XCTAssertTrue(violations.isEmpty)
    }

    func testBlocksJellyfinHLSPlaylistURLs() throws {
        let master = try XCTUnwrap(URL(string: "https://jellyfin.example/videos/item/master.m3u8"))
        let main = try XCTUnwrap(URL(string: "https://jellyfin.example/videos/item/main.m3u8"))

        XCTAssertEqual(
            NativePlayerRouteGuard.validateOriginalPlaybackURL(master),
            [.hlsPlaylistURL("/videos/item/master.m3u8")]
        )
        XCTAssertEqual(
            NativePlayerRouteGuard.validateOriginalPlaybackURL(main),
            [.hlsPlaylistURL("/videos/item/main.m3u8")]
        )
    }

    func testBlocksLoopbackLocalHLSInStrictNativeMode() throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:49152/master.m3u8"))

        let violations = NativePlayerRouteGuard.validateOriginalPlaybackURL(url)

        XCTAssertEqual(violations, [.hlsPlaylistURL("/master.m3u8")])
    }

    func testBlocksAllKnownJellyfinTranscodeQueryItems() throws {
        let url = try XCTUnwrap(URL(string: "https://jellyfin.example/videos/item/main.m3u8?VideoCodec=h264&AudioCodec=aac&TranscodeReasons=ContainerNotSupported&AllowVideoStreamCopy=false&AllowAudioStreamCopy=false&RequireAvc=true"))

        let violations = NativePlayerRouteGuard.validateOriginalPlaybackURL(url)

        XCTAssertTrue(violations.contains(.hlsPlaylistURL("/videos/item/main.m3u8")))
        XCTAssertTrue(violations.contains(.forbiddenTranscodeQueryItem(name: "VideoCodec", value: "h264")))
        XCTAssertTrue(violations.contains(.forbiddenTranscodeQueryItem(name: "AudioCodec", value: "aac")))
        XCTAssertTrue(violations.contains(.forbiddenTranscodeQueryItem(name: "TranscodeReasons", value: "ContainerNotSupported")))
        XCTAssertTrue(violations.contains(.forbiddenTranscodeQueryItem(name: "AllowVideoStreamCopy", value: "false")))
        XCTAssertTrue(violations.contains(.forbiddenTranscodeQueryItem(name: "AllowAudioStreamCopy", value: "false")))
        XCTAssertTrue(violations.contains(.forbiddenTranscodeQueryItem(name: "RequireAvc", value: "true")))
    }

    func testBlocksCodecListsThatContainForcedH264OrAAC() throws {
        let url = try XCTUnwrap(URL(string: "https://jellyfin.example/Videos/item/stream?static=true&VideoCodec=hevc,h264&AudioCodec=eac3,aac"))

        let violations = NativePlayerRouteGuard.validateOriginalPlaybackURL(url)

        XCTAssertTrue(violations.contains(.forbiddenTranscodeQueryItem(name: "VideoCodec", value: "hevc,h264")))
        XCTAssertTrue(violations.contains(.forbiddenTranscodeQueryItem(name: "AudioCodec", value: "eac3,aac")))
    }

    func testBlocksLegacyPlaybackSurfacesForNativeRoute() throws {
        let proof = NativePlayerRouteProof(
            usedLegacyPlaybackCoordinator: true,
            createdAVPlayerItem: true,
            usedAVPlayerViewController: true,
            transcodeProfile: "forceH264Transcode",
            selectedURL: URL(string: "https://jellyfin.example/videos/item/master.m3u8?VideoCodec=h264")
        )

        let violations = NativePlayerRouteGuard.validate(proof)

        XCTAssertTrue(violations.contains(.legacyPlaybackCoordinator))
        XCTAssertTrue(violations.contains(.avPlayerItemCreation))
        XCTAssertTrue(violations.contains(.avPlayerViewControllerSurface))
        XCTAssertTrue(violations.contains(.forceH264TranscodeProfile))
        XCTAssertTrue(violations.contains(.hlsPlaylistURL("/videos/item/master.m3u8")))
        XCTAssertTrue(violations.contains(.forbiddenTranscodeQueryItem(name: "VideoCodec", value: "h264")))
    }

    func testServerTranscodeBlockedReasonIsExplicit() {
        XCTAssertEqual(
            NativePlayerRouteViolation.serverTranscodeBlockedByConfig.localizedDescription,
            "Native engine mode blocks Jellyfin server transcode because allowServerTranscodeFallback=false."
        )
    }

    func testRuntimeOverrideForcesOriginalOnlyNativeMode() {
        let config = NativePlayerConfig(
            enabled: false,
            alwaysRequestOriginalFile: false,
            allowServerTranscodeFallback: true
        )

        let overridden = config.applyingRuntimeOverride(environment: ["REELFIN_NATIVE_PLAYER": "1"])

        XCTAssertTrue(overridden.enabled)
        XCTAssertTrue(overridden.alwaysRequestOriginalFile)
        XCTAssertFalse(overridden.allowServerTranscodeFallback)
    }

    func testWarmupResolvesOriginalDirectPlayWhenNativeModeEnabled() async throws {
        let apiClient = NativeWarmupGuardAPIClient(
            configuration: ServerConfiguration(
                serverURL: URL(string: "https://jellyfin.example")!,
                nativePlayerConfig: NativePlayerConfig(enabled: true)
            )
        )
        let warmup = PlaybackWarmupManager(apiClient: apiClient, ttl: 60)

        await warmup.warm(itemID: "item-1")
        let warmedSelection = await warmup.selection(for: "item-1")
        let selection = try XCTUnwrap(warmedSelection)
        let url = selection.assetURL
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        XCTAssertEqual(apiClient.fetchPlaybackSourcesCallCount, 1)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.mode, .performance)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.enableDirectPlay, true)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.enableDirectStream, false)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.allowTranscoding, false)
        XCTAssertEqual(url.path, "/Videos/item-1/stream.mp4")
        XCTAssertEqual(queryItems.first { $0.name == "static" }?.value, "true")
        XCTAssertEqual(queryItems.first { $0.name == "MediaSourceId" }?.value, "source-1")
        XCTAssertEqual(queryItems.first { $0.name == "api_key" }?.value, "secret")
        XCTAssertTrue(NativePlayerRouteGuard.validateOriginalPlaybackURL(url).isEmpty)
    }

    func testPlaybackCoordinatorThrowsBeforeLegacyPlaybackInfoWhenNativeModeEnabled() async throws {
        let apiClient = NativeWarmupGuardAPIClient(
            configuration: ServerConfiguration(
                serverURL: URL(string: "https://jellyfin.example")!,
                nativePlayerConfig: NativePlayerConfig(enabled: true)
            )
        )
        let coordinator = PlaybackCoordinator(apiClient: apiClient)

        do {
            _ = try await coordinator.resolvePlayback(
                itemID: "item-1",
                transcodeProfile: .forceH264Transcode
            )
            XCTFail("Expected native route guard to block legacy PlaybackCoordinator.")
        } catch let violation as NativePlayerRouteViolation {
            XCTAssertEqual(violation, .legacyPlaybackCoordinator)
        }

        XCTAssertEqual(apiClient.fetchPlaybackSourcesCallCount, 0)
    }

    func testPlaybackCoordinatorAllowsExplicitNativeRecoveryFallback() async throws {
        let apiClient = NativeWarmupGuardAPIClient(
            configuration: ServerConfiguration(
                serverURL: URL(string: "https://jellyfin.example")!,
                nativePlayerConfig: NativePlayerConfig(enabled: true)
            )
        )
        let coordinator = PlaybackCoordinator(apiClient: apiClient)
        let startTimeTicks: Int64 = 12_340_000_000

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-1",
            mode: .balanced,
            transcodeProfile: .appleOptimizedHEVC,
            startTimeTicks: startTimeTicks,
            allowDirectRoutes: false,
            nativeEngineFallbackReason: StartupFailureReason.directPlayPostStartStall.rawValue
        )

        guard case .transcode = selection.decision.route else {
            return XCTFail("Expected explicit native recovery fallback to select a transcode route.")
        }
        XCTAssertEqual(apiClient.fetchPlaybackSourcesCallCount, 1)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.startTimeTicks, startTimeTicks)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.enableDirectPlay, false)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.enableDirectStream, false)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.allowTranscoding, true)
    }
}

private final class NativeWarmupGuardAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    private let configuration: ServerConfiguration
    private(set) var fetchPlaybackSourcesCallCount = 0
    private(set) var lastPlaybackInfoOptions: PlaybackInfoOptions?

    init(configuration: ServerConfiguration) {
        self.configuration = configuration
    }

    func currentConfiguration() async -> ServerConfiguration? { configuration }
    func currentSession() async -> UserSession? {
        UserSession(userID: "user", username: "user", token: "secret")
    }
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
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] {
        fetchPlaybackSourcesCallCount += 1
        return [
            MediaSource(
                id: "source-1",
                itemID: itemID,
                name: "Original",
                fileSize: 4_000_000_000,
                container: "mp4",
                videoCodec: "hevc",
                audioCodec: "eac3",
                bitrate: 22_000_000,
                videoBitDepth: 10,
                supportsDirectPlay: true,
                supportsDirectStream: true
            )
        ]
    }
    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] {
        lastPlaybackInfoOptions = options
        return try await fetchPlaybackSources(itemID: itemID)
    }
    func fetchTrickplayManifest(itemID: String, mediaSourceID: String?) async throws -> TrickplayManifest? { nil }
    func trickplayTileBaseURL(itemID: String, mediaSourceID: String?, width: Int) async -> URL? { nil }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? { nil }
    func reportPlayback(progress: PlaybackProgressUpdate) async throws {}
    func reportPlaybackStopped(progress: PlaybackProgressUpdate) async throws {}
    func reportPlayed(itemID: String) async throws {}
    func setPlayedState(itemID: String, isPlayed: Bool) async throws {}
    func setFavorite(itemID: String, isFavorite: Bool) async throws {}
}
