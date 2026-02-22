import PlaybackEngine
import Shared
import XCTest

final class PlaybackDecisionEngineTests: XCTestCase {
    private let server = ServerConfiguration(serverURL: URL(string: "https://example.com")!)

    func testDirectPlayPreferredWhenCompatible() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "direct",
                itemID: "item",
                name: "Direct",
                container: "mp4",
                videoCodec: "h264",
                audioCodec: "aac",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/direct-stream.mp4"),
                directPlayURL: URL(string: "https://example.com/direct-play.mp4"),
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "direct")
        XCTAssertEqual(decision?.route, .directPlay(URL(string: "https://example.com/direct-play.mp4")!))
    }

    func testRemuxUsedWhenDirectPlayNotCompatible() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "remux",
                itemID: "item",
                name: "Remux",
                container: "mkv",
                videoCodec: "hevc",
                audioCodec: "aac",
                supportsDirectPlay: false,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/remux/master.m3u8"),
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "remux")
        XCTAssertEqual(decision?.route, .remux(URL(string: "https://example.com/remux/master.m3u8")!))
    }

    func testTranscodeFallbackWhenNoDirectOptions() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "transcode",
                itemID: "item",
                name: "Transcode",
                container: "avi",
                videoCodec: "mpeg2",
                audioCodec: "dts",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "transcode")
        XCTAssertEqual(decision?.route, .transcode(URL(string: "https://example.com/transcode.m3u8")!))
    }

    func testPerformanceModeCanRejectWhenOnlyTranscodeAvailable() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "transcode-only",
                itemID: "item",
                name: "Only Transcode",
                container: "mkv",
                videoCodec: "hevc",
                audioCodec: "dts",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(
            itemID: "item",
            sources: sources,
            configuration: server,
            token: "abc",
            allowTranscoding: false
        )

        XCTAssertNil(decision)
    }

    func testDolbyVisionDirectPlayWinsOverH264() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "h264",
                itemID: "item",
                name: "h264",
                container: "mp4",
                videoCodec: "h264",
                audioCodec: "aac",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/h264.mp4"),
                directPlayURL: URL(string: "https://example.com/h264.mp4"),
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            ),
            MediaSource(
                id: "dv",
                itemID: "item",
                name: "dv",
                container: "mp4",
                videoCodec: "dvh1",
                audioCodec: "eac3",
                videoBitDepth: 10,
                videoRange: "DolbyVision",
                audioChannelLayout: "7.1 Atmos",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/dv.mp4"),
                directPlayURL: URL(string: "https://example.com/dv.mp4"),
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "dv")
        XCTAssertEqual(decision?.route, .directPlay(URL(string: "https://example.com/dv.mp4")!))
    }

    func testFallbackTranscodeURLKeepsVideoCopyAndAudioAAC() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "fallback-hevc",
                itemID: "item",
                name: "fallback",
                container: "mkv",
                videoCodec: "hevc",
                audioCodec: "eac3",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: nil
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        guard case let .transcode(url) = decision?.route else {
            XCTFail("Expected transcode route")
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryMap: [String: String] = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        XCTAssertEqual(queryMap["VideoCodec"], "hevc")
        XCTAssertEqual(queryMap["AudioCodec"], "aac")
        XCTAssertEqual(queryMap["AllowVideoStreamCopy"], "true")
        XCTAssertEqual(queryMap["AllowAudioStreamCopy"], "false")
        XCTAssertEqual(queryMap["Container"], "fmp4")
        XCTAssertEqual(queryMap["SegmentContainer"], "fmp4")
    }

    func testCoordinatorConservativeProfileKeepsVideoCopy() async throws {
        let source = MediaSource(
            id: "source-1",
            itemID: "item-1",
            name: "HEVC source",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/Videos/item-1/master.m3u8?MediaSourceId=source-1&VideoCodec=hevc")
        )
        let client = MockPlaybackAPIClient(configuration: server, sources: ["item-1": [source]])
        let coordinator = PlaybackCoordinator(apiClient: client)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-1",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .conservativeCompatibility
        )

        guard case .transcode = selection.decision.route else {
            XCTFail("Expected transcode route")
            return
        }

        let queryMap = queryMap(from: selection.assetURL)
        XCTAssertEqual(queryMap["VideoCodec"], "hevc")
        XCTAssertEqual(queryMap["AllowVideoStreamCopy"], "true")
        XCTAssertEqual(queryMap["AudioCodec"], "aac")
        XCTAssertEqual(queryMap["AllowAudioStreamCopy"], "false")
        XCTAssertEqual(queryMap["Container"], "fmp4")
        XCTAssertEqual(queryMap["SegmentContainer"], "fmp4")
    }

    func testCoordinatorAppleOptimizedProfileForcesHEVCTranscode() async throws {
        let source = MediaSource(
            id: "source-apple-hevc",
            itemID: "item-apple-hevc",
            name: "HEVC source",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/Videos/item-apple-hevc/master.m3u8?MediaSourceId=source-apple-hevc&VideoCodec=hevc")
        )
        let client = MockPlaybackAPIClient(configuration: server, sources: ["item-apple-hevc": [source]])
        let coordinator = PlaybackCoordinator(apiClient: client)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-apple-hevc",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .appleOptimizedHEVC
        )

        guard case .transcode = selection.decision.route else {
            XCTFail("Expected transcode route")
            return
        }

        let queryMap = queryMap(from: selection.assetURL)
        XCTAssertEqual(queryMap["VideoCodec"], "hevc")
        XCTAssertEqual(queryMap["AllowVideoStreamCopy"], "false")
        XCTAssertEqual(queryMap["AudioCodec"], "aac")
        XCTAssertEqual(queryMap["AllowAudioStreamCopy"], "false")
        XCTAssertEqual(queryMap["Container"], "fmp4")
        XCTAssertEqual(queryMap["SegmentContainer"], "fmp4")
    }

    func testCoordinatorServerDefaultAutoUpgradesRiskyHEVCStreamCopy() async throws {
        let source = MediaSource(
            id: "source-server-default-hevc",
            itemID: "item-server-default-hevc",
            name: "HEVC source",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/Videos/item-server-default-hevc/master.m3u8?MediaSourceId=source-server-default-hevc&VideoCodec=hevc&AllowVideoStreamCopy=true&AllowAudioStreamCopy=false&Container=fmp4&SegmentContainer=fmp4")
        )
        let client = MockPlaybackAPIClient(configuration: server, sources: ["item-server-default-hevc": [source]])
        let coordinator = PlaybackCoordinator(apiClient: client)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-server-default-hevc",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .serverDefault
        )

        guard case .transcode = selection.decision.route else {
            XCTFail("Expected transcode route")
            return
        }

        let queryMap = queryMap(from: selection.assetURL)
        XCTAssertEqual(queryMap["VideoCodec"], "hevc")
        XCTAssertEqual(queryMap["AllowVideoStreamCopy"], "false")
        XCTAssertEqual(queryMap["AudioCodec"], "aac")
        XCTAssertEqual(queryMap["AllowAudioStreamCopy"], "false")
        XCTAssertEqual(queryMap["Container"], "fmp4")
        XCTAssertEqual(queryMap["SegmentContainer"], "fmp4")
    }

    func testCoordinatorForceH264ProfileDisablesVideoCopy() async throws {
        let source = MediaSource(
            id: "source-2",
            itemID: "item-2",
            name: "HEVC source",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/Videos/item-2/master.m3u8?MediaSourceId=source-2&VideoCodec=hevc")
        )
        let client = MockPlaybackAPIClient(configuration: server, sources: ["item-2": [source]])
        let coordinator = PlaybackCoordinator(apiClient: client)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-2",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .forceH264Transcode
        )

        guard case .transcode = selection.decision.route else {
            XCTFail("Expected transcode route")
            return
        }

        let queryMap = queryMap(from: selection.assetURL)
        XCTAssertEqual(queryMap["VideoCodec"], "h264")
        XCTAssertEqual(queryMap["AllowVideoStreamCopy"], "false")
        XCTAssertEqual(queryMap["AudioCodec"], "aac")
        XCTAssertEqual(queryMap["AllowAudioStreamCopy"], "false")
        XCTAssertEqual(queryMap["Container"], "ts")
        XCTAssertEqual(queryMap["SegmentContainer"], "ts")
    }

    func testCoordinatorForceH264ProfileStripsHEVCConstraintsAndDeduplicatesKeys() async throws {
        let source = MediaSource(
            id: "source-3",
            itemID: "item-3",
            name: "HEVC source with stale params",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(
                string: "https://example.com/Videos/item-3/master.m3u8?MediaSourceId=source-3&VideoCodec=hevc&AllowVideoStreamCopy=true&allowVideoStreamCopy=true&AllowAudioStreamCopy=false&hevc-level=150&hevc-profile=main10&hevc-videobitdepth=10&AudioCodec=aac,ac3"
            )
        )
        let client = MockPlaybackAPIClient(configuration: server, sources: ["item-3": [source]])
        let coordinator = PlaybackCoordinator(apiClient: client)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-3",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .forceH264Transcode
        )

        guard case .transcode = selection.decision.route else {
            XCTFail("Expected transcode route")
            return
        }

        let lowerMap = lowercasedQueryMap(from: selection.assetURL)
        let names = queryNames(from: selection.assetURL)

        XCTAssertEqual(lowerMap["videocodec"], "h264")
        XCTAssertEqual(lowerMap["allowvideostreamcopy"], "false")
        XCTAssertEqual(lowerMap["allowaudiostreamcopy"], "false")
        XCTAssertEqual(lowerMap["audiocodec"], "aac")
        XCTAssertEqual(lowerMap["requireavc"], "true")
        XCTAssertNil(lowerMap["hevc-level"])
        XCTAssertNil(lowerMap["hevc-profile"])
        XCTAssertNil(lowerMap["hevc-videobitdepth"])
        XCTAssertEqual(names.filter { $0 == "allowvideostreamcopy" }.count, 1)
    }

    private func queryMap(from url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
    }

    private func lowercasedQueryMap(from url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name.lowercased(), value.lowercased())
        })
    }

    private func queryNames(from url: URL) -> [String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return (components?.queryItems ?? []).map { $0.name.lowercased() }
    }
}

