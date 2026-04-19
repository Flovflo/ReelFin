import Foundation
@testable import PlaybackEngine
import XCTest

final class HLSSegmentDiskCacheTests: XCTestCase {
    func testStoreAndReadHit() async throws {
        let directoryURL = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let cache = try HLSSegmentDiskCache(directoryURL: directoryURL, maxSizeBytes: 1024)
        let key = HLSSegmentDiskCache.Key(
            kind: .mediaPlaylist,
            identifier: "https://example.com/video.m3u8?api_key=secret-token"
        )
        let payload = Data("playlist-body".utf8)

        await cache.setData(payload, for: key)

        let entryCount = await cache.entryCount()
        let currentSizeBytes = await cache.currentSizeBytes()
        let cachedPayload = await cache.data(for: key)

        XCTAssertEqual(entryCount, 1)
        XCTAssertEqual(currentSizeBytes, payload.count)
        XCTAssertEqual(cachedPayload, payload)
    }

    func testReadMissForUnknownKey() async throws {
        let directoryURL = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let cache = try HLSSegmentDiskCache(directoryURL: directoryURL)
        let key = HLSSegmentDiskCache.Key(kind: .masterPlaylist, identifier: "missing")

        let cachedPayload = await cache.data(for: key)
        let entryCount = await cache.entryCount()

        XCTAssertNil(cachedPayload)
        XCTAssertEqual(entryCount, 0)
    }

    func testEvictsLeastRecentlyUsedEntriesWhenBudgetExceeded() async throws {
        let directoryURL = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let cache = try HLSSegmentDiskCache(directoryURL: directoryURL, maxSizeBytes: 160)
        let keyA = HLSSegmentDiskCache.Key(kind: .mediaSegment, identifier: "segment-a")
        let keyB = HLSSegmentDiskCache.Key(kind: .mediaSegment, identifier: "segment-b")
        let keyC = HLSSegmentDiskCache.Key(kind: .mediaSegment, identifier: "segment-c")

        await cache.setData(Data(repeating: 1, count: 60), for: keyA)
        await cache.setData(Data(repeating: 2, count: 60), for: keyB)
        _ = await cache.data(for: keyA)
        await cache.setData(Data(repeating: 3, count: 80), for: keyC)

        let cachedA = await cache.data(for: keyA)
        let cachedB = await cache.data(for: keyB)
        let cachedC = await cache.data(for: keyC)
        let entryCount = await cache.entryCount()
        let currentSizeBytes = await cache.currentSizeBytes()

        XCTAssertNotNil(cachedA)
        XCTAssertNil(cachedB)
        XCTAssertNotNil(cachedC)
        XCTAssertEqual(entryCount, 2)
        XCTAssertEqual(currentSizeBytes, 140)
    }

    func testOverwriteUpdatesByteSize() async throws {
        let directoryURL = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let cache = try HLSSegmentDiskCache(directoryURL: directoryURL, maxSizeBytes: 256)
        let key = HLSSegmentDiskCache.Key(kind: .initSegment, identifier: "init")
        let initial = Data(repeating: 0x11, count: 40)
        let updated = Data(repeating: 0x22, count: 70)

        await cache.setData(initial, for: key)
        await cache.setData(updated, for: key)

        let entryCount = await cache.entryCount()
        let currentSizeBytes = await cache.currentSizeBytes()
        let cachedPayload = await cache.data(for: key)

        XCTAssertEqual(entryCount, 1)
        XCTAssertEqual(currentSizeBytes, 70)
        XCTAssertEqual(cachedPayload, updated)
    }

    func testDoesNotLeakSensitiveMaterialInFilenamesOrIndex() async throws {
        let directoryURL = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let cache = try HLSSegmentDiskCache(directoryURL: directoryURL)
        let rawKey = "https://example.com/segment.ts?api_key=secret-token&Authorization=Bearer header-token&X-Emby-Token=abc123"
        let key = HLSSegmentDiskCache.Key(kind: .mediaSegment, identifier: rawKey)

        await cache.setData(Data([0x01, 0x02, 0x03]), for: key)

        let files = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        let filenames = files.map(\.lastPathComponent).joined(separator: "\n")
        let indexText = try String(
            contentsOf: directoryURL.appendingPathComponent("index.json"),
            encoding: .utf8
        )

        for needle in ["secret-token", "Authorization", "Bearer", "X-Emby-Token", "api_key", "header-token"] {
            XCTAssertFalse(filenames.contains(needle))
            XCTAssertFalse(indexText.contains(needle))
        }
    }

    func testRecoversFromCorruptedIndexUsingOnDiskFiles() async throws {
        let directoryURL = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let originalCache = try HLSSegmentDiskCache(directoryURL: directoryURL, maxSizeBytes: 1024)
        let key = HLSSegmentDiskCache.Key(kind: .initSegment, identifier: "https://example.com/init.mp4?token=secret-token")
        let payload = Data("init-segment".utf8)

        await originalCache.setData(payload, for: key)
        try "{not-json".write(to: directoryURL.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)

        let recoveredCache = try HLSSegmentDiskCache(directoryURL: directoryURL, maxSizeBytes: 1024)

        let cachedPayload = await recoveredCache.data(for: key)
        let entryCount = await recoveredCache.entryCount()

        XCTAssertEqual(cachedPayload, payload)
        XCTAssertEqual(entryCount, 1)
    }

    func testExpiresEntriesAfterTTL() async throws {
        let directoryURL = makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let cache = try HLSSegmentDiskCache(directoryURL: directoryURL, maxSizeBytes: 1024, ttl: 0.1)
        let key = HLSSegmentDiskCache.Key(kind: .masterPlaylist, identifier: "ttl-test")
        let payload = Data("ttl".utf8)

        await cache.setData(payload, for: key)
        try await Task.sleep(nanoseconds: 250_000_000)

        let cachedPayload = await cache.data(for: key)
        let entryCount = await cache.entryCount()

        XCTAssertNil(cachedPayload)
        XCTAssertEqual(entryCount, 0)
    }

    private func makeCacheDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
