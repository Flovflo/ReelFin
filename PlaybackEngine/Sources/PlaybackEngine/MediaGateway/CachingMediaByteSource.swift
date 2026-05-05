import Foundation
import NativeMediaCore

public actor CachingMediaByteSource: MediaByteSource {
    public nonisolated let url: URL
    private let upstream: any MediaByteSource
    private let store: MediaGatewayStore
    private let key: MediaGatewayCacheKey
    private var snapshot = MediaAccessMetrics()

    public init(
        upstream: any MediaByteSource,
        store: MediaGatewayStore,
        key: MediaGatewayCacheKey
    ) {
        self.upstream = upstream
        self.store = store
        self.key = key
        self.url = upstream.url
    }

    public func read(range: ByteRange) async throws -> Data {
        guard range.offset >= 0, range.length > 0 else { throw MediaAccessError.invalidRange(range) }
        if let cached = try await store.read(range: range, key: key) {
            snapshot.currentOffset = range.offset + Int64(cached.count)
            snapshot.bufferedRanges = (try? await store.coveredRanges(key: key)) ?? snapshot.bufferedRanges
            return cached
        }

        let started = Date()
        let data = try await upstream.read(range: range)
        let elapsed = max(Date().timeIntervalSince(started), 0.001)
        try await store.write(range: ByteRange(offset: range.offset, length: data.count), data: data, key: key)
        snapshot.currentOffset = range.offset + Int64(data.count)
        snapshot.bufferedRanges = (try? await store.coveredRanges(key: key)) ?? snapshot.bufferedRanges
        snapshot.readThroughputMbps = Double(data.count * 8) / elapsed / 1_000_000
        snapshot.rangeRequestCount += 1
        return data
    }

    public func size() async throws -> Int64? {
        try await upstream.size()
    }

    public func cancel() async {
        await upstream.cancel()
    }

    public func metrics() async -> MediaAccessMetrics {
        snapshot
    }
}
