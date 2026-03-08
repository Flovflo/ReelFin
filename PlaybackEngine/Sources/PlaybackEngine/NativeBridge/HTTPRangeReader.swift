import Foundation
import Shared

/// Actor-based HTTP range reader with an LRU chunk cache for streaming
/// large media files without downloading them fully.
///
/// Design goals:
/// - Bounded memory: `maxCacheSize` controls total cached bytes (LRU eviction).
/// - Parallel prefetch: caller can request multiple regions simultaneously.
/// - Retry with exponential backoff + jitter for transient errors.
/// - Token auth via header injection (no token in URLs/logs).
public actor HTTPRangeReader {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public var chunkSize: Int            // Bytes per range request (default 512 KB)
        public var maxCacheSize: Int         // Max total cached bytes (default 32 MB)
        public var maxRetries: Int           // Per-request retry limit
        public var baseRetryDelayMs: Int     // Initial retry delay
        public var timeoutInterval: TimeInterval
        public var maxConcurrentRequests: Int
        public var readAheadChunks: Int

        public static let `default` = Configuration(
            chunkSize: 512 * 1024,
            maxCacheSize: 32 * 1024 * 1024,
            maxRetries: 3,
            baseRetryDelayMs: 200,
            timeoutInterval: 30,
            maxConcurrentRequests: 4,
            readAheadChunks: 1
        )

        public init(
            chunkSize: Int = 512 * 1024,
            maxCacheSize: Int = 32 * 1024 * 1024,
            maxRetries: Int = 3,
            baseRetryDelayMs: Int = 200,
            timeoutInterval: TimeInterval = 30,
            maxConcurrentRequests: Int = 4,
            readAheadChunks: Int = 1
        ) {
            self.chunkSize = chunkSize
            self.maxCacheSize = maxCacheSize
            self.maxRetries = maxRetries
            self.baseRetryDelayMs = baseRetryDelayMs
            self.timeoutInterval = timeoutInterval
            self.maxConcurrentRequests = maxConcurrentRequests
            self.readAheadChunks = max(0, readAheadChunks)
        }
    }

    // MARK: - State

    private let url: URL
    private let headers: [String: String]
    private let config: Configuration
    private let session: URLSession

    private var cache: [Int64: CacheEntry] = [:]  // Key = chunk-aligned offset
    private var cacheOrder: [Int64] = []            // LRU order (most recent at end)
    private var currentCacheSize: Int = 0
    private var totalFileSize: Int64?
    private var pendingRequests: [Int64: Task<Data, Error>] = [:]

    // Metrics
    private var _metrics = HTTPRangeReaderMetrics()

    private struct CacheEntry {
        let offset: Int64
        let data: Data
    }

    // MARK: - Init

    public init(
        url: URL,
        headers: [String: String] = [:],
        config: Configuration = .default,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) {
        self.url = url
        self.headers = headers
        self.config = config

        let sessionConfig = sessionConfiguration ?? URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeoutInterval
        sessionConfig.httpMaximumConnectionsPerHost = config.maxConcurrentRequests
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Public API

    /// Read `length` bytes starting at `offset`. May return less if at EOF.
    public func read(offset: Int64, length: Int) async throws -> Data {
        // Determine which chunks cover the requested range
        let chunkSize = Int64(config.chunkSize)
        let startChunk = (offset / chunkSize) * chunkSize
        let endByte = offset + Int64(length) - 1
        let endChunk = (endByte / chunkSize) * chunkSize

        var result = Data()

        var chunkOffset = startChunk
        while chunkOffset <= endChunk {
            let chunkData = try await fetchChunk(at: chunkOffset)

            // Calculate the slice within this chunk
            let chunkStart = chunkOffset
            let relativeStart = max(0, Int(offset - chunkStart))
            let relativeEnd = min(chunkData.count, Int(offset + Int64(length) - chunkStart))

            if relativeStart < relativeEnd {
                result.append(chunkData[relativeStart..<relativeEnd])
            }

            chunkOffset += chunkSize
        }

        if config.readAheadChunks > 0 {
            for distance in 1...config.readAheadChunks {
                let nextChunk = endChunk + Int64(distance) * chunkSize
                Task { [self] in
                    _ = try? await fetchChunk(at: nextChunk)
                }
            }
        }

        return result
    }

    /// Prefetch multiple byte regions in parallel (e.g. init + first cluster).
    public func prefetch(ranges: [(offset: Int64, length: Int)]) async {
        await withTaskGroup(of: Void.self) { group in
            for range in ranges {
                group.addTask { [self] in
                    _ = try? await self.read(offset: range.offset, length: range.length)
                }
            }
        }
    }

    /// Get the total file size (fetched via HEAD or first range response).
    public func fileSize() async throws -> Int64 {
        if let cached = totalFileSize { return cached }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = config.timeoutInterval

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NativeBridgeError.httpError(statusCode: 0, message: "Non-HTTP response")
        }

        if let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
           let size = Int64(contentLength) {
            totalFileSize = size
            return size
        }

        // Fallback: try a range request for 0-0
        let probeData = try await fetchRemote(offset: 0, length: 1)
        _ = probeData
        if let size = totalFileSize { return size }

        throw NativeBridgeError.httpError(statusCode: http.statusCode, message: "Cannot determine file size")
    }

    /// Invalidate the cache and cancel pending requests.
    public func invalidate() {
        for (_, task) in pendingRequests {
            task.cancel()
        }
        pendingRequests.removeAll()
        session.invalidateAndCancel()
        cache.removeAll()
        cacheOrder.removeAll()
        currentCacheSize = 0
    }

    /// Current metrics snapshot.
    public var metrics: HTTPRangeReaderMetrics { _metrics }

    // MARK: - Chunk Fetch

    private func fetchChunk(at offset: Int64) async throws -> Data {
        // Check cache
        if let entry = cache[offset] {
            touchLRU(offset)
            _metrics.cacheHitCount += 1
            return entry.data
        }

        let task: Task<Data, Error>
        let ownsTask: Bool
        if let pending = pendingRequests[offset] {
            task = pending
            ownsTask = false
        } else {
            task = Task<Data, Error> {
                try await fetchRemote(offset: offset, length: config.chunkSize)
            }
            pendingRequests[offset] = task
            ownsTask = true
        }

        do {
            let data = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                if ownsTask {
                    task.cancel()
                }
            }

            if ownsTask {
                pendingRequests.removeValue(forKey: offset)
            }

            // Store in cache
            storeInCache(offset: offset, data: data)
            _metrics.cacheHitCount -= 1  // Will be counted as miss below
            _metrics.cacheMissCount += 1
            return data
        } catch {
            if ownsTask {
                pendingRequests.removeValue(forKey: offset)
            }
            throw error
        }
    }

    // MARK: - HTTP Range Request with Retry

    private func fetchRemote(offset: Int64, length: Int) async throws -> Data {
        var lastError: Error = NativeBridgeError.httpError(statusCode: 0, message: "No attempts made")

        for attempt in 0..<config.maxRetries {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                let endByte = offset + Int64(length) - 1
                request.setValue("bytes=\(offset)-\(endByte)", forHTTPHeaderField: "Range")
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
                request.timeoutInterval = config.timeoutInterval

                _metrics.rangeRequestCount += 1

                let (data, response) = try await performData(for: request)
                try Task.checkCancellation()

                guard let http = response as? HTTPURLResponse else {
                    throw NativeBridgeError.httpError(statusCode: 0, message: "Non-HTTP response")
                }

                // Parse Content-Range for total size: "bytes 0-1023/12345678"
                if totalFileSize == nil,
                   let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
                   let slashIndex = contentRange.lastIndex(of: "/") {
                    let sizeStr = contentRange[contentRange.index(after: slashIndex)...]
                    if let size = Int64(sizeStr), size > 0 {
                        totalFileSize = size
                    }
                }

                if http.statusCode == 206 || http.statusCode == 200 {
                    return data
                }

                if (500...504).contains(http.statusCode) {
                    throw NativeBridgeError.httpError(statusCode: http.statusCode, message: "Server error")
                }

                throw NativeBridgeError.httpError(
                    statusCode: http.statusCode,
                    message: "Unexpected status"
                )
            } catch is CancellationError {
                _metrics.cancelledRequestCount += 1
                throw NativeBridgeError.cancelled
            } catch {
                lastError = error

                if attempt < config.maxRetries - 1 {
                    let baseDelay = config.baseRetryDelayMs * (1 << attempt)
                    let jitter = Int.random(in: 0...baseDelay / 2)
                    let delayMs = baseDelay + jitter
                    _metrics.retryCount += 1
                    AppLog.playback.warning(
                        "Range request retry \(attempt + 1)/\(self.config.maxRetries) after \(delayMs)ms"
                    )
                    try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                }
            }
        }

        throw lastError
    }

    // MARK: - LRU Cache Management

    private func storeInCache(offset: Int64, data: Data) {
        // Evict until we have room
        while currentCacheSize + data.count > config.maxCacheSize, !cacheOrder.isEmpty {
            let evictOffset = cacheOrder.removeFirst()
            if let evicted = cache.removeValue(forKey: evictOffset) {
                currentCacheSize -= evicted.data.count
            }
        }

        cache[offset] = CacheEntry(offset: offset, data: data)
        cacheOrder.append(offset)
        currentCacheSize += data.count
    }

    private func touchLRU(_ offset: Int64) {
        cacheOrder.removeAll(where: { $0 == offset })
        cacheOrder.append(offset)
    }

    private func performData(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw error
        }
    }
}

// MARK: - Metrics

public struct HTTPRangeReaderMetrics: Sendable {
    public var cacheHitCount: Int = 0
    public var cacheMissCount: Int = 0
    public var rangeRequestCount: Int = 0
    public var retryCount: Int = 0
    public var cancelledRequestCount: Int = 0
}
