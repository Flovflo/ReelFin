import Foundation
import ImageCache
import XCTest

final class LRUDiskCacheTests: XCTestCase {
    func testEvictsLeastRecentlyUsedItemWhenSizeExceeded() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try LRUDiskCache(directoryURL: cacheDir, maxSizeBytes: 100)

        await cache.setData(Data(repeating: 1, count: 60), forKey: "a")
        await cache.setData(Data(repeating: 2, count: 60), forKey: "b")

        let aData = await cache.data(forKey: "a")
        let bData = await cache.data(forKey: "b")

        XCTAssertNil(aData)
        XCTAssertNotNil(bData)
        let entries = await cache.entryCount()
        XCTAssertEqual(entries, 1)
    }

    func testUpdatesRecencyWhenRead() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try LRUDiskCache(directoryURL: cacheDir, maxSizeBytes: 160)

        await cache.setData(Data(repeating: 1, count: 60), forKey: "a")
        await cache.setData(Data(repeating: 2, count: 60), forKey: "b")

        _ = await cache.data(forKey: "a")
        await cache.setData(Data(repeating: 3, count: 80), forKey: "c")

        let aData = await cache.data(forKey: "a")
        let bData = await cache.data(forKey: "b")

        XCTAssertNotNil(aData)
        XCTAssertNil(bData)
    }

    func testReadAccessBatchesIndexPersistence() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try LRUDiskCache(
            directoryURL: cacheDir,
            maxSizeBytes: 256,
            indexPersistDelayNanoseconds: 500_000_000
        )

        await cache.setData(Data(repeating: 1, count: 48), forKey: "a")

        let indexURL = cacheDir.appendingPathComponent("index.json")
        let baseline = try decodeIndexSnapshot(from: indexURL)

        _ = await cache.data(forKey: "a")
        _ = await cache.data(forKey: "a")
        _ = await cache.data(forKey: "a")

        try await Task.sleep(nanoseconds: 200_000_000)

        let beforeFlush = try decodeIndexSnapshot(from: indexURL)
        XCTAssertEqual(beforeFlush["a"]?.lastAccess, baseline["a"]?.lastAccess)

        try await Task.sleep(nanoseconds: 400_000_000)

        let afterFlush = try decodeIndexSnapshot(from: indexURL)
        XCTAssertGreaterThan(
            afterFlush["a"]?.lastAccess ?? .distantPast,
            baseline["a"]?.lastAccess ?? .distantPast
        )
    }

    private func decodeIndexSnapshot(from url: URL) throws -> [String: IndexEntry] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: IndexEntry].self, from: data)
    }
}

private struct IndexEntry: Decodable {
    let fileName: String
    let size: Int
    let lastAccess: Date
}
