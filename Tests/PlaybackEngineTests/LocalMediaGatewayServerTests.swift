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
        XCTAssertEqual(MockOriginalMediaProtocol.rangeRequestCount, 1)

        let second = try await fetchRange(url: assetURL, range: "bytes=4-7")
        XCTAssertEqual(second.statusCode, 206)
        XCTAssertEqual(second.data, Data([4, 5, 6, 7]))
        XCTAssertEqual(MockOriginalMediaProtocol.rangeRequestCount, 1)
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
        MediaGatewayCacheKey(
            scope: "original",
            userID: "user-1",
            serverID: "server-1",
            itemID: "item-1",
            sourceID: "source-1",
            routeURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            routeHeaders: ["Authorization": "Bearer secret"]
        )
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
