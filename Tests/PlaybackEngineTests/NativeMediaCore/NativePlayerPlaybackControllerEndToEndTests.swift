@testable import PlaybackEngine
import Shared
import XCTest

final class NativePlayerPlaybackControllerEndToEndTests: XCTestCase {
    func testPrepareRoutesOriginalMP4ToAppleNativePlaybackWithoutTranscodeURL() async throws {
        let itemID = "item-1"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let streamURL = root.appendingPathComponent("Videos").appendingPathComponent(itemID).appendingPathComponent("stream.mp4")
        try FileManager.default.createDirectory(at: streamURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await MP4PlaybackFixture.makeTinyH264AACMP4(at: streamURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let nativeConfig = NativePlayerConfig(enabled: true)
        let configuration = ServerConfiguration(serverURL: root, nativePlayerConfig: nativeConfig)
        let apiClient = NativePlaybackControllerAPIClient(source: MediaSource(
            id: "source-1",
            itemID: itemID,
            name: "Original",
            fileSize: Int64((try? Data(contentsOf: streamURL).count) ?? 0),
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            transcodeURL: URL(string: "https://jellyfin.example/videos/item/master.m3u8?VideoCodec=h264")
        ))
        let controller = NativePlayerPlaybackController(apiClient: apiClient)

        let snapshot = try await controller.prepare(
            itemID: itemID,
            configuration: configuration,
            session: UserSession(userID: "user", username: "user", token: "secret"),
            nativeConfig: nativeConfig,
            startTimeTicks: 1_500_000
        )

        XCTAssertEqual(snapshot.surface, .appleNative)
        XCTAssertNil(snapshot.playbackURL)
        XCTAssertEqual(snapshot.applePlaybackSelection?.assetURL.path, streamURL.path)
        XCTAssertNil(snapshot.nativeBridgePlan)
        XCTAssertEqual(try XCTUnwrap(snapshot.startTimeSeconds), 0.15, accuracy: 0.001)
        XCTAssertTrue(snapshot.overlayLines.contains("originalMediaRequested=true"))
        XCTAssertTrue(snapshot.overlayLines.contains("serverTranscodeUsed=false"))
        XCTAssertTrue(snapshot.overlayLines.contains("nativeProbe=false"))
        XCTAssertTrue(snapshot.overlayLines.contains("renderer=AVPlayerViewController"))
        XCTAssertFalse(snapshot.overlayLines.joined().contains("byteSource=HTTPRangeByteSource"))
        XCTAssertFalse(snapshot.overlayLines.joined().contains("MP4Demuxer"))
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.allowTranscoding, false)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.enableDirectStream, false)
    }

