import Foundation
import NativeMediaCore

struct LocalMediaGatewayRangeResponse: Sendable {
    let data: Data
    let totalLength: Int64?
}

public actor LocalMediaGatewaySession {
    public nonisolated let id: String
    private let remoteURL: URL
    private let headers: [String: String]
    private let key: MediaGatewayCacheKey
    private let store: MediaGatewayStore
    private let session: URLSession
    private let prefetcher: LocalMediaGatewayPrefetcher?
    private var cachedSize: Int64?
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

    func response(for range: ByteRange) async throws -> LocalMediaGatewayRangeResponse {
        if let data = try await store.read(range: range, key: key) {
            let response = LocalMediaGatewayRangeResponse(data: data, totalLength: cachedSize)
            await prefetcher?.schedule(after: ByteRange(offset: range.offset, length: data.count), totalLength: cachedSize)
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

    func size() async throws -> Int64? {
        if let cachedSize { return cachedSize }
        var request = URLRequest(url: PlaybackAuthenticatedRequestURL.forInternalURLSession(remoteURL, headers: headers))
        request.httpMethod = "HEAD"
        applyHeaders(to: &request)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        cachedSize = http.mediaGatewayContentLength
        return cachedSize
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
        request.setValue("bytes=\(range.offset)-\(range.offset + Int64(range.length) - 1)", forHTTPHeaderField: "Range")
        applyHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MediaAccessError.nonHTTPResponse }
        guard http.statusCode == 206 || http.statusCode == 200 else {
            throw MediaAccessError.httpStatus(http.statusCode)
        }
        if let total = http.mediaGatewayContentRangeTotal ?? http.mediaGatewayContentLength {
            cachedSize = total
        }
        let payload = slicedPayload(data, for: range, statusCode: http.statusCode)
        try await store.write(range: ByteRange(offset: range.offset, length: payload.count), data: payload, key: key)
        await prefetcher?.recordRemoteFetch(
            byteCount: payload.count,
            elapsedSeconds: Date().timeIntervalSince(start),
            totalLength: cachedSize
        )
        return LocalMediaGatewayRangeResponse(data: payload, totalLength: cachedSize)
    }

    private func slicedPayload(_ data: Data, for range: ByteRange, statusCode: Int) -> Data {
        guard statusCode == 200, data.count > range.length else { return data }
        return Data(data.prefix(range.length))
    }

    private func applyHeaders(to request: inout URLRequest) {
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }
}
