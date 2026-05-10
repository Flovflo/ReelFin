import Foundation
import NativeMediaCore

struct LocalMediaGatewayRangeResponse: Sendable {
    let data: Data
    let range: ByteRange
    let totalLength: Int64?
    let contentType: String?
}

public actor LocalMediaGatewaySession {
    private static let implicitRangeLength = 4 * 1_024 * 1_024

    public nonisolated let id: String
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
        self.id = UUID().uuidString
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

    public func localAssetURL(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("media").appendingPathComponent(id)
    }

    func response(for requestedRange: LocalMediaGatewayRequestedRange?) async throws -> LocalMediaGatewayRangeResponse {
        let range = try await resolveRange(requestedRange)
        if let data = try await store.read(range: range, key: key) {
            let totalLength: Int64?
            if let cachedSize {
                totalLength = cachedSize
            } else {
                totalLength = try? await size()
            }
            let response = LocalMediaGatewayRangeResponse(
                data: data,
                range: range,
                totalLength: totalLength,
                contentType: cachedContentType
            )
            await prefetcher?.schedule(after: ByteRange(offset: range.offset, length: data.count), totalLength: totalLength)
            return response
        }
        if let task = inFlight[range] {
            let response = try await task.value
            await prefetcher?.schedule(after: ByteRange(offset: range.offset, length: response.data.count), totalLength: response.totalLength)
            return response
        }
        let task = Task { try await fetchAndStore(range: range) }
        inFlight[range] = task
        defer { inFlight.removeValue(forKey: range) }
        let response = try await task.value
        await prefetcher?.schedule(after: ByteRange(offset: range.offset, length: response.data.count), totalLength: response.totalLength)
        return response
    }

    private func resolveRange(_ requestedRange: LocalMediaGatewayRequestedRange?) async throws -> ByteRange {
        switch requestedRange {
        case .bounded(let range):
            if let totalLength = try await size(), range.offset >= totalLength {
                throw MediaAccessError.invalidRange(range)
            }
            return range
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
        LocalMediaGatewayDiagnostics(
            contentType: cachedContentType,
            totalLength: cachedSize,
            observedBitrate: latestObservedBitrate
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
        let rangeSession = URLSession(configuration: rangeSessionConfiguration)
        defer { rangeSession.invalidateAndCancel() }
        var request = URLRequest(url: PlaybackAuthenticatedRequestURL.forInternalURLSession(remoteURL, headers: headers))
        request.httpMethod = "GET"
        request.setValue("bytes=\(range.offset)-\(range.offset + Int64(range.length) - 1)", forHTTPHeaderField: "Range")
        applyHeaders(to: &request)
        let (bytes, response) = try await rangeSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw MediaAccessError.nonHTTPResponse }
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
        let payload = try await readPrefix(from: bytes, maxLength: range.length)
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

    private func readPrefix(from bytes: URLSession.AsyncBytes, maxLength: Int) async throws -> Data {
        var payload = Data()
        payload.reserveCapacity(maxLength)
        for try await byte in bytes {
            payload.append(byte)
            if payload.count >= maxLength {
                break
            }
        }
        return payload
    }

    private func applyHeaders(to request: inout URLRequest) {
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }
}

public struct LocalMediaGatewayDiagnostics: Sendable, Equatable {
    public let contentType: String?
    public let totalLength: Int64?
    public let observedBitrate: Int?
}
