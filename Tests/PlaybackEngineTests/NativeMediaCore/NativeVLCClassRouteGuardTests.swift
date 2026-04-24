@testable import PlaybackEngine
import Shared
import XCTest

final class NativeVLCClassRouteGuardTests: XCTestCase {
    func testAllowsStaticOriginalStreamURL() throws {
        let url = try XCTUnwrap(URL(string: "https://jellyfin.example/Videos/item/stream?static=true&MediaSourceId=source&api_key=secret"))

        let violations = NativeVLCClassRouteGuard.validateOriginalPlaybackURL(url)

        XCTAssertTrue(violations.isEmpty)
    }

    func testBlocksJellyfinHLSPlaylistURLs() throws {
        let master = try XCTUnwrap(URL(string: "https://jellyfin.example/videos/item/master.m3u8"))
        let main = try XCTUnwrap(URL(string: "https://jellyfin.example/videos/item/main.m3u8"))

        XCTAssertEqual(
            NativeVLCClassRouteGuard.validateOriginalPlaybackURL(master),
            [.hlsPlaylistURL("/videos/item/master.m3u8")]
        )
        XCTAssertEqual(
            NativeVLCClassRouteGuard.validateOriginalPlaybackURL(main),
            [.hlsPlaylistURL("/videos/item/main.m3u8")]
        )
    }

    func testBlocksAllKnownJellyfinTranscodeQueryItems() throws {
        let url = try XCTUnwrap(URL(string: "https://jellyfin.example/videos/item/main.m3u8?VideoCodec=h264&AudioCodec=aac&TranscodeReasons=ContainerNotSupported&AllowVideoStreamCopy=false&AllowAudioStreamCopy=false&RequireAvc=true"))

        let violations = NativeVLCClassRouteGuard.validateOriginalPlaybackURL(url)

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

        let violations = NativeVLCClassRouteGuard.validateOriginalPlaybackURL(url)

        XCTAssertTrue(violations.contains(.forbiddenTranscodeQueryItem(name: "VideoCodec", value: "hevc,h264")))
        XCTAssertTrue(violations.contains(.forbiddenTranscodeQueryItem(name: "AudioCodec", value: "eac3,aac")))
    }

    func testBlocksLegacyPlaybackSurfacesForNativeRoute() throws {
        let proof = NativeVLCClassRouteProof(
            usedLegacyPlaybackCoordinator: true,
            createdAVPlayerItem: true,
            usedAVPlayerViewController: true,
            transcodeProfile: "forceH264Transcode",
            selectedURL: URL(string: "https://jellyfin.example/videos/item/master.m3u8?VideoCodec=h264")
        )

        let violations = NativeVLCClassRouteGuard.validate(proof)

        XCTAssertTrue(violations.contains(.legacyPlaybackCoordinator))
        XCTAssertTrue(violations.contains(.avPlayerItemCreation))
        XCTAssertTrue(violations.contains(.avPlayerViewControllerSurface))
        XCTAssertTrue(violations.contains(.forceH264TranscodeProfile))
        XCTAssertTrue(violations.contains(.hlsPlaylistURL("/videos/item/master.m3u8")))
        XCTAssertTrue(violations.contains(.forbiddenTranscodeQueryItem(name: "VideoCodec", value: "h264")))
    }

    func testServerTranscodeBlockedReasonIsExplicit() {
        XCTAssertEqual(
            NativeVLCClassRouteViolation.serverTranscodeBlockedByConfig.localizedDescription,
            "Native VLC-class mode blocks Jellyfin server transcode because allowServerTranscodeFallback=false."
        )
    }

    func testRuntimeOverrideForcesOriginalOnlyNativeMode() {
        let config = NativeVLCClassPlayerConfig(
            enabled: false,
            alwaysRequestOriginalFile: false,
            allowServerTranscodeFallback: true
        )

        let overridden = config.applyingRuntimeOverride(environment: ["REELFIN_NATIVE_VLC_CLASS_PLAYER": "1"])

        XCTAssertTrue(overridden.enabled)
        XCTAssertTrue(overridden.alwaysRequestOriginalFile)
        XCTAssertFalse(overridden.allowServerTranscodeFallback)
    }

    func testWarmupDoesNotResolveLegacyPlaybackWhenNativeModeEnabled() async {
        let apiClient = NativeWarmupGuardAPIClient(
            configuration: ServerConfiguration(
                serverURL: URL(string: "https://jellyfin.example")!,
                nativeVLCClassPlayerConfig: NativeVLCClassPlayerConfig(enabled: true)
            )
        )
        let warmup = PlaybackWarmupManager(apiClient: apiClient, ttl: 0)

        await warmup.warm(itemID: "item-1")

        XCTAssertEqual(apiClient.fetchPlaybackSourcesCallCount, 0)
    }

    func testPlaybackCoordinatorThrowsBeforeLegacyPlaybackInfoWhenNativeModeEnabled() async throws {
        let apiClient = NativeWarmupGuardAPIClient(
            configuration: ServerConfiguration(
                serverURL: URL(string: "https://jellyfin.example")!,
                nativeVLCClassPlayerConfig: NativeVLCClassPlayerConfig(enabled: true)
            )
        )
        let coordinator = PlaybackCoordinator(apiClient: apiClient)

        do {
            _ = try await coordinator.resolvePlayback(
                itemID: "item-1",
                transcodeProfile: .forceH264Transcode
            )
            XCTFail("Expected native route guard to block legacy PlaybackCoordinator.")
        } catch let violation as NativeVLCClassRouteViolation {
            XCTAssertEqual(violation, .legacyPlaybackCoordinator)
        }

        XCTAssertEqual(apiClient.fetchPlaybackSourcesCallCount, 0)
    }
}

private final class NativeWarmupGuardAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    private let configuration: ServerConfiguration
    private(set) var fetchPlaybackSourcesCallCount = 0

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
        return []
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
