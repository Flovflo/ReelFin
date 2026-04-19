import Foundation
import XCTest
@testable import PlaybackEngine

final class MediaGatewayIndexTests: XCTestCase {
    func testPersistenceAndReloadPreservesRecordState() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let index = try MediaGatewayIndex(directoryURL: directory)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let key = makeKey(suffix: "primary")
        let secondary = makeKey(suffix: "secondary")

        try await index.upsert(key: key, byteSize: 120, ttl: 120, now: now)
        _ = try await index.touch(key: key, now: now.addingTimeInterval(45))
        try await index.upsert(key: secondary, byteSize: 80, ttl: 240, now: now.addingTimeInterval(1))
        try await index.persist()

        let reloaded = try MediaGatewayIndex(directoryURL: directory)
        let record = await reloaded.record(for: key, now: now.addingTimeInterval(46))
        let secondaryRecord = await reloaded.record(for: secondary, now: now.addingTimeInterval(46))
        let recordCount = await reloaded.recordCount
        let byteSize = await reloaded.byteSize

        XCTAssertEqual(recordCount, 2)
        XCTAssertEqual(byteSize, 200)
        XCTAssertEqual(record?.byteSize, 120)
        XCTAssertEqual(record?.lastAccessAt, now.addingTimeInterval(45))
        XCTAssertEqual(record?.ttlSeconds, 120)
        XCTAssertEqual(secondaryRecord?.byteSize, 80)
        XCTAssertEqual(secondaryRecord?.ttlSeconds, 240)
    }

    func testReloadRecoversFromCorruptionByClearingState() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let index = try MediaGatewayIndex(directoryURL: directory)
        let key = makeKey(suffix: "corruptible")
        let indexURL = directory.appendingPathComponent("index.json")
        let now = Date(timeIntervalSince1970: 1_700_000_100)

        try await index.upsert(key: key, byteSize: 64, ttl: 60, now: now)
        try Data("{not-valid-json".utf8).write(to: indexURL, options: .atomic)

        let recovered = await index.reload()
        let recordCount = await index.recordCount
        let byteSize = await index.byteSize

        XCTAssertFalse(recovered)
        XCTAssertEqual(recordCount, 0)
        XCTAssertEqual(byteSize, 0)
    }

    func testTTLPrunesExpiredRecords() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let index = try MediaGatewayIndex(directoryURL: directory)
        let now = Date(timeIntervalSince1970: 1_700_000_200)
        let key = makeKey(suffix: "ttl")

        try await index.upsert(key: key, byteSize: 64, ttl: 60, now: now)

        let removed = try await index.pruneExpired(now: now.addingTimeInterval(61))
        let recordCount = await index.recordCount
        let byteSize = await index.byteSize

        XCTAssertEqual(removed, [key])
        XCTAssertEqual(recordCount, 0)
        XCTAssertEqual(byteSize, 0)
    }

    func testLRUEvictionAndOrderingAreDeterministic() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let index = try MediaGatewayIndex(directoryURL: directory)
        let now = Date(timeIntervalSince1970: 1_700_000_300)
        let keyA = makeKey(suffix: "a")
        let keyB = makeKey(suffix: "b")
        let keyC = makeKey(suffix: "c")

        try await index.upsert(key: keyA, byteSize: 100, now: now)
        try await index.upsert(key: keyB, byteSize: 100, now: now.addingTimeInterval(1))
        try await index.upsert(key: keyC, byteSize: 100, now: now.addingTimeInterval(2))
        _ = try await index.touch(key: keyA, now: now.addingTimeInterval(3))

        let order = await index.lruKeys(now: now.addingTimeInterval(3))
        XCTAssertEqual(order, [keyB, keyC, keyA])

        let evicted = try await index.evictLRU(keepingMaxByteSize: 100, now: now.addingTimeInterval(4))
        let recordCount = await index.recordCount
        let byteSize = await index.byteSize
        XCTAssertEqual(evicted, [keyB, keyC])
        XCTAssertEqual(recordCount, 1)
        XCTAssertEqual(byteSize, 100)
        let remaining = await index.record(for: keyA, now: now.addingTimeInterval(4))
        XCTAssertEqual(remaining?.byteSize, 100)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaGatewayIndexTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeKey(suffix: String) -> MediaGatewayCacheKey {
        MediaGatewayCacheKey(
            scope: "playback",
            userID: "user-1",
            serverID: "server-1",
            itemID: "item-\(suffix)",
            sourceID: "source-\(suffix)",
            routeURL: URL(
                string: "https://media.example.com/library/items/\(suffix)/master.m3u8?container=fmp4&quality=high&token=secret-\(suffix)"
            )!,
            routeHeaders: [
                "Authorization": "Bearer secret-\(suffix)",
                "Accept": "application/vnd.apple.mpegurl"
            ],
            audioSignature: "codec=eac3|channels=6|lang=en",
            subtitleSignature: "codec=srt|lang=fr",
            resumeSeconds: 45
        )
    }
}