    func testCompatibleCommaSeparatedMOVSourceUsesAppleNativeWithoutProbe() {
        let source = MediaSource(
            id: "source-dv",
            itemID: "item-dv",
            name: "Dolby Vision Original",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hvc1",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        XCTAssertTrue(NativePlayerPlaybackController.shouldUseAppleNativeSurface(
            source: source,
            url: URL(string: "https://example.com/Videos/item-dv/stream?static=true")!
        ))
    }

    func testPrepareRoutesDolbyVisionMOVToAppleNativePlaybackWithoutProbe() async throws {
        let itemID = "item-dv"
        let nativeConfig = NativePlayerConfig(enabled: true)
        let configuration = ServerConfiguration(
            serverURL: URL(string: "https://jellyfin.example")!,
            nativePlayerConfig: nativeConfig
        )
        let apiClient = NativePlaybackControllerAPIClient(source: MediaSource(
            id: "source-dv",
            itemID: itemID,
            name: "Dolby Vision Original",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hvc1",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            transcodeURL: URL(string: "https://jellyfin.example/videos/item/master.m3u8?VideoCodec=h264")
        ))
        let controller = NativePlayerPlaybackController(apiClient: apiClient)

        let snapshot = try await controller.prepare(
            itemID: itemID,
            configuration: configuration,
            session: UserSession(userID: "user", username: "user", token: "secret"),
            nativeConfig: nativeConfig,
            startTimeTicks: 12_000_000_000
        )

        XCTAssertEqual(snapshot.surface, .appleNative)
        XCTAssertEqual(snapshot.routeDescription, "Direct Play (Apple Native)")
        XCTAssertEqual(snapshot.applePlaybackSelection?.debugInfo.playMethod, "DirectPlay")
        XCTAssertNil(snapshot.playbackURL)
        XCTAssertNil(snapshot.nativeBridgePlan)
        XCTAssertEqual(try XCTUnwrap(snapshot.startTimeSeconds), 1200, accuracy: 0.001)
        XCTAssertTrue(snapshot.overlayLines.contains("originalMediaRequested=true"))
        XCTAssertTrue(snapshot.overlayLines.contains("serverTranscodeUsed=false"))
        XCTAssertTrue(snapshot.overlayLines.contains("nativeProbe=false"))
        XCTAssertTrue(snapshot.overlayLines.contains("renderer=AVPlayerViewController"))
        XCTAssertFalse(snapshot.overlayLines.joined().contains("HTTPRangeByteSource"))
        XCTAssertFalse(snapshot.overlayLines.joined().contains("MP4Demuxer"))
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.allowTranscoding, false)
    }

    func testMatroskaSourceDoesNotUseAppleNativeByMetadataOnly() {
        let source = MediaSource(
            id: "source-mkv",
            itemID: "item-mkv",
            name: "Matroska Original",
            container: "mkv",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        XCTAssertFalse(NativePlayerPlaybackController.shouldUseAppleNativeSurface(
            source: source,
            url: URL(string: "https://example.com/Videos/item-mkv/stream?static=true")!
        ))
    }

    func testPrepareRoutesOriginalMatroskaToNativePlaybackWithoutTranscodeURL() async throws {
        let itemID = "item-mkv"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let streamURL = root.appendingPathComponent("Videos").appendingPathComponent(itemID).appendingPathComponent("stream")
        try FileManager.default.createDirectory(at: streamURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeTinyMatroskaH264AAC().write(to: streamURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let nativeConfig = NativePlayerConfig(enabled: true)
        let configuration = ServerConfiguration(serverURL: root, nativePlayerConfig: nativeConfig)
        let apiClient = NativePlaybackControllerAPIClient(source: MediaSource(
            id: "source-mkv",
            itemID: itemID,
            name: "Original MKV",
            fileSize: Int64((try? Data(contentsOf: streamURL).count) ?? 0),
            container: "mkv",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            transcodeURL: URL(string: "https://jellyfin.example/videos/item/master.m3u8?VideoCodec=h264")
        ))
        let controller = NativePlayerPlaybackController(apiClient: apiClient)

        let snapshot = try await controller.prepare(
            itemID: itemID,
            configuration: configuration,
            session: UserSession(userID: "user", username: "user", token: "secret"),
            nativeConfig: nativeConfig,
            startTimeTicks: nil
        )

        XCTAssertEqual(snapshot.surface, .sampleBuffer)
        XCTAssertEqual(snapshot.playbackURL?.path, streamURL.path)
        XCTAssertNil(snapshot.applePlaybackSelection)
        XCTAssertNil(snapshot.nativeBridgePlan)
        XCTAssertNil(NativePlayerRouteGuard.firstViolationDescription(for: NativePlayerRouteProof(selectedURL: snapshot.playbackURL)))
        XCTAssertTrue(snapshot.overlayLines.contains("serverTranscodeUsed=false"))
        XCTAssertTrue(snapshot.overlayLines.contains { $0.contains("container=matroska") })
        XCTAssertTrue(snapshot.overlayLines.contains { $0.contains("demuxer=MatroskaDemuxer(EBML)") })
        XCTAssertTrue(snapshot.overlayLines.contains { $0.contains("renderer=AVSampleBufferDisplayLayer") })
        XCTAssertTrue(snapshot.overlayLines.contains { $0.contains("audioRenderer=AVSampleBufferAudioRenderer") })
        XCTAssertFalse(snapshot.overlayLines.joined().contains("AVPlayerViewController"))
        XCTAssertFalse(snapshot.overlayLines.joined().contains("LocalFMP4HLS"))
        XCTAssertGreaterThan(snapshot.overlayLines.videoPacketCount, 0)
        XCTAssertGreaterThan(snapshot.overlayLines.audioPacketCount, 0)
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.allowTranscoding, false)
    }

    func testPrepareRoutesMatroskaUnsupportedAudioToCustomNativePath() async throws {
        let itemID = "item-mkv-truehd"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let streamURL = root.appendingPathComponent("Videos").appendingPathComponent(itemID).appendingPathComponent("stream")
        try FileManager.default.createDirectory(at: streamURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeTinyMatroskaH264(audioCodecID: "A_TRUEHD").write(to: streamURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let nativeConfig = NativePlayerConfig(enabled: true)
        let configuration = ServerConfiguration(serverURL: root, nativePlayerConfig: nativeConfig)
        let apiClient = NativePlaybackControllerAPIClient(source: MediaSource(
            id: "source-mkv-truehd",
            itemID: itemID,
            name: "Original MKV TrueHD",
            fileSize: Int64((try? Data(contentsOf: streamURL).count) ?? 0),
            container: "mkv",
            videoCodec: "h264",
            audioCodec: "truehd",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            transcodeURL: URL(string: "https://jellyfin.example/videos/item/master.m3u8?AudioCodec=aac")
        ))
        let controller = NativePlayerPlaybackController(apiClient: apiClient)

        let snapshot = try await controller.prepare(
            itemID: itemID,
            configuration: configuration,
            session: UserSession(userID: "user", username: "user", token: "secret"),
            nativeConfig: nativeConfig,
            startTimeTicks: nil
        )

        XCTAssertEqual(snapshot.surface, .sampleBuffer)
        XCTAssertNil(snapshot.applePlaybackSelection)
        XCTAssertNil(snapshot.nativeBridgePlan)
        XCTAssertTrue(snapshot.overlayLines.contains("serverTranscodeUsed=false"))
        XCTAssertTrue(snapshot.overlayLines.contains { $0.contains("audio=truehd decoder=software-module-planned") })
        XCTAssertFalse(snapshot.overlayLines.joined().contains("AVPlayerViewController"))
        XCTAssertEqual(apiClient.lastPlaybackInfoOptions?.allowTranscoding, false)
    }

    private func makeTinyMatroskaH264AAC() -> Data {
        makeTinyMatroskaH264(audioCodecID: "A_AAC")
    }

    private func makeTinyMatroskaH264(audioCodecID: String) -> Data {
        let videoTrack = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x01]) +
            element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8))
        )
        let audioTrack = element([0xAE], payload:
            element([0xD7], payload: [0x02]) +
            element([0x83], payload: [0x02]) +
            element([0x86], payload: Array(audioCodecID.utf8)) +
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

private final class NativePlaybackControllerAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    let source: MediaSource
    private(set) var lastPlaybackInfoOptions: PlaybackInfoOptions?

    init(source: MediaSource) {
        self.source = source
    }

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
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] { [source] }
    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] {
        lastPlaybackInfoOptions = options
        return [source]
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

private extension [String] {
    var videoPacketCount: Int {
        packetCount(prefix: "packets video=")
    }

    var audioPacketCount: Int {
        packetCount(prefix: "packets video=", field: "audio=")
    }

    func packetCount(prefix: String, field: String = "video=") -> Int {
        guard let line = first(where: { $0.hasPrefix(prefix) }) else { return 0 }
        return line.split(separator: " ")
            .first { $0.hasPrefix(field) }
            .flatMap { Int(String($0).replacingOccurrences(of: field, with: "")) } ?? 0
    }
}
