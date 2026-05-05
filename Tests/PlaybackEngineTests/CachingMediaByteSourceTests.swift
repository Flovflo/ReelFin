import Foundation
import NativeMediaCore
import XCTest
@testable import PlaybackEngine

final class CachingMediaByteSourceTests: XCTestCase {
    func testNativeByteSourceReadsThroughPersistentCache() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let upstream = CountingByteSource(data: Data((0..<16).map(UInt8.init)))
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(chunkSize: 4, maxBytes: 128)
        )
        let source = CachingMediaByteSource(
            upstream: upstream,
            store: store,
            key: makeKey()
        )
        let range = ByteRange(offset: 4, length: 4)

        let first = try await source.read(range: range)
        let second = try await source.read(range: range)

        XCTAssertEqual(first, Data([4, 5, 6, 7]))
        XCTAssertEqual(second, Data([4, 5, 6, 7]))
        let upstreamReadCount = await upstream.readCount
        XCTAssertEqual(upstreamReadCount, 1)
        let metrics = await source.metrics()
        XCTAssertEqual(metrics.rangeRequestCount, 1)
        XCTAssertEqual(metrics.bufferedRanges, [range])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CachingMediaByteSourceTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeKey() -> MediaGatewayCacheKey {
        MediaGatewayCacheKey(
            scope: "native",
            userID: "user-1",
            serverID: "server-1",
            itemID: "item-1",
            sourceID: "source-1",
            routeURL: URL(string: "https://media.example.com/video.mkv?api_key=secret")!,
            routeHeaders: ["Authorization": "Bearer secret"]
        )
    }
}

private actor CountingByteSource: MediaByteSource {
    nonisolated let url = URL(string: "https://media.example.com/video.mkv")!
    private let data: Data
    private(set) var readCount = 0

    init(data: Data) {
        self.data = data
    }

    func read(range: ByteRange) async throws -> Data {
        readCount += 1
        let start = Int(range.offset)
        let end = min(data.count, start + range.length)
        return Data(data[start..<end])
    }

    func size() async throws -> Int64? {
        Int64(data.count)
    }

    func cancel() async {}

    func metrics() async -> MediaAccessMetrics {
        MediaAccessMetrics(rangeRequestCount: readCount)
    }
}
