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

    // MARK: - 4K-movie scale: append-coalescing, dedupe, throttled index (the mid-film cut fix)

    /// A 4K movie commits tens of thousands of ≥256KB sub-blocks. One FILE per sub-block made every
    /// store operation an O(N) directory scan that eventually starved the serve loop mid-film.
    /// Contiguous sub-blocks must coalesce into a bounded number of segment files.
    func testContiguousWritesCoalesceIntoFewSegmentFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(
                chunkSize: 4, maxBytes: 1_024 * 1_024, segmentMaxBytes: 64
            )
        )
        let key = makeKey(suffix: "coalesce")

        // 32 contiguous 16-byte sub-blocks (= 512 bytes) with a 64-byte segment cap → 8 segments.
        var expected = Data()
        for block in 0..<32 {
            let payload = Data(repeating: UInt8(block), count: 16)
            expected.append(payload)
            try await store.write(range: ByteRange(offset: Int64(block * 16), length: 16), data: payload, key: key)
        }

        let served = try await store.readAvailablePrefix(from: 0, maxLength: 512, key: key)
        XCTAssertEqual(served, expected)
        let end = try await store.contiguousEnd(from: 0, key: key)
        XCTAssertEqual(end, 512)

        let cacheFiles = try cacheFileCount(in: directory)
        XCTAssertEqual(cacheFiles, 8, "32 contiguous sub-blocks must coalesce into ceil(512/64)=8 segment files, got \(cacheFiles)")
    }

    /// The serve path's on-demand fetch and the background downloader can fetch overlapping ranges.
    /// A write that is already (partially) covered must only persist the uncovered bytes — never
    /// duplicate coverage on disk.
    func testOverlappingWritesAreDeduplicated() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 1_024, segmentMaxBytes: 1_024)
        )
        let key = makeKey(suffix: "dedupe")

        try await store.write(range: ByteRange(offset: 0, length: 8), data: Data([0, 1, 2, 3, 4, 5, 6, 7]), key: key)
        // Overlaps [4,8) — only [8,12) may be written. The overlapping bytes carry the same origin
        // content; the store must keep serving the first copy.
        try await store.write(range: ByteRange(offset: 4, length: 8), data: Data([4, 5, 6, 7, 8, 9, 10, 11]), key: key)
        // Fully covered → no-op.
        try await store.write(range: ByteRange(offset: 2, length: 6), data: Data([2, 3, 4, 5, 6, 7]), key: key)

        let served = try await store.readAvailablePrefix(from: 0, maxLength: 12, key: key)
        XCTAssertEqual(served, Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]))

        let totalOnDisk = try cacheFileBytes(in: directory)
        XCTAssertEqual(totalOnDisk, 12, "overlapping writes must not duplicate bytes on disk")
    }

    /// A write that bridges a gap between two islands (partially covered on BOTH sides) must fill
    /// exactly the gap and make the whole span contiguous.
    func testGapBridgingWriteFillsExactlyTheGap() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 1_024, segmentMaxBytes: 1_024)
        )
        let key = makeKey(suffix: "bridge")

        try await store.write(range: ByteRange(offset: 0, length: 4), data: Data([0, 1, 2, 3]), key: key)
        try await store.write(range: ByteRange(offset: 8, length: 4), data: Data([8, 9, 10, 11]), key: key)
        // Bridge write overlaps both islands.
        try await store.write(range: ByteRange(offset: 2, length: 8), data: Data([2, 3, 4, 5, 6, 7, 8, 9]), key: key)

        let served = try await store.readAvailablePrefix(from: 0, maxLength: 12, key: key)
        XCTAssertEqual(served, Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]))
        let end = try await store.contiguousEnd(from: 0, key: key)
        XCTAssertEqual(end, 12)
    }

    /// The in-memory coverage cache must load existing (legacy per-sub-block) files from disk, so a
    /// prior play's cache keeps serving across a process restart / new store instance.
    func testCoverageSurvivesAcrossStoreInstances() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = makeKey(suffix: "restart")
        let config = MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 1_024, segmentMaxBytes: 32)

        do {
            let first = try MediaGatewayStore(directoryURL: directory, configuration: config)
            try await first.write(range: ByteRange(offset: 0, length: 8), data: Data([0, 1, 2, 3, 4, 5, 6, 7]), key: key)
            try await first.write(range: ByteRange(offset: 8, length: 8), data: Data([8, 9, 10, 11, 12, 13, 14, 15]), key: key)
        }

        let second = try MediaGatewayStore(directoryURL: directory, configuration: config)
        let served = try await second.readAvailablePrefix(from: 0, maxLength: 16, key: key)
        XCTAssertEqual(served, Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]))
        let end = try await second.contiguousEnd(from: 4, key: key)
        XCTAssertEqual(end, 16)
    }

    /// The index JSON used to be re-encoded + rewritten for EVERY ≥256KB sub-block (with a full
    /// directory scan) — an IO storm on the write hot path. Index persistence must be throttled;
    /// `flushIndex()` forces it (end of playback).
    func testIndexPersistenceIsThrottledOffTheWriteHotPath() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(
                chunkSize: 4, maxBytes: 1_024 * 1_024, segmentMaxBytes: 1_024,
                indexSyncBytes: 1_024 * 1_024, indexSyncSeconds: 3_600
            )
        )
        let key = makeKey(suffix: "throttle")
        let indexURL = directory.appendingPathComponent("index.json")

        let baseline = (try? Data(contentsOf: indexURL)) ?? Data()
        for block in 0..<16 {
            try await store.write(range: ByteRange(offset: Int64(block * 16), length: 16),
                                  data: Data(repeating: UInt8(block), count: 16), key: key)
        }
        let afterWrites = (try? Data(contentsOf: indexURL)) ?? Data()
        XCTAssertEqual(afterWrites, baseline, "index must not be rewritten per sub-block")

        await store.flushIndex()
        let index = try MediaGatewayIndex(directoryURL: directory)
        let record = await index.record(for: key)
        XCTAssertEqual(record?.byteSize, 256, "flushIndex must persist the real cached size")
    }

    /// Range-aware eviction: behind-playhead segments go, the protected head + everything at/after
    /// the cutoff stay, and the coverage map reflects it immediately.
    func testEvictRangesRemovesBehindCutoffButProtectsHeadAndForward() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 1_024 * 1_024, segmentMaxBytes: 8)
        )
        let key = makeKey(suffix: "evict")

        // 5 segments of 8 bytes: [0,8) head, [8,16), [16,24), [24,32), [32,40).
        for block in 0..<5 {
            try await store.write(range: ByteRange(offset: Int64(block * 8), length: 8),
                                  data: Data(repeating: UInt8(block), count: 8), key: key)
        }

        // Playhead ~32, rewind window 8 → cutoff 24; protect the first 8 bytes (head/moov).
        let freed = try await store.evictRanges(endingBefore: 24, key: key, protectingHeadBytes: 8)
        XCTAssertEqual(freed, 16, "segments [8,16) and [16,24) must be evicted")

        let head = try await store.readAvailablePrefix(from: 0, maxLength: 8, key: key)
        XCTAssertEqual(head, Data(repeating: 0, count: 8), "protected head must survive eviction")
        let evicted = try await store.readAvailablePrefix(from: 8, maxLength: 8, key: key)
        XCTAssertNil(evicted, "behind-cutoff range must be gone")
        let forward = try await store.readAvailablePrefix(from: 24, maxLength: 16, key: key)
        XCTAssertEqual(forward?.count, 16, "at/after-cutoff ranges are sacred")
        let size = try await store.cachedByteSize(key: key)
        XCTAssertEqual(size, 24)
    }

    private func cacheFileCount(in directory: URL) throws -> Int {
        try cacheFiles(in: directory).count
    }

    private func cacheFileBytes(in directory: URL) throws -> Int {
        try cacheFiles(in: directory).reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func cacheFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "cache" }
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
