import Foundation

public actor HTTPRangeByteSource: MediaByteSource {
    public struct Configuration: Sendable {
        public var timeout: TimeInterval
        public var maxRetries: Int
        public var cacheWindowBytes: Int

        public init(timeout: TimeInterval = 30, maxRetries: Int = 2, cacheWindowBytes: Int = 32 * 1024 * 1024) {
            self.timeout = timeout
            self.maxRetries = maxRetries
            self.cacheWindowBytes = cacheWindowBytes
        }
    }

    public nonisolated let url: URL
    private let headers: [String: String]
    private let rangeStreamer: StreamingRangeWriter
    private let configuration: Configuration
    private var cachedSize: Int64?
    private var cache: [ByteRange: Data] = [:]
    private var cacheWindow: MediaCacheWindow
    private var snapshot = MediaAccessMetrics()

    public init(
        url: URL,
        headers: [String: String] = [:],
        configuration: Configuration = Configuration(),
        sessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.url = url
        self.headers = headers
        self.configuration = configuration
        self.cacheWindow = MediaCacheWindow(maximumBytes: configuration.cacheWindowBytes)
        sessionConfiguration.timeoutIntervalForRequest = configuration.timeout
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.rangeStreamer = StreamingRangeWriter(configuration: sessionConfiguration)
    }

    public func read(range: ByteRange) async throws -> Data {
        guard range.offset >= 0, range.length > 0 else { throw MediaAccessError.invalidRange(range) }
        if let cached = cache[range] {
            snapshot.currentOffset = range.offset + Int64(cached.count)
            return cached
        }
        let started = Date()
        let data = try await retrying { try await self.fetch(range: range) }
        let elapsed = max(Date().timeIntervalSince(started), 0.001)
        cache[range] = data
        cacheWindow.record(ByteRange(offset: range.offset, length: data.count))
        snapshot.bufferedRanges = cacheWindow.ranges
        snapshot.currentOffset = range.offset + Int64(data.count)
        snapshot.readThroughputMbps = Double(data.count * 8) / elapsed / 1_000_000
        return data
    }

    public func size() async throws -> Int64? {
        if let cachedSize { return cachedSize }
        if url.isFileURL {
            let size = try fileSize()
            cachedSize = size
            return size
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        applyHeaders(to: &request)
        let stream = rangeStreamer.stream(
            request: request,
            startOffset: 0,
            minSubBlock: 1,
            maximumResponseBytes: 1
        )
        for try await _ in stream {}
        if let size = rangeStreamer.resourceSize() {
            cachedSize = size
            return size
        }
        return nil
    }

    public func cancel() async {
        rangeStreamer.invalidate()
    }

    public func metrics() async -> MediaAccessMetrics {
        snapshot
    }

    private func fetch(range: ByteRange) async throws -> Data {
        if url.isFileURL {
            return try readFile(range: range)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=\(range.offset)-\(range.offset + Int64(range.length) - 1)", forHTTPHeaderField: "Range")
        applyHeaders(to: &request)
        snapshot.rangeRequestCount += 1
        // The reusable streamer keeps one URLSession for the whole native playback. Closed 206
        // ranges complete normally and return their connection to the pool; an ignored range
        // (200 at offset zero) is still hard-capped so a multi-GB original can never be buffered.
        let stream = rangeStreamer.stream(
            request: request,
            startOffset: range.offset,
            minSubBlock: min(range.length, 256 * 1_024),
            maximumResponseBytes: range.length
        )
        var data = Data()
        data.reserveCapacity(min(range.length, 8 * 1_024 * 1_024))
        for try await block in stream {
            let remaining = range.length - data.count
            guard remaining > 0 else { continue }
            if block.data.count <= remaining {
                data.append(block.data)
            } else {
                data.append(block.data.prefix(remaining))
            }
        }
        if let size = rangeStreamer.resourceSize() {
            cachedSize = size
        }
        return data
    }

    private func retrying(_ operation: () async throws -> Data) async throws -> Data {
        var lastError: Error?
        for attempt in 0...configuration.maxRetries {
            do {
                return try await operation()
            } catch is CancellationError {
                throw MediaAccessError.cancelled
            } catch {
                lastError = error
                if attempt < configuration.maxRetries {
                    snapshot.retryCount += 1
                    try await Task.sleep(nanoseconds: 120_000_000 * UInt64(attempt + 1))
                }
            }
        }
        throw lastError ?? MediaAccessError.cancelled
    }

    private func applyHeaders(to request: inout URLRequest) {
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func readFile(range: ByteRange) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(range.offset))
        return try handle.read(upToCount: range.length) ?? Data()
    }

    private func fileSize() throws -> Int64? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    }
}
