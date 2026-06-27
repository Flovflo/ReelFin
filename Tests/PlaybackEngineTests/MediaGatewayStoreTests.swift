import Foundation
import NativeMediaCore
import XCTest
@testable import PlaybackEngine

final class MediaGatewayStoreTests: XCTestCase {
    func testRangeMissThenWriteThenHit() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 128)
        )
        let key = makeKey(suffix: "hit")
        let range = ByteRange(offset: 0, length: 4)

        let miss = try await store.read(range: range, key: key)
        XCTAssertNil(miss)

        try await store.write(range: range, data: Data([0, 1, 2, 3]), key: key)

        let hit = try await store.read(range: ByteRange(offset: 1, length: 2), key: key)
        XCTAssertEqual(hit, Data([1, 2]))
        let covered = try await store.coveredRanges(key: key)
        XCTAssertEqual(covered, [range])
    }

    func testTrimProtectsActiveItemAndEvictsLRUItems() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 64)
        )
        let protected = makeKey(suffix: "protected")
        let evictable = makeKey(suffix: "evictable")

        try await store.write(range: ByteRange(offset: 0, length: 4), data: Data([1, 1, 1, 1]), key: evictable)
        try await store.write(range: ByteRange(offset: 0, length: 4), data: Data([2, 2, 2, 2]), key: protected)

        try await store.trim(budget: 4, protectedKeys: [protected])

        let evictedRead = try await store.read(range: ByteRange(offset: 0, length: 4), key: evictable)
        let protectedRead = try await store.read(range: ByteRange(offset: 0, length: 4), key: protected)
        XCTAssertNil(evictedRead)
        XCTAssertEqual(protectedRead, Data([2, 2, 2, 2]))
    }

    func testRemoveServerScopeDeletesOnlyMatchingServerRecords() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 128)
        )
        let serverA = makeKey(suffix: "a", serverID: "server-a")
        let serverB = makeKey(suffix: "b", serverID: "server-b")

        try await store.write(range: ByteRange(offset: 0, length: 4), data: Data([1, 2, 3, 4]), key: serverA)
        try await store.write(range: ByteRange(offset: 0, length: 4), data: Data([5, 6, 7, 8]), key: serverB)

        try await store.removeServerScope(serverID: "server-a", userID: nil)

        let removedRead = try await store.read(range: ByteRange(offset: 0, length: 4), key: serverA)
        let keptRead = try await store.read(range: ByteRange(offset: 0, length: 4), key: serverB)
        XCTAssertNil(removedRead)
        XCTAssertEqual(keptRead, Data([5, 6, 7, 8]))
    }

    func testPartialFilesAreIgnored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 128)
        )
        let key = makeKey(suffix: "partial")

        let partialURL = try await store.partialFileURLForTesting(
            range: ByteRange(offset: 0, length: 4),
            key: key
        )
        try FileManager.default.createDirectory(
            at: partialURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([9, 9, 9, 9]).write(to: partialURL)

        let read = try await store.read(range: ByteRange(offset: 0, length: 4), key: key)
        let covered = try await store.coveredRanges(key: key)
        XCTAssertNil(read)
        XCTAssertEqual(covered, [])
    }

    // MARK: - Never-cut serve primitives (cache resource loader foundation)

    func testReadAvailablePrefixServesPartialContiguousCoverage() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 1024)
        )
        let key = makeKey(suffix: "prefix")

        // Cache [0,8) but leave a gap at [8,12), then [12,16).
        try await store.write(range: ByteRange(offset: 0, length: 8), data: Data([0, 1, 2, 3, 4, 5, 6, 7]), key: key)
        try await store.write(range: ByteRange(offset: 12, length: 4), data: Data([12, 13, 14, 15]), key: key)

        // Asking for 16 bytes from 0 returns only the contiguous prefix [0,8) — never spans the gap.
        let prefix = try await store.readAvailablePrefix(from: 0, maxLength: 16, key: key)
        XCTAssertEqual(prefix, Data([0, 1, 2, 3, 4, 5, 6, 7]))

        // maxLength caps the slice even when more contiguous bytes exist.
        let capped = try await store.readAvailablePrefix(from: 2, maxLength: 3, key: key)
        XCTAssertEqual(capped, Data([2, 3, 4]))

        // Offset inside the gap → nil (nothing to serve right now).
        let inGap = try await store.readAvailablePrefix(from: 8, maxLength: 4, key: key)
        XCTAssertNil(inGap)

        // After the gap, the later island serves on its own.
        let island = try await store.readAvailablePrefix(from: 12, maxLength: 8, key: key)
        XCTAssertEqual(island, Data([12, 13, 14, 15]))
    }

    func testContiguousEndStopsAtFirstGap() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 1024)
        )
        let key = makeKey(suffix: "cend")

        try await store.write(range: ByteRange(offset: 0, length: 4), data: Data([0, 1, 2, 3]), key: key)
        try await store.write(range: ByteRange(offset: 4, length: 4), data: Data([4, 5, 6, 7]), key: key)
        try await store.write(range: ByteRange(offset: 12, length: 4), data: Data([12, 13, 14, 15]), key: key)

        // Contiguous from 0 runs through the two adjacent writes and stops at the gap (8).
        let end = try await store.contiguousEnd(from: 0, key: key)
        XCTAssertEqual(end, 8)

        // From a missing offset, the cursor doesn't advance.
        let stuck = try await store.contiguousEnd(from: 8, key: key)
        XCTAssertEqual(stuck, 8)
    }

    func testWriteEmitsCoverageEvent() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 1024)
        )
        let key = makeKey(suffix: "cov")

        // Subscribe before writing so the event is observed.
        let events = store.coverageEvents
        let collector = Task<Int64?, Never> {
            for await event in events {
                return event.advancedToOffset
            }
            return nil
        }

        try await store.write(range: ByteRange(offset: 0, length: 4), data: Data([0, 1, 2, 3]), key: key)

        let advancedTo = await collector.value
        XCTAssertEqual(advancedTo, 4)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaGatewayStoreTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeKey(suffix: String, serverID: String = "server-1") -> MediaGatewayCacheKey {
        MediaGatewayCacheKey(
            scope: "original",
            userID: "user-1",
            serverID: serverID,
            itemID: "item-\(suffix)",
            sourceID: "source-\(suffix)",
            routeURL: URL(string: "https://media.example.com/videos/\(suffix)/stream.mp4?static=true&api_key=secret")!,
            routeHeaders: ["Authorization": "Bearer secret"],
            audioSignature: "default",
            subtitleSignature: "none",
            resumeSeconds: 0
        )
    }
}
