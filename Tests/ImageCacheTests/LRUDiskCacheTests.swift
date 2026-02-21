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
}
