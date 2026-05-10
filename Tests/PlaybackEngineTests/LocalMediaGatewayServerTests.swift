import AVFoundation
import Foundation
import NativeMediaCore
import XCTest
@testable import PlaybackEngine

final class LocalMediaGatewayServerTests: XCTestCase {
    override func tearDown() async throws {
        MockOriginalMediaProtocol.reset()
        try await super.tearDown()
    }

    func testRangeMissFetchesRemoteThenSecondRangeHitUsesStore() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<32).map(UInt8.init))
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 128)
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["Authorization": "Bearer secret"],
            key: makeKey(),
            store: store,
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown") }

        let first = try await fetchRange(url: assetURL, range: "bytes=4-7")
        XCTAssertEqual(first.statusCode, 206)
        XCTAssertEqual(first.data, Data([4, 5, 6, 7]))
        XCTAssertEqual(first.response.value(forHTTPHeaderField: "Accept-Ranges"), "bytes")
        XCTAssertEqual(first.response.value(forHTTPHeaderField: "Content-Range"), "bytes 4-7/32")
        XCTAssertEqual(first.response.value(forHTTPHeaderField: "Content-Type"), "video/mp4")
        XCTAssertEqual(MockOriginalMediaProtocol.rangeRequestCount, 1)

        let second = try await fetchRange(url: assetURL, range: "bytes=4-7")
        XCTAssertEqual(second.statusCode, 206)
        XCTAssertEqual(second.data, Data([4, 5, 6, 7]))
        XCTAssertEqual(MockOriginalMediaProtocol.rangeRequestCount, 1)
    }

    func testOpenEndedRangeServesPartialResponseForAVPlayerStartup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<64).map(UInt8.init))
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 8, maxBytes: 256)
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: makeKey(),
            store: store,
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_open_ended") }

        let response = try await fetchRange(url: assetURL, range: "bytes=4-")

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.data, Data((4..<64).map(UInt8.init)))
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Range"), "bytes 4-63/64")
    }

    func testSuffixRangeServesTailBytes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<64).map(UInt8.init))
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: makeKey(),
            store: try MediaGatewayStore(directoryURL: directory),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_suffix") }

        let response = try await fetchRange(url: assetURL, range: "bytes=-4")

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.data, Data((60..<64).map(UInt8.init)))
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Range"), "bytes 60-63/64")
    }

    func testGatewayPreservesUpstreamContentType() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<32).map(UInt8.init))
        MockOriginalMediaProtocol.contentType = "video/x-matroska"
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mkv?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: makeKey(),
            store: try MediaGatewayStore(directoryURL: directory),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_content_type") }

        let head = try await fetchHead(url: assetURL)
        let response = try await fetchRange(url: assetURL, range: "bytes=0-3")

        XCTAssertEqual(head.response.value(forHTTPHeaderField: "Content-Type"), "video/x-matroska")
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Type"), "video/x-matroska")
    }

    func testInvalidRangeReturns416() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<16).map(UInt8.init))
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: makeKey(),
            store: try MediaGatewayStore(directoryURL: directory),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_invalid_range") }

        let response = try await fetchRange(url: assetURL, range: "bytes=99-120")

        XCTAssertEqual(response.statusCode, 416)
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Range"), "bytes */16")
    }

    func testMissingRangeServesInitialPartialResponseForAVPlayerProbe() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<64).map(UInt8.init))
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: makeKey(),
            store: try MediaGatewayStore(directoryURL: directory),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_missing_range") }

        let response = try await fetch(url: assetURL)

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.data, Data((0..<64).map(UInt8.init)))
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Range"), "bytes 0-63/64")
    }

    func testCachedRangeResolvesTotalLengthBeforeServingAVPlayerContentRange() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<64).map(UInt8.init))
        let key = makeKey()
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 8, maxBytes: 256)
        )
        try await store.write(range: ByteRange(offset: 0, length: 2), data: Data([0, 1]), key: key)
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: key,
            store: store,
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_cached_total") }

        let response = try await fetchRange(url: assetURL, range: "bytes=0-1")

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.data, Data([0, 1]))
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Range"), "bytes 0-1/64")
        XCTAssertEqual(MockOriginalMediaProtocol.rangeRequestCount, 0)
    }

    @MainActor
    func testGatewayURLCanReachReadyToPlayForGeneratedMP4() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureURL = directory.appendingPathComponent("fixture.mp4")
        try await MP4PlaybackFixture.makeTinyH264AACMP4(at: fixtureURL)
        MockOriginalMediaProtocol.storage = try Data(contentsOf: fixtureURL)
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: makeKey(),
            store: try MediaGatewayStore(directoryURL: directory),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_avplayer") }

        let asset = AVURLAsset(url: assetURL, options: [AVURLAssetOverrideMIMETypeKey: "video/mp4"])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.playImmediately(atRate: 1)
        defer { player.pause() }

        let didBecomeReady = await waitUntil(timeout: 5) {
            item.status != .unknown
        }

        XCTAssertTrue(didBecomeReady)
        XCTAssertEqual(item.status, .readyToPlay, item.error?.localizedDescription ?? "unknown AVPlayerItem error")
    }

    @MainActor
    func testLiveJellyfinGatewayServesRealRangeSniff() async throws {
        guard let target = try await makeLiveDirectPlayGatewayTarget() else {
            throw XCTSkip("Set ReelFin live Jellyfin env values to run the live Direct Play gateway AVPlayer test.")
        }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = LocalMediaGatewaySession(
            remoteURL: target.url,
            headers: target.headers,
            key: makeKey(routeURL: target.url, routeHeaders: target.headers),
            store: try MediaGatewayStore(directoryURL: directory)
        )
        do {
            let upstreamSniff = try await session.response(for: .bounded(ByteRange(offset: 0, length: 2)))
            XCTAssertEqual(upstreamSniff.data.count, 2)
            XCTAssertEqual(upstreamSniff.range, ByteRange(offset: 0, length: 2))
        } catch {
            XCTFail("Live gateway upstream fetch failed for item \(target.itemID.prefix(8)): \(error)")
            return
        }
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_live_avplayer") }

        let head = try await fetchHead(url: assetURL)
        XCTAssertEqual(head.statusCode, 200)
        XCTAssertEqual(head.response.value(forHTTPHeaderField: "Accept-Ranges"), "bytes")
        let sniff = try await fetchRange(url: assetURL, range: "bytes=0-1")
        XCTAssertEqual(sniff.statusCode, 206)
        XCTAssertEqual(sniff.data.count, 2)
        XCTAssertEqual(sniff.response.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes 0-1/"), true)
    }

    @MainActor
    func testLiveJellyfinDirectRemoteAVPlayerFailsForLargeOriginal() async throws {
        guard let target = try await makeLiveDirectPlayGatewayTarget() else {
            throw XCTSkip("Set ReelFin live Jellyfin env values to run the live Direct Play remote AVPlayer test.")
        }
        let asset = AVURLAsset(url: target.url, options: [AVURLAssetOverrideMIMETypeKey: "video/mp4"])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.playImmediately(atRate: 1)
        defer { player.pause() }

        let didBecomeReady = await waitUntil(timeout: 20) {
            item.status != .unknown
        }

        XCTAssertTrue(didBecomeReady, "Live Direct Play remote AVPlayerItem stayed unknown for item \(target.itemID.prefix(8)).")
        XCTAssertEqual(item.status, .failed)
        let error = try XCTUnwrap(item.error as NSError?)
        XCTAssertEqual(error.domain, AVFoundationErrorDomain)
        XCTAssertEqual(error.code, AVError.serverIncorrectlyConfigured.rawValue)
    }

    func testExposedLocalURLDoesNotContainRemoteSecret() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["Authorization": "Bearer secret"],
            key: makeKey(),
            store: try MediaGatewayStore(directoryURL: directory),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_secret") }

        XCTAssertEqual(assetURL.host, "127.0.0.1")
        XCTAssertFalse(assetURL.absoluteString.contains("secret"))
        XCTAssertFalse(assetURL.absoluteString.contains("api_key"))
    }

    func testGatewayPrefetchesAheadWhenPolicyAllowsCaching() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<128).map(UInt8.init))
        let key = makeKey()
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 8, maxBytes: 512)
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["Authorization": "Bearer secret"],
            key: key,
            store: store,
            prefetchConfiguration: LocalMediaGatewayPrefetchConfiguration(
                mediaCacheMode: .automatic,
                isTVOS: true,
                routeKind: .directPlayOriginal,
                sourceBitrate: 8,
                runtimeSeconds: 128,
                isExpensiveNetwork: false,
                isConstrainedNetwork: false
            ),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_prefetch") }

        let first = try await fetchRange(url: assetURL, range: "bytes=0-7")
        XCTAssertEqual(first.data, Data((0..<8).map(UInt8.init)))

        let prefetchRange = ByteRange(offset: 8, length: 8)
        let didPrefetch = await waitUntil(timeout: 2) {
            (try? await store.read(range: prefetchRange, key: key)) != nil
        }
        XCTAssertTrue(didPrefetch)
        let prefetched = try await store.read(range: prefetchRange, key: key)
        XCTAssertEqual(prefetched, Data((8..<16).map(UInt8.init)))
    }

    func testTinySniffRangeDoesNotTriggerPrefetch() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<128).map(UInt8.init))
        let key = makeKey()
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 8, maxBytes: 512)
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: key,
            store: store,
            prefetchConfiguration: LocalMediaGatewayPrefetchConfiguration(
                mediaCacheMode: .automatic,
                isTVOS: true,
                routeKind: .directPlayOriginal,
                sourceBitrate: 8,
                runtimeSeconds: 128,
                isExpensiveNetwork: false,
                isConstrainedNetwork: false
            ),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_sniff") }

        let first = try await fetchRange(url: assetURL, range: "bytes=0-1")
        XCTAssertEqual(first.data, Data([0, 1]))

        let didPrefetch = await waitUntil(timeout: 0.5) {
            (try? await store.read(range: ByteRange(offset: 2, length: 8), key: key)) != nil
        }
        XCTAssertFalse(didPrefetch)
        XCTAssertEqual(MockOriginalMediaProtocol.rangeRequestCount, 1)
    }

    func testInternalGatewayRequestsStripQueryAPIKeyWhenHeaderAuthExists() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<32).map(UInt8.init))
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 128)
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?static=true&api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: makeKey(),
            store: store,
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_internal_auth") }

        _ = try await fetchRange(url: assetURL, range: "bytes=4-7")

        XCTAssertFalse(MockOriginalMediaProtocol.requestedURLs.isEmpty)
        XCTAssertTrue(
            MockOriginalMediaProtocol.requestedURLs.allSatisfy {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .contains { $0.name.caseInsensitiveCompare("api_key") == .orderedSame } != true
            }
        )
        XCTAssertTrue(MockOriginalMediaProtocol.requestedHeaders.contains { $0["X-Emby-Token"] == "secret" })
        XCTAssertTrue(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=4-7" })
    }

    private func fetchRange(url: URL, range: String) async throws -> (data: Data, response: HTTPURLResponse, statusCode: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(range, forHTTPHeaderField: "Range")
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (data, http, http.statusCode)
    }

    private func fetch(url: URL) async throws -> (data: Data, response: HTTPURLResponse, statusCode: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (data, http, http.statusCode)
    }

    private func fetchHead(url: URL) async throws -> (response: HTTPURLResponse, statusCode: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (http, http.statusCode)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalMediaGatewayServerTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeMockSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockOriginalMediaProtocol.self]
        return configuration
    }

    private func makeKey() -> MediaGatewayCacheKey {
        makeKey(
            routeURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            routeHeaders: ["Authorization": "Bearer secret"]
        )
    }

    private func makeKey(routeURL: URL, routeHeaders: [String: String]) -> MediaGatewayCacheKey {
        MediaGatewayCacheKey(
            scope: "original",
            userID: "user-1",
            serverID: "server-1",
            itemID: "item-1",
            sourceID: "source-1",
            routeURL: routeURL,
            routeHeaders: routeHeaders
        )
    }

    private struct LiveGatewayTarget {
        let itemID: String
        let url: URL
        let headers: [String: String]
    }

    private func makeLiveDirectPlayGatewayTarget() async throws -> LiveGatewayTarget? {
        var environment = ProcessInfo.processInfo.environment
        loadEnvFile().forEach { key, value in
            environment[key] = environment[key] ?? value
        }
        guard
            let serverURL = environment["REELFIN_TEST_SERVER_URL"] ?? environment["JELLYFIN_BASE_URL"],
            let username = environment["REELFIN_TEST_USERNAME"] ?? environment["JELLYFIN_USERNAME"],
            let password = environment["REELFIN_TEST_PASSWORD"] ?? environment["JELLYFIN_PASSWORD"],
            let itemID = environment["TEST_DIRECTPLAY_MP4_ITEM_ID"],
            !serverURL.isEmpty,
            !username.isEmpty,
            !password.isEmpty,
            !itemID.isEmpty,
            serverURL != "...",
            username != "...",
            password != "...",
            itemID != "..."
        else { return nil }

        let token = try await authenticate(serverURL: serverURL, username: username, password: password)
        let headers = PlaybackAuthenticationHeaders.jellyfin(token: token)
        let normalizedItemID = normalizedItemID(itemID)
        let url = try XCTUnwrap(
            URL(string: "\(serverURL.trimmedTrailingSlash)/Videos/\(normalizedItemID)/stream.mp4?static=true&MediaSourceId=\(normalizedItemID)&api_key=\(token)")
        )
        return LiveGatewayTarget(itemID: normalizedItemID, url: url, headers: headers)
    }

    private func authenticate(serverURL: String, username: String, password: String) async throws -> String {
        let url = try XCTUnwrap(URL(string: "\(serverURL.trimmedTrailingSlash)/Users/AuthenticateByName"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "MediaBrowser Client=\"ReelFin\", Device=\"PlayerE2E\", DeviceId=\"reelfin-player-e2e\", Version=\"1.0\"",
            forHTTPHeaderField: "X-Emby-Authorization"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["AccessToken"] as? String)
    }

    private func loadEnvFile() -> [String: String] {
        let envURL = URL(fileURLWithPath: "/Users/florian/Documents/Projet/ReelFin/.artifacts/secrets/reelfin-e2e.env")
        guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }
            values[key] = value
        }
        return values
    }

    private func normalizedItemID(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#,
            #"[0-9a-fA-F]{32}"#
        ]
        for pattern in patterns {
            if let range = value.range(of: pattern, options: .regularExpression) {
                return value[range].filter { $0 != "-" }.lowercased()
            }
        }
        return value.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return await condition()
    }
}

private extension String {
    var trimmedTrailingSlash: String {
        var result = self
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
