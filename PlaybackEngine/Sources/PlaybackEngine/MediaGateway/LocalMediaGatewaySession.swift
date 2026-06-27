import Foundation
import NativeMediaCore

struct LocalMediaGatewayRangeResponse: Sendable {
    let data: Data
    let range: ByteRange
    let totalLength: Int64?
    let contentType: String?
}

struct LocalMediaGatewayStreamingResponse {
    let range: ByteRange
    let totalLength: Int64
    let contentType: String?
    let chunks: AsyncThrowingStream<Data, Error>
}

public actor LocalMediaGatewaySession {
    private static let implicitRangeLength = 4 * 1_024 * 1_024
    private static let coalescedRangeFetchThreshold = 32 * 1_024
    private static let streamChunkLength = 64 * 1_024
    private static let streamCacheWriteLength = 1 * 1_024 * 1_024
    // Each contiguous remote gap inside a streaming response is fetched in one upstream
    // connection of up to this size. It used to be 1 MB, which meant a fresh HTTPS
    // connection per megabyte — dozens of handshakes to a remote server per read, measured
    // at ~1.5 MB/s (below real-time bitrate). Large contiguous fetches restore near-baseline
    // throughput. Open-ended responses still advertise the full remainder; memory stays
    // bounded because AVPlayer closes the connection once its forward buffer is full.
    private static let remoteGapStreamLength = 16 * 1_024 * 1_024
    private static let avFoundationSniffableExtensions: Set<String> = ["m4v", "mov", "mp4"]

    public nonisolated let id: String
    public nonisolated let localPath: String
    private let remoteURL: URL
    private let headers: [String: String]
    private let key: MediaGatewayCacheKey
    private let store: MediaGatewayStore
    private let session: URLSession
    private let rangeSessionConfiguration: URLSessionConfiguration
    private let prefetcher: LocalMediaGatewayPrefetcher?
    private var cachedSize: Int64?
    private var cachedContentType: String?
    private var latestObservedBitrate: Int?
    private var inFlight: [ByteRange: Task<LocalMediaGatewayRangeResponse, Error>] = [:]

    public init(
        remoteURL: URL,
        headers: [String: String],
        key: MediaGatewayCacheKey,
        store: MediaGatewayStore,
        prefetchConfiguration: LocalMediaGatewayPrefetchConfiguration? = nil,
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        let id = UUID().uuidString
        self.id = id
        self.localPath = Self.makeLocalPath(id: id, remoteURL: remoteURL)
        self.remoteURL = remoteURL
        self.headers = headers
        self.key = key
        self.store = store
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: sessionConfiguration)
        self.rangeSessionConfiguration = sessionConfiguration.copy() as? URLSessionConfiguration ?? .ephemeral
        if let prefetchConfiguration {
            self.prefetcher = LocalMediaGatewayPrefetcher(
                remoteURL: remoteURL,
                headers: headers,
                key: key,
                store: store,
                configuration: prefetchConfiguration,
                sessionConfiguration: sessionConfiguration.copy() as? URLSessionConfiguration ?? .ephemeral
            )
        } else {
            self.prefetcher = nil
        }
    }

    public nonisolated func localAssetURL(baseURL: URL) -> URL {
        localPath
            .split(separator: "/")
            .reduce(baseURL) { url, component in
                url.appendingPathComponent(String(component))
            }
    }

    nonisolated func acceptsLocalPath(_ path: String) -> Bool {
        path == localPath || path == "/media/\(id)"
    }

    private static func makeLocalPath(id: String, remoteURL: URL) -> String {
        let pathExtension = remoteURL.pathExtension.lowercased()
        guard avFoundationSniffableExtensions.contains(pathExtension) else {
            return "/media/\(id)"
        }
        return "/media/\(id).\(pathExtension)"
    }

    func streamingResponse(for requestedRange: LocalMediaGatewayRequestedRange?) async throws -> LocalMediaGatewayStreamingResponse? {
        switch requestedRange {
        case .openEnded(let offset):
            return try await streamResponse(offset: offset, requestedLength: nil)
        case .bounded(let range) where range.length > Self.implicitRangeLength:
            guard range.offset >= 0, range.length > 0 else {
                throw MediaAccessError.invalidRange(range)
            }
            return try await streamResponse(offset: range.offset, requestedLength: range.length)
        default:
            return nil
        }
    }

    private func streamResponse(offset: Int64, requestedLength: Int?) async throws -> LocalMediaGatewayStreamingResponse {
        let totalLength = try await size()
        guard let totalLength, offset >= 0, offset < totalLength else {
            throw MediaAccessError.invalidRange(ByteRange(offset: offset, length: 0))
        }
        let contentType = try await contentType()
        // The response must advertise the full requested length (open-ended = the whole
        // remainder) so AVPlayer sees the true resource size; capping it makes AVPlayer
        // report "content range mismatch" (-12939) and refuse to play. Memory stays bounded
        // because the stream is fetched in `remoteGapStreamLength` windows and AVPlayer
        // closes the connection once its forward buffer is full, cancelling the producer.
        let availableLength = totalLength - offset
        let responseLength: Int64
        if let requestedLength {
            responseLength = min(Int64(requestedLength), availableLength)
        } else {
            responseLength = availableLength
        }
        guard responseLength > 0, responseLength <= Int64(Int.max) else {
            throw MediaAccessError.invalidRange(ByteRange(offset: offset, length: 0))
        }
        let requestURL = PlaybackAuthenticatedRequestURL.forInternalURLSession(remoteURL, headers: headers)
        let requestHeaders = headers
        let configuration = rangeSessionConfiguration.copy() as? URLSessionConfiguration ?? .ephemeral
        let responseLengthInt = Int(responseLength)
        let endOffset = requestedLength == nil ? nil : offset + responseLength - 1
        let store = store
        let key = key
        let prefetcher = prefetcher
        let totalLengthForCache = totalLength
        let cachedPrefixLength = try await cachedPrefixLength(offset: offset, maxLength: responseLengthInt)
        let chunks = Self.makeCachedThenRangeStream(
            requestURL: requestURL,
            headers: requestHeaders,
            offset: offset,
            cachedPrefixLength: cachedPrefixLength,
            endOffset: endOffset,
            maxLength: responseLengthInt,
            configuration: configuration,
            store: store,
            key: key,
            onCacheChunk: { [store, key, prefetcher] range, data in
                try await store.write(range: range, data: data, key: key)
                await prefetcher?.schedule(
                    after: range,
                    totalLength: totalLengthForCache,
                    priority: .streamingPlayback
                )
            },
            onProgress: { [weak self] byteCount, elapsedSeconds in
                await self?.recordStreamingFetch(
                    byteCount: byteCount,
                    elapsedSeconds: elapsedSeconds,
                    totalLength: totalLengthForCache
                )
            }
        )
        return LocalMediaGatewayStreamingResponse(
            range: ByteRange(offset: offset, length: responseLengthInt),
            totalLength: totalLength,
            contentType: contentType,
            chunks: chunks
        )
    }

    private func cachedPrefixLength(offset: Int64, maxLength: Int) async throws -> Int {
        guard maxLength > 0 else { return 0 }
        let ranges = try await store.coveredRanges(key: key)
        return Self.contiguousCachedLength(from: ranges, offset: offset, maxLength: maxLength)
    }

    private static func contiguousCachedLength(
        from ranges: [ByteRange],
        offset: Int64,
        maxLength: Int
    ) -> Int {
        guard offset >= 0, maxLength > 0 else { return 0 }
        let targetEnd = offset + Int64(maxLength)
        var cursor = offset
        for range in ranges.sorted(by: { $0.offset < $1.offset }) {
            let rangeEnd = range.offset + Int64(range.length)
            guard rangeEnd > cursor else { continue }
            guard range.offset <= cursor else { break }
            cursor = min(targetEnd, rangeEnd)
            if cursor >= targetEnd { break }
        }
        return max(0, Int(cursor - offset))
    }

    func response(for requestedRange: LocalMediaGatewayRequestedRange?) async throws -> LocalMediaGatewayRangeResponse {
        let range = try await resolveRange(requestedRange)
        if let response = try await cachedResponse(for: range) {
            await prefetcher?.schedule(after: ByteRange(offset: range.offset, length: response.data.count), totalLength: response.totalLength)
            return response
        }
        if let task = inFlight.first(where: { Self.range($0.key, contains: range) })?.value {
            let fetched = try await task.value
            let response = try await response(for: range, from: fetched)
            await prefetcher?.schedule(after: ByteRange(offset: range.offset, length: response.data.count), totalLength: response.totalLength)
            return response
        }
        let fetchRange = try await coalescedFetchRange(for: range)
        let task = Task { try await fetchAndStore(range: fetchRange) }
        inFlight[fetchRange] = task
        defer { inFlight.removeValue(forKey: fetchRange) }
        let fetched = try await task.value
        let response = try await response(for: range, from: fetched)
        await prefetcher?.schedule(after: ByteRange(offset: range.offset, length: response.data.count), totalLength: response.totalLength)
        return response
    }

    private func cachedResponse(for range: ByteRange) async throws -> LocalMediaGatewayRangeResponse? {
        guard let data = try await store.read(range: range, key: key) else { return nil }
        let totalLength: Int64?
        if let cachedSize {
            totalLength = cachedSize
        } else {
            totalLength = try? await size()
        }
        return LocalMediaGatewayRangeResponse(
            data: data,
            range: range,
            totalLength: totalLength,
            contentType: cachedContentType
        )
    }

    private func response(
        for range: ByteRange,
        from fetched: LocalMediaGatewayRangeResponse
    ) async throws -> LocalMediaGatewayRangeResponse {
        if fetched.range == range {
            return fetched
        }
        if let data = Self.slice(range: range, from: fetched) {
            return LocalMediaGatewayRangeResponse(
                data: data,
                range: range,
                totalLength: fetched.totalLength,
                contentType: fetched.contentType
            )
        }
        if let cached = try await cachedResponse(for: range) {
            return cached
        }
        throw MediaAccessError.invalidRange(range)
    }

    private func coalescedFetchRange(for range: ByteRange) async throws -> ByteRange {
        guard range.length >= Self.coalescedRangeFetchThreshold,
              range.length < Self.implicitRangeLength else {
            return range
        }
        let totalLength = try await size()
        return try clampedRange(
            offset: range.offset,
            requestedLength: Self.implicitRangeLength,
            totalLength: totalLength
        )
    }

    private static func range(_ container: ByteRange, contains range: ByteRange) -> Bool {
        let containerEnd = container.offset + Int64(container.length)
        let rangeEnd = range.offset + Int64(range.length)
        return range.offset >= container.offset && rangeEnd <= containerEnd
    }

    private static func slice(
        range: ByteRange,
        from response: LocalMediaGatewayRangeResponse
    ) -> Data? {
        guard Self.range(response.range, contains: range) else { return nil }
        let lower = Int(range.offset - response.range.offset)
        let upper = lower + range.length
        guard lower >= 0, upper <= response.data.count else { return nil }
        return Data(response.data[lower..<upper])
    }

    private func resolveRange(_ requestedRange: LocalMediaGatewayRequestedRange?) async throws -> ByteRange {
        switch requestedRange {
        case .bounded(let range):
            guard range.offset >= 0, range.length > 0 else {
                throw MediaAccessError.invalidRange(range)
            }
            let totalLength = try await size()
            if let totalLength, range.offset >= totalLength {
                throw MediaAccessError.invalidRange(range)
            }
            return try clampedRange(offset: range.offset, requestedLength: range.length, totalLength: totalLength)
        case .openEnded(let offset):
            return try await boundedImplicitRange(offset: offset)
        case .suffix(let length):
            let totalLength = try await size()
            guard let totalLength else {
                return ByteRange(offset: 0, length: min(length, Self.implicitRangeLength))
            }
            let boundedLength = min(length, Self.implicitRangeLength, Int(totalLength))
            guard boundedLength > 0 else {
                throw MediaAccessError.invalidRange(ByteRange(offset: 0, length: 0))
            }
            return ByteRange(offset: max(0, totalLength - Int64(boundedLength)), length: boundedLength)
        case .none:
            return try await boundedImplicitRange(offset: 0)
        }
    }

    private func clampedRange(offset: Int64, requestedLength: Int, totalLength: Int64?) throws -> ByteRange {
        let availableLength = totalLength.map { max(0, $0 - offset) } ?? Int64(requestedLength)
        let length = Int(min(Int64(Self.implicitRangeLength), Int64(requestedLength), availableLength))
        guard length > 0 else {
            throw MediaAccessError.invalidRange(ByteRange(offset: offset, length: 0))
        }
        return ByteRange(offset: offset, length: length)
    }

    private func boundedImplicitRange(offset: Int64) async throws -> ByteRange {
        let totalLength = try await size()
        let remaining = totalLength.map { max(0, $0 - offset) } ?? Int64(Self.implicitRangeLength)
        let length = Int(min(Int64(Self.implicitRangeLength), remaining))
        guard length > 0 else {
            throw MediaAccessError.invalidRange(ByteRange(offset: offset, length: 0))
        }
        return ByteRange(offset: offset, length: length)
    }

    func size() async throws -> Int64? {
        if let cachedSize { return cachedSize }
        var request = URLRequest(url: PlaybackAuthenticatedRequestURL.forInternalURLSession(remoteURL, headers: headers))
        request.httpMethod = "HEAD"
        applyHeaders(to: &request)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        cachedSize = http.mediaGatewayContentLength
        cachedContentType = http.value(forHTTPHeaderField: "Content-Type") ?? cachedContentType
        return cachedSize
    }

    func contentType() async throws -> String? {
        if let cachedContentType { return cachedContentType }
        _ = try await size()
        return cachedContentType
    }

    public func diagnostics() async -> LocalMediaGatewayDiagnostics {
        let coveredRanges = (try? await store.coveredRanges(key: key)) ?? []
        let nonZeroRanges = coveredRanges.filter { $0.offset > 0 }
        let latestNonZeroRange = nonZeroRanges.max { $0.offset < $1.offset }
        let largestNonZeroRange = nonZeroRanges.max { $0.length < $1.length }
        let prefetchSnapshot = await prefetcher?.diagnosticsSnapshot()
        return LocalMediaGatewayDiagnostics(
            contentType: cachedContentType,
            totalLength: cachedSize,
            observedBitrate: max(latestObservedBitrate ?? 0, prefetchSnapshot?.observedBitrate ?? 0),
            cachedBytes: coveredRanges.reduce(0) { $0 + Int64($1.length) },
            largestNonZeroCachedOffset: largestNonZeroRange?.offset,
            largestNonZeroCachedRangeLength: largestNonZeroRange.map { Int64($0.length) },
            latestNonZeroCachedOffset: latestNonZeroRange?.offset,
            latestNonZeroCachedRangeLength: latestNonZeroRange.map { Int64($0.length) },
            nonZeroCachedRanges: nonZeroRanges.map {
                LocalMediaGatewayCachedRange(offset: $0.offset, length: Int64($0.length))
            },
            activePrefetchStartOffset: prefetchSnapshot?.activeStartOffset,
            activePrefetchEndOffset: prefetchSnapshot?.activeEndOffset,
            activePrefetchIsStreamingPlayback: prefetchSnapshot?.activePriority == .streamingPlayback
        )
    }

    public func cancel() async {
        session.invalidateAndCancel()
        await prefetcher?.cancel()
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
    }

    private func fetchAndStore(range: ByteRange) async throws -> LocalMediaGatewayRangeResponse {
        let start = Date()
        var request = URLRequest(url: PlaybackAuthenticatedRequestURL.forInternalURLSession(remoteURL, headers: headers))
        request.httpMethod = "GET"
        request.setValue(Self.upstreamRangeHeader(for: range), forHTTPHeaderField: "Range")
        applyHeaders(to: &request)
        // Bulk chunked read instead of byte-by-byte AsyncBytes iteration. Bounded to
        // range.length, so an open-ended upstream request stops once the window is filled.
        let (payload, http) = try await HTTPChunkedRangeReader.collect(
            request: request,
            configuration: rangeSessionConfiguration.copy() as? URLSessionConfiguration ?? .ephemeral,
            maxLength: range.length
        )
        guard http.statusCode == 206 || http.statusCode == 200 else {
            throw MediaAccessError.httpStatus(http.statusCode)
        }
        guard http.statusCode == 206 || range.offset == 0 else {
            throw MediaAccessError.httpStatus(http.statusCode)
        }
        if let total = http.mediaGatewayContentRangeTotal ?? http.mediaGatewayContentLength {
            cachedSize = total
        }
        cachedContentType = http.value(forHTTPHeaderField: "Content-Type") ?? cachedContentType
        try await store.write(range: ByteRange(offset: range.offset, length: payload.count), data: payload, key: key)
        let elapsed = Date().timeIntervalSince(start)
        if elapsed > 0 {
            latestObservedBitrate = max(latestObservedBitrate ?? 0, Int(Double(payload.count * 8) / elapsed))
        }
        await prefetcher?.recordRemoteFetch(
            byteCount: payload.count,
            elapsedSeconds: elapsed,
            totalLength: cachedSize
        )
        return LocalMediaGatewayRangeResponse(
            data: payload,
            range: ByteRange(offset: range.offset, length: payload.count),
            totalLength: cachedSize,
            contentType: cachedContentType
        )
    }

    private func recordStreamingFetch(
        byteCount: Int,
        elapsedSeconds: TimeInterval,
        totalLength: Int64?
    ) {
        cachedSize = totalLength ?? cachedSize
        if elapsedSeconds > 0 {
            latestObservedBitrate = max(latestObservedBitrate ?? 0, Int(Double(byteCount * 8) / elapsedSeconds))
        }
    }

    private func applyHeaders(to request: inout URLRequest) {
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private static func upstreamRangeHeader(for range: ByteRange) -> String {
        if range.offset > 0 {
            return "bytes=\(range.offset)-"
        }
        return "bytes=0-\(Int64(range.length) - 1)"
    }

    private static func makeRangeStream(
        requestURL: URL,
        headers: [String: String],
        offset: Int64,
        endOffset: Int64?,
        maxLength: Int,
        configuration: URLSessionConfiguration,
        onCacheChunk: @escaping @Sendable (ByteRange, Data) async throws -> Void,
        onProgress: @escaping @Sendable (Int, TimeInterval) async -> Void
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: requestURL)
                    request.httpMethod = "GET"
                    let rangeHeader = Self.upstreamStreamingRangeHeader(offset: offset, endOffset: endOffset)
                    request.setValue(rangeHeader, forHTTPHeaderField: "Range")
                    headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
                    let startedAt = Date()
                    // Bulk chunked read (not byte-by-byte). Bounded to maxLength (the gap
                    // window, <= 1 MB), which also caps an open-ended upstream response so
                    // it cannot pull more than the current window into memory.
                    let (data, http) = try await HTTPChunkedRangeReader.collect(
                        request: request,
                        configuration: configuration,
                        maxLength: maxLength
                    )
                    guard http.statusCode == 206 || (offset == 0 && http.statusCode == 200) else {
                        throw MediaAccessError.httpStatus(http.statusCode)
                    }
                    try await emitAndCache(
                        data: data,
                        offset: offset,
                        continuation: continuation,
                        onCacheChunk: onCacheChunk
                    )
                    await onProgress(data.count, max(0.001, Date().timeIntervalSince(startedAt)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Persists a fully-fetched window to the cache, then yields it to the player in
    /// stream-sized chunks. Replaces the former byte-by-byte streaming loop.
    ///
    /// Caching happens *before* emitting: the window is already entirely in memory, and a
    /// consumer (the HTTP server) that stops reading the moment it has enough cancels this
    /// producer task. If we emitted first and cached afterwards, that cancellation would
    /// interrupt the cache writes and leave a partially-cached window. Writing to the cache
    /// up front guarantees the cached range matches what the player received.
    private static func emitAndCache(
        data: Data,
        offset: Int64,
        continuation: AsyncThrowingStream<Data, Error>.Continuation,
        onCacheChunk: @escaping @Sendable (ByteRange, Data) async throws -> Void
    ) async throws {
        guard !data.isEmpty else { return }
        var cacheCursor = 0
        var cacheOffset = offset
        while cacheCursor < data.count {
            let end = min(cacheCursor + streamCacheWriteLength, data.count)
            let block = data.subdata(in: cacheCursor..<end)
            try await onCacheChunk(ByteRange(offset: cacheOffset, length: block.count), block)
            cacheOffset += Int64(block.count)
            cacheCursor = end
        }
        var emitCursor = 0
        while emitCursor < data.count {
            let end = min(emitCursor + streamChunkLength, data.count)
            continuation.yield(data.subdata(in: emitCursor..<end))
            emitCursor = end
        }
    }

    private static func makeCachedThenRangeStream(
        requestURL: URL,
        headers: [String: String],
        offset: Int64,
        cachedPrefixLength: Int,
        endOffset: Int64?,
        maxLength: Int,
        configuration: URLSessionConfiguration,
        store: MediaGatewayStore,
        key: MediaGatewayCacheKey,
        onCacheChunk: @escaping @Sendable (ByteRange, Data) async throws -> Void,
        onProgress: @escaping @Sendable (Int, TimeInterval) async -> Void
    ) -> AsyncThrowingStream<Data, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var cursor = offset
                    var remainingLength = maxLength
                    var cachedPrefixLength = min(max(cachedPrefixLength, 0), maxLength)

                    while remainingLength > 0, !Task.isCancelled {
                        let ranges = try await store.coveredRanges(key: key)
                        let cachedLength = cachedPrefixLength > 0
                            ? cachedPrefixLength
                            : contiguousCachedLength(
                                from: ranges,
                                offset: cursor,
                                maxLength: remainingLength
                            )
                        cachedPrefixLength = 0

                        if cachedLength > 0 {
                            try await emitCachedPrefix(
                                offset: cursor,
                                length: cachedLength,
                                store: store,
                                key: key,
                                continuation: continuation
                            )
                            cursor += Int64(cachedLength)
                            remainingLength -= cachedLength
                            continue
                        }

                        let remoteLength = remoteGapLength(
                            from: ranges,
                            offset: cursor,
                            remainingLength: remainingLength
                        )
                        let remoteOffset = cursor
                        let remoteEndOffset = min(
                            endOffset ?? (remoteOffset + Int64(remoteLength) - 1),
                            remoteOffset + Int64(remoteLength) - 1
                        )
                        let remoteStream = makeRangeStream(
                            requestURL: requestURL,
                            headers: headers,
                            offset: remoteOffset,
                            endOffset: remoteEndOffset,
                            maxLength: remoteLength,
                            configuration: configuration,
                            onCacheChunk: onCacheChunk,
                            onProgress: onProgress
                        )
                        var emittedRemoteBytes = 0
                        for try await chunk in remoteStream {
                            emittedRemoteBytes += chunk.count
                            continuation.yield(chunk)
                        }
                        guard emittedRemoteBytes > 0 else {
                            throw MediaAccessError.invalidRange(ByteRange(offset: remoteOffset, length: remoteLength))
                        }
                        cursor += Int64(emittedRemoteBytes)
                        remainingLength -= emittedRemoteBytes
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func remoteGapLength(
        from ranges: [ByteRange],
        offset: Int64,
        remainingLength: Int
    ) -> Int {
        let defaultLength = min(Self.remoteGapStreamLength, remainingLength)
        let nextCachedOffset = ranges
            .filter { $0.offset > offset }
            .map(\.offset)
            .min()
        guard let nextCachedOffset else { return defaultLength }

        let gapLength = nextCachedOffset - offset
        guard gapLength > 0 else { return defaultLength }
        return max(1, min(defaultLength, Int(min(Int64(Int.max), gapLength))))
    }

    private static func emitCachedPrefix(
        offset: Int64,
        length: Int,
        store: MediaGatewayStore,
        key: MediaGatewayCacheKey,
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) async throws {
        var cursor = offset
        var remaining = length
        while remaining > 0 {
            let chunkLength = min(streamChunkLength, remaining)
            let range = ByteRange(offset: cursor, length: chunkLength)
            guard let data = try await store.read(range: range, key: key) else {
                throw MediaAccessError.invalidRange(range)
            }
            continuation.yield(data)
            cursor += Int64(data.count)
            remaining -= data.count
        }
    }

    private static func upstreamStreamingRangeHeader(offset: Int64, endOffset: Int64?) -> String {
        if offset > 0 {
            return "bytes=\(offset)-"
        }
        if let endOffset {
            return "bytes=0-\(endOffset)"
        }
        return "bytes=0-"
    }

}

public struct LocalMediaGatewayCachedRange: Sendable, Equatable {
    public let offset: Int64
    public let length: Int64

    public init(offset: Int64, length: Int64) {
        self.offset = offset
        self.length = length
    }
}

public struct LocalMediaGatewayDiagnostics: Sendable, Equatable {
    public let contentType: String?
    public let totalLength: Int64?
    public let observedBitrate: Int?
    public let cachedBytes: Int64?
    public let largestNonZeroCachedOffset: Int64?
    public let largestNonZeroCachedRangeLength: Int64?
    public let latestNonZeroCachedOffset: Int64?
    public let latestNonZeroCachedRangeLength: Int64?
    public let nonZeroCachedRanges: [LocalMediaGatewayCachedRange]
    public let activePrefetchStartOffset: Int64?
    public let activePrefetchEndOffset: Int64?
    public let activePrefetchIsStreamingPlayback: Bool

    public init(
        contentType: String?,
        totalLength: Int64?,
        observedBitrate: Int?,
        cachedBytes: Int64?,
        largestNonZeroCachedOffset: Int64?,
        largestNonZeroCachedRangeLength: Int64?,
        latestNonZeroCachedOffset: Int64?,
        latestNonZeroCachedRangeLength: Int64?,
        nonZeroCachedRanges: [LocalMediaGatewayCachedRange] = [],
        activePrefetchStartOffset: Int64? = nil,
        activePrefetchEndOffset: Int64? = nil,
        activePrefetchIsStreamingPlayback: Bool = false
    ) {
        self.contentType = contentType
        self.totalLength = totalLength
        self.observedBitrate = observedBitrate
        self.cachedBytes = cachedBytes
        self.largestNonZeroCachedOffset = largestNonZeroCachedOffset
        self.largestNonZeroCachedRangeLength = largestNonZeroCachedRangeLength
        self.latestNonZeroCachedOffset = latestNonZeroCachedOffset
        self.latestNonZeroCachedRangeLength = latestNonZeroCachedRangeLength
        self.nonZeroCachedRanges = nonZeroCachedRanges
        self.activePrefetchStartOffset = activePrefetchStartOffset
        self.activePrefetchEndOffset = activePrefetchEndOffset
        self.activePrefetchIsStreamingPlayback = activePrefetchIsStreamingPlayback
    }
}