private final class MockPlaybackAPIClient: JellyfinAPIClientProtocol {
    private let configuration: ServerConfiguration
    private let session: UserSession
    private let sources: [String: [MediaSource]]

    init(configuration: ServerConfiguration, sources: [String: [MediaSource]]) {
        self.configuration = configuration
        self.sources = sources
        self.session = UserSession(userID: "user-1", username: "Flo", token: "token-1")
    }

    func currentConfiguration() async -> ServerConfiguration? {
        configuration
    }

    func currentSession() async -> UserSession? {
        session
    }

    func configure(server: ServerConfiguration) async throws {
        _ = server
    }

    func testConnection(serverURL: URL) async throws {
        _ = serverURL
    }

    func authenticate(credentials: UserCredentials) async throws -> UserSession {
        _ = credentials
        return session
    }

    func signOut() async {}

    func fetchUserViews() async throws -> [Shared.LibraryView] {
        []
    }

    func fetchHomeFeed(since: Date?) async throws -> HomeFeed {
        _ = since
        return .empty
    }

    func fetchItemDetail(id: String) async throws -> MediaDetail {
        _ = id
        throw AppError.network("Not implemented for tests.")
    }

    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        _ = query
        return []
    }

    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] {
        sources[itemID] ?? []
    }

    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] {
        _ = options
        return try await fetchPlaybackSources(itemID: itemID)
    }

    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? {
        _ = itemID
        _ = type
        _ = width
        _ = quality
        return nil
    }

    func reportPlayback(progress: PlaybackProgressUpdate) async throws {
        _ = progress
    }

    func reportPlayed(itemID: String) async throws {
        _ = itemID
    }

    func fetchItem(id: String) async throws -> MediaItem {
        throw AppError.network("Not implemented for tests.")
    }

    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { [] }
}
