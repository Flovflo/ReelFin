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

    func testSmallAVPlayerRangesReuseCoalescedRemoteWindow() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remoteLength = 6 * 1_024 * 1_024
        MockOriginalMediaProtocol.storage = Data((0..<remoteLength).map { UInt8($0 % 251) })
        let key = makeKey()
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 64 * 1_024, maxBytes: 16 * 1_024 * 1_024)
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: key,
            store: store,
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_coalesced_window") }

        let firstOffset = 1 * 1_024 * 1_024
        let secondOffset = firstOffset + 64 * 1_024
        let first = try await fetchRange(url: assetURL, range: "bytes=\(firstOffset)-\(secondOffset - 1)")
        let second = try await fetchRange(url: assetURL, range: "bytes=\(secondOffset)-\(secondOffset + 64 * 1_024 - 1)")

        XCTAssertEqual(first.statusCode, 206)
        XCTAssertEqual(first.data.count, 64 * 1_024)
        XCTAssertEqual(second.statusCode, 206)
        XCTAssertEqual(second.data.count, 64 * 1_024)
        XCTAssertEqual(MockOriginalMediaProtocol.rangeRequestCount, 1)
        XCTAssertTrue(
            MockOriginalMediaProtocol.requestedHeaders.contains {
                $0["Range"] == "bytes=\(firstOffset)-"
            }
        )
    }

    func testBoundedNonZeroAVPlayerRangeUsesOpenEndedUpstreamRequest() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<64).map(UInt8.init))
        MockOriginalMediaProtocol.ignoresBoundedNonZeroRangeRequests = true
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
        defer { server.stop(reason: "test_teardown_bounded_nonzero_open_upstream") }

        let response = try await fetchRange(url: assetURL, range: "bytes=8-11")

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.data, Data((8...11).map(UInt8.init)))
        XCTAssertTrue(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=8-" })
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

    func testOpenEndedRangeServesCompleteRequestedRangeForLargeAVPlayerRequest() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gatewayWindowLength = 4 * 1_024 * 1_024
        let remoteLength = gatewayWindowLength + 1_024
        MockOriginalMediaProtocol.storage = Data((0..<remoteLength).map { UInt8($0 % 251) })
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 64 * 1_024, maxBytes: 16 * 1_024 * 1_024)
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
        defer { server.stop(reason: "test_teardown_large_open_ended") }

        let response = try await fetchRange(url: assetURL, range: "bytes=0-")

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.data.count, remoteLength)
        XCTAssertEqual(response.data.first, 0)
        XCTAssertEqual(response.data.last, UInt8((remoteLength - 1) % 251))
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Length"), "\(remoteLength)")
        XCTAssertEqual(
            response.response.value(forHTTPHeaderField: "Content-Range"),
            "bytes 0-\(remoteLength - 1)/\(remoteLength)"
        )
    }

    func testLargeBoundedRangeServesCompleteRequestedRangeForAVPlayerFullFileRequest() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gatewayWindowLength = 4 * 1_024 * 1_024
        let remoteLength = gatewayWindowLength + 512 * 1_024
        MockOriginalMediaProtocol.storage = Data(repeating: 7, count: remoteLength)
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 64 * 1_024, maxBytes: 16 * 1_024 * 1_024)
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
        defer { server.stop(reason: "test_teardown_full_file_range") }

        let response = try await fetchRange(url: assetURL, range: "bytes=0-\(remoteLength - 1)")

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.data.count, remoteLength)
        XCTAssertEqual(response.data.first, 7)
        XCTAssertEqual(response.data.last, 7)
        XCTAssertEqual(
            response.response.value(forHTTPHeaderField: "Content-Range"),
            "bytes 0-\(remoteLength - 1)/\(remoteLength)"
        )
        XCTAssertTrue(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=0-\(remoteLength - 1)" })
    }

    func testLargeBoundedNonZeroRangeUsesOpenEndedUpstreamRequest() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startOffset = 1 * 1_024 * 1_024
        let requestedLength = 4 * 1_024 * 1_024 + 512 * 1_024
        let remoteLength = startOffset + requestedLength + 256 * 1_024
        MockOriginalMediaProtocol.storage = Data((0..<remoteLength).map { UInt8($0 % 251) })
        MockOriginalMediaProtocol.ignoresBoundedNonZeroRangeRequests = true
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 64 * 1_024, maxBytes: 16 * 1_024 * 1_024)
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
        defer { server.stop(reason: "test_teardown_large_nonzero_open_upstream") }

        let endOffset = startOffset + requestedLength - 1
        let response = try await fetchRange(url: assetURL, range: "bytes=\(startOffset)-\(endOffset)")

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.data.count, requestedLength)
        XCTAssertEqual(response.data.first, UInt8(startOffset % 251))
        XCTAssertEqual(response.data.last, UInt8(endOffset % 251))
        XCTAssertTrue(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=\(startOffset)-" })
    }

    func testLargeStreamingRangeServesCachedPrefixBeforeRemoteFetch() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startOffset = 1 * 1_024 * 1_024
        let cachedLength = 512 * 1_024
        let requestedLength = 4 * 1_024 * 1_024 + 512 * 1_024
        let remoteLength = startOffset + requestedLength + 256 * 1_024
        MockOriginalMediaProtocol.storage = Data((0..<remoteLength).map { UInt8($0 % 251) })
        MockOriginalMediaProtocol.ignoresBoundedNonZeroRangeRequests = true
        let key = makeKey()
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 64 * 1_024, maxBytes: 16 * 1_024 * 1_024)
        )
        let cachedRange = ByteRange(offset: Int64(startOffset), length: cachedLength)
        try await store.write(
            range: cachedRange,
            data: Data(MockOriginalMediaProtocol.storage[startOffset..<(startOffset + cachedLength)]),
            key: key
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: key,
            store: store,
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_stream_cached_prefix") }

        let endOffset = startOffset + requestedLength - 1
        let response = try await fetchRange(url: assetURL, range: "bytes=\(startOffset)-\(endOffset)")

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.data.count, requestedLength)
        XCTAssertEqual(response.data.prefix(cachedLength), MockOriginalMediaProtocol.storage[startOffset..<(startOffset + cachedLength)])
        XCTAssertTrue(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=\(startOffset + cachedLength)-" })
        XCTAssertFalse(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=\(startOffset)-" })
    }

    func testLargeStreamingRangeStitchesCachedWindowAfterRemoteGap() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startOffset = 1 * 1_024 * 1_024
        let gapLength = 128 * 1_024
        let cachedLength = 2 * 1_024 * 1_024
        let tailLength = 3 * 1_024 * 1_024
        let cachedOffset = startOffset + gapLength
        let requestedLength = gapLength + cachedLength + tailLength
        let remoteLength = startOffset + requestedLength + 256 * 1_024
        MockOriginalMediaProtocol.storage = Data((0..<remoteLength).map { UInt8($0 % 251) })
        MockOriginalMediaProtocol.ignoresBoundedNonZeroRangeRequests = true
        let key = makeKey()
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 64 * 1_024, maxBytes: 16 * 1_024 * 1_024)
        )
        try await store.write(
            range: ByteRange(offset: Int64(cachedOffset), length: cachedLength),
            data: Data(MockOriginalMediaProtocol.storage[cachedOffset..<(cachedOffset + cachedLength)]),
            key: key
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: key,
            store: store,
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_stream_cached_gap") }

        let endOffset = startOffset + requestedLength - 1
        let response = try await fetchRange(url: assetURL, range: "bytes=\(startOffset)-\(endOffset)")

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.data.count, requestedLength)
        XCTAssertEqual(response.data, Data(MockOriginalMediaProtocol.storage[startOffset..<(startOffset + requestedLength)]))
        XCTAssertTrue(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=\(startOffset)-" })
        XCTAssertTrue(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=\(cachedOffset + cachedLength)-" })
        XCTAssertGreaterThanOrEqual(MockOriginalMediaProtocol.rangeRequestCount, 2)
    }

    func testLargeStreamingRangeFullyCachedAvoidsRemoteFetch() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startOffset = 1 * 1_024 * 1_024
        let requestedLength = 4 * 1_024 * 1_024 + 512 * 1_024
        let remoteLength = startOffset + requestedLength + 256 * 1_024
        MockOriginalMediaProtocol.storage = Data((0..<remoteLength).map { UInt8($0 % 251) })
        let key = makeKey()
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 64 * 1_024, maxBytes: 16 * 1_024 * 1_024)
        )
        let cachedRange = ByteRange(offset: Int64(startOffset), length: requestedLength)
        try await store.write(
            range: cachedRange,
            data: Data(MockOriginalMediaProtocol.storage[startOffset..<(startOffset + requestedLength)]),
            key: key
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: key,
            store: store,
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_stream_fully_cached") }

        let endOffset = startOffset + requestedLength - 1
        let response = try await fetchRange(url: assetURL, range: "bytes=\(startOffset)-\(endOffset)")

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.data.count, requestedLength)
        XCTAssertEqual(response.data, Data(MockOriginalMediaProtocol.storage[startOffset..<(startOffset + requestedLength)]))
        XCTAssertEqual(MockOriginalMediaProtocol.rangeRequestCount, 0)
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

    /// The literal "it must not cut to reload" test: plays a real high-bitrate direct-play
    /// original through the production gateway with the same steady-state buffering the app
    /// applies (waits-to-minimize-stalling + 30s forward buffer), then asserts playback
    /// advances past the ~1 min mark where it used to stall, with zero rebuffer stalls after
    /// the first frame. Runs in real time, so it is gated behind live env values.
    @MainActor
    func testLiveGatewaySustainsContinuousPlaybackPastOneMinute() async throws {
        guard let target = try await makeLiveDirectPlayGatewayTarget() else {
            throw XCTSkip("Set ReelFin live Jellyfin env values to run the sustained playback test.")
        }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = LocalMediaGatewaySession(
            remoteURL: target.url,
            headers: target.headers,
            key: makeKey(routeURL: target.url, routeHeaders: target.headers),
            store: try MediaGatewayStore(directoryURL: directory)
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_sustained_playback") }

        let asset = AVURLAsset(url: assetURL, options: [AVURLAssetOverrideMIMETypeKey: "video/mp4"])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = DirectPlaySessionPolicy.steadyStateForwardBufferSeconds
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        defer { player.pause() }

        let stallCounter = StallCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { _ in stallCounter.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let becameReady = await waitUntil(timeout: 30) { item.status != .unknown }
        XCTAssertTrue(becameReady, "Live gateway AVPlayerItem stayed unknown for item \(target.itemID.prefix(8)).")
        XCTAssertNotEqual(item.status, .failed, "Live gateway playback failed: \(String(describing: item.error)).")

        player.playImmediately(atRate: 1)
        let startedPlaying = await waitUntil(timeout: 30) { player.currentTime().seconds > 0.5 }
        XCTAssertTrue(startedPlaying, "Playback never advanced past the first frame.")
        stallCounter.reset() // ignore any startup-phase stall; we measure steady-state only

        // Watch past the ~1 min mark where the thin-buffer config used to cut to rebuffer.
        let targetSeconds = 65.0
        let reachedTarget = await waitUntil(timeout: 100) { player.currentTime().seconds >= targetSeconds }
        let reached = player.currentTime().seconds
        let stalls = stallCounter.value
        print(String(
            format: "live.gateway.sustained — reachedSeconds=%.1f targetSeconds=%.1f postFirstFrameStalls=%d item=%@",
            reached, targetSeconds, stalls, String(target.itemID.prefix(8))
        ))
        XCTAssertTrue(reachedTarget, "Playback only reached \(String(format: "%.1f", reached))s of \(targetSeconds)s — it stalled/cut before the target.")
        XCTAssertEqual(stalls, 0, "Playback stalled \(stalls) time(s) after the first frame — it cut to rebuffer.")
    }

    private final class StallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        func increment() { lock.lock(); count += 1; lock.unlock() }
        func reset() { lock.lock(); count = 0; lock.unlock() }
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

    func testExposedLocalURLKeepsUpstreamMP4ExtensionForAVFoundationSniffing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<32).map(UInt8.init))
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/stream.mp4?api_key=secret")!,
            headers: ["X-Emby-Token": "secret"],
            key: makeKey(),
            store: try MediaGatewayStore(directoryURL: directory),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_local_extension") }

        XCTAssertEqual(assetURL.pathExtension, "mp4")
        XCTAssertFalse(assetURL.absoluteString.contains("secret"))
        XCTAssertFalse(assetURL.absoluteString.contains("api_key"))

        let response = try await fetchRange(url: assetURL, range: "bytes=0-3")
        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.data, Data((0..<4).map(UInt8.init)))

        let legacyURL = assetURL.deletingPathExtension()
        let legacyResponse = try await fetchRange(url: legacyURL, range: "bytes=4-7")
        XCTAssertEqual(legacyResponse.statusCode, 206)
        XCTAssertEqual(legacyResponse.data, Data((4..<8).map(UInt8.init)))
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

    func testGatewayPrefetchUsesOpenEndedNonZeroRangeWhenServerIgnoresBoundedRanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<128).map(UInt8.init))
        MockOriginalMediaProtocol.ignoresBoundedNonZeroRangeRequests = true
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
        defer { server.stop(reason: "test_teardown_prefetch_bounded_nonzero") }

        let first = try await fetchRange(url: assetURL, range: "bytes=0-7")
        XCTAssertEqual(first.data, Data((0..<8).map(UInt8.init)))

        let prefetchRange = ByteRange(offset: 8, length: 8)
        let didPrefetch = await waitUntil(timeout: 2) {
            (try? await store.read(range: prefetchRange, key: key)) != nil
        }

        XCTAssertTrue(didPrefetch)
        let prefetched = try await store.read(range: prefetchRange, key: key)
        XCTAssertEqual(prefetched, Data((8..<16).map(UInt8.init)))
        XCTAssertTrue(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=8-" })
        XCTAssertFalse(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=8-15" })
    }

    func testGatewayPrefetchReanchorsAfterResumeRangeRequest() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resumeOffset = 1 * 1_024 * 1_024
        let remoteLength = resumeOffset + 512 * 1_024
        MockOriginalMediaProtocol.storage = Data((0..<remoteLength).map { UInt8($0 % 251) })
        MockOriginalMediaProtocol.responseDelayNanoseconds = 200_000_000
        let key = makeKey()
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 8, maxBytes: 8 * 1_024 * 1_024)
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["Authorization": "Bearer secret"],
            key: key,
            store: store,
            prefetchConfiguration: LocalMediaGatewayPrefetchConfiguration(
                mediaCacheMode: .automatic,
                isTVOS: false,
                routeKind: .directPlayOriginal,
                sourceBitrate: 8 * 1_024 * 1_024,
                runtimeSeconds: 3_600,
                isExpensiveNetwork: false,
                isConstrainedNetwork: false
            ),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_prefetch_reanchor") }

        let startup = try await fetchRange(url: assetURL, range: "bytes=0-7")
        XCTAssertEqual(startup.data, Data((0..<8).map(UInt8.init)))

        let resume = try await fetchRange(url: assetURL, range: "bytes=\(resumeOffset)-\(resumeOffset + 7)")
        XCTAssertEqual(resume.data, Data((resumeOffset..<(resumeOffset + 8)).map { UInt8($0 % 251) }))

        let expectedPrefetchHeader = "bytes=\(resumeOffset + 8)-"
        let didReanchor = await waitUntil(timeout: 3) {
            MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == expectedPrefetchHeader }
        }
        XCTAssertTrue(didReanchor)
    }

    func testGatewayPrefetchReanchorIgnoresBackwardMetadataRangeDuringResumeWindow() {
        let resumeWindowStart: Int64 = 482_279_424
        let metadataWindowStart: Int64 = 24_444_928
        let reanchorDistance: Int64 = 1 * 1_024 * 1_024

        XCTAssertFalse(
            LocalMediaGatewayPrefetcher.shouldReanchorPrefetch(
                activeStartOffset: resumeWindowStart,
                activeEndOffset: resumeWindowStart + 155 * 1_024 * 1_024,
                newStartOffset: metadataWindowStart,
                reanchorDistance: reanchorDistance,
                activePriority: .streamingPlayback,
                newPriority: .rangeProbe
            )
        )
        XCTAssertTrue(
            LocalMediaGatewayPrefetcher.shouldReanchorPrefetch(
                activeStartOffset: resumeWindowStart,
                activeEndOffset: resumeWindowStart + 155 * 1_024 * 1_024,
                newStartOffset: 168_624_128,
                reanchorDistance: reanchorDistance,
                activePriority: .streamingPlayback,
                newPriority: .streamingPlayback
            )
        )
        XCTAssertFalse(
            LocalMediaGatewayPrefetcher.shouldReanchorPrefetch(
                activeStartOffset: 168_624_128,
                activeEndOffset: 340_000_000,
                newStartOffset: resumeWindowStart,
                reanchorDistance: reanchorDistance,
                activePriority: .streamingPlayback,
                newPriority: .streamingPlayback
            )
        )
        XCTAssertTrue(
            LocalMediaGatewayPrefetcher.shouldReanchorPrefetch(
                activeStartOffset: metadataWindowStart,
                newStartOffset: resumeWindowStart,
                reanchorDistance: reanchorDistance,
                activePriority: .rangeProbe,
                newPriority: .streamingPlayback
            )
        )
        XCTAssertFalse(
            LocalMediaGatewayPrefetcher.shouldReanchorPrefetch(
                activeStartOffset: resumeWindowStart,
                activeEndOffset: resumeWindowStart + 155 * 1_024 * 1_024,
                newStartOffset: resumeWindowStart + reanchorDistance / 2,
                reanchorDistance: reanchorDistance,
                activePriority: .streamingPlayback,
                newPriority: .streamingPlayback
            )
        )
        XCTAssertFalse(
            LocalMediaGatewayPrefetcher.shouldReanchorPrefetch(
                activeStartOffset: resumeWindowStart,
                activeEndOffset: resumeWindowStart + 155 * 1_024 * 1_024,
                newStartOffset: resumeWindowStart + 3 * reanchorDistance,
                reanchorDistance: reanchorDistance,
                activePriority: .streamingPlayback,
                newPriority: .streamingPlayback
            )
        )
        XCTAssertTrue(
            LocalMediaGatewayPrefetcher.shouldReanchorPrefetch(
                activeStartOffset: resumeWindowStart,
                activeEndOffset: resumeWindowStart + 155 * 1_024 * 1_024,
                newStartOffset: resumeWindowStart + 156 * 1_024 * 1_024,
                reanchorDistance: reanchorDistance,
                activePriority: .streamingPlayback,
                newPriority: .streamingPlayback
            )
        )
        XCTAssertTrue(
            LocalMediaGatewayPrefetcher.shouldReanchorPrefetch(
                activeStartOffset: resumeWindowStart,
                newStartOffset: resumeWindowStart + reanchorDistance + 1,
                reanchorDistance: reanchorDistance,
                activePriority: .streamingPlayback,
                newPriority: .streamingPlayback
            )
        )
        XCTAssertFalse(
            LocalMediaGatewayPrefetcher.shouldReanchorPrefetch(
                activeStartOffset: resumeWindowStart,
                newStartOffset: resumeWindowStart + 512 * 1_024 * 1_024,
                reanchorDistance: reanchorDistance,
                activePriority: .streamingPlayback,
                newPriority: .rangeProbe
            )
        )
    }

    func testGatewayPrefetchKeepsResumeWindowWhenMetadataRangeArrivesAfterward() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resumeOffset = 2 * 1_024 * 1_024
        let prefetchOffset = resumeOffset + 8
        let remoteLength = resumeOffset + 3 * 1_024 * 1_024
        MockOriginalMediaProtocol.storage = Data((0..<remoteLength).map { UInt8($0 % 251) })
        MockOriginalMediaProtocol.responseDelayNanosecondsForRangeStart = [prefetchOffset: 1_000_000_000]
        let key = makeKey()
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 8, maxBytes: 8 * 1_024 * 1_024)
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["Authorization": "Bearer secret"],
            key: key,
            store: store,
            prefetchConfiguration: LocalMediaGatewayPrefetchConfiguration(
                mediaCacheMode: .automatic,
                isTVOS: false,
                routeKind: .directPlayOriginal,
                sourceBitrate: 8 * 1_024 * 1_024,
                runtimeSeconds: 3_600,
                isExpensiveNetwork: false,
                isConstrainedNetwork: false
            ),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_prefetch_resume_window") }

        let resume = try await fetchRange(url: assetURL, range: "bytes=\(resumeOffset)-\(resumeOffset + 7)")
        XCTAssertEqual(resume.data, Data((resumeOffset..<(resumeOffset + 8)).map { UInt8($0 % 251) }))

        let metadata = try await fetchRange(url: assetURL, range: "bytes=0-7")
        XCTAssertEqual(metadata.data, Data((0..<8).map(UInt8.init)))

        let highPrefetchRange = ByteRange(offset: Int64(prefetchOffset), length: 2 * 1_024 * 1_024)
        let didKeepResumePrefetch = await waitUntil(timeout: 3) {
            (try? await store.read(range: highPrefetchRange, key: key)) != nil
        }

        XCTAssertTrue(didKeepResumePrefetch)
        XCTAssertTrue(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=\(prefetchOffset)-" })
    }

    func testGatewayPrefetchKeepsPlaybackStreamWindowWhenSpeculativeProbeJumpsAhead() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resumeOffset = 2 * 1_024 * 1_024
        let playbackLength = 6 * 1_024 * 1_024
        let speculativeOffset = 96 * 1_024 * 1_024
        let remoteLength = speculativeOffset + 8 * 1_024 * 1_024
        MockOriginalMediaProtocol.storage = Data((0..<remoteLength).map { UInt8($0 % 251) })
        MockOriginalMediaProtocol.responseDelayNanosecondsForRangeStart = [
            resumeOffset: 800_000_000
        ]
        let key = makeKey()
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 512 * 1_024, maxBytes: 128 * 1_024 * 1_024)
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["Authorization": "Bearer secret"],
            key: key,
            store: store,
            prefetchConfiguration: LocalMediaGatewayPrefetchConfiguration(
                mediaCacheMode: .automatic,
                isTVOS: false,
                routeKind: .directPlayOriginal,
                sourceBitrate: 8 * 1_024 * 1_024,
                runtimeSeconds: 3_600,
                isExpensiveNetwork: false,
                isConstrainedNetwork: false
            ),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_prefetch_speculative_probe") }

        async let playback = fetchRange(
            url: assetURL,
            range: "bytes=\(resumeOffset)-\(resumeOffset + playbackLength - 1)"
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        let probe = try await fetchRange(
            url: assetURL,
            range: "bytes=\(speculativeOffset)-\(speculativeOffset + 65_535)"
        )
        XCTAssertEqual(probe.statusCode, 206)
        _ = try await playback

        let protectedPlaybackWindow = ByteRange(
            offset: Int64(resumeOffset + 1 * 1_024 * 1_024),
            length: 2 * 1_024 * 1_024
        )
        let didKeepPlaybackWindow = await waitUntil(timeout: 3) {
            (try? await store.read(range: protectedPlaybackWindow, key: key)) != nil
        }

        XCTAssertTrue(didKeepPlaybackWindow)
        XCTAssertTrue(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=\(resumeOffset)-" })
        XCTAssertFalse(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=\(speculativeOffset + 65_536)-" })
    }

    func testGatewayStreamingResponseCachesLargeNonZeroRangeForStartupEvidence() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startOffset = 1 * 1_024 * 1_024
        let requestedLength = 5 * 1_024 * 1_024
        let remoteLength = startOffset + requestedLength + 512 * 1_024
        MockOriginalMediaProtocol.storage = Data((0..<remoteLength).map { UInt8($0 % 251) })
        let key = makeKey()
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 512 * 1_024, maxBytes: 16 * 1_024 * 1_024)
        )
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4?api_key=secret")!,
            headers: ["Authorization": "Bearer secret"],
            key: key,
            store: store,
            prefetchConfiguration: LocalMediaGatewayPrefetchConfiguration(
                mediaCacheMode: .automatic,
                isTVOS: false,
                routeKind: .directPlayOriginal,
                sourceBitrate: 8 * 1_024 * 1_024,
                runtimeSeconds: 3_600,
                isExpensiveNetwork: false,
                isConstrainedNetwork: false
            ),
            sessionConfiguration: makeMockSessionConfiguration()
        )
        let server = LocalMediaGatewayServer(session: session)
        let assetURL = try server.start()
        defer { server.stop(reason: "test_teardown_streaming_cache") }

        let result = try await fetchRange(
            url: assetURL,
            range: "bytes=\(startOffset)-\(startOffset + requestedLength - 1)"
        )

        XCTAssertEqual(result.statusCode, 206)
        XCTAssertEqual(result.data.count, requestedLength)
        let cached = try await store.read(
            range: ByteRange(offset: Int64(startOffset), length: 1 * 1_024 * 1_024),
            key: key
        )
        XCTAssertEqual(cached?.count, 1 * 1_024 * 1_024)
        let diagnostics = await session.diagnostics()
        XCTAssertEqual(diagnostics.largestNonZeroCachedOffset, Int64(startOffset))
        XCTAssertGreaterThanOrEqual(diagnostics.latestNonZeroCachedRangeLength ?? 0, Int64(requestedLength))
        XCTAssertEqual(diagnostics.nonZeroCachedRanges.first?.offset, Int64(startOffset))
        XCTAssertGreaterThanOrEqual(diagnostics.nonZeroCachedRanges.first?.length ?? 0, Int64(requestedLength))
        XCTAssertGreaterThan(diagnostics.observedBitrate ?? 0, 0)
    }

    func testGatewayPrefetchDoesNotCacheIgnoredNonZeroRangeResponse() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = Data((0..<128).map(UInt8.init))
        MockOriginalMediaProtocol.ignoresNonZeroRangeRequests = true
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
        defer { server.stop(reason: "test_teardown_prefetch_ignored_range") }

        let first = try await fetchRange(url: assetURL, range: "bytes=0-7")
        XCTAssertEqual(first.data, Data((0..<8).map(UInt8.init)))

        let prefetchRange = ByteRange(offset: 8, length: 8)
        let didCacheIgnoredRange = await waitUntil(timeout: 0.5) {
            (try? await store.read(range: prefetchRange, key: key)) != nil
        }
        XCTAssertFalse(didCacheIgnoredRange)
        XCTAssertGreaterThanOrEqual(MockOriginalMediaProtocol.rangeRequestCount, 2)
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
        XCTAssertTrue(MockOriginalMediaProtocol.requestedHeaders.contains { $0["Range"] == "bytes=4-" })
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
