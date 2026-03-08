@testable import PlaybackEngine
import Foundation
import XCTest

final class HTTPRangeReaderTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockRangeURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(MockRangeURLProtocol.self)
        super.tearDown()
    }

    func testRangeReadAndFileSizeInference() async throws {
        let payload = Data((0..<4096).map { UInt8($0 % 255) })
        MockRangeURLProtocol.storage = payload
        MockRangeURLProtocol.delayNanos = 0

        let reader = HTTPRangeReader(
            url: URL(string: "https://example.com/video.mkv")!,
            headers: [:],
            config: .init(chunkSize: 512, maxCacheSize: 4096, maxRetries: 2, baseRetryDelayMs: 10, timeoutInterval: 5, maxConcurrentRequests: 2, readAheadChunks: 0),
            sessionConfiguration: makeMockSessionConfiguration()
        )

        let data = try await reader.read(offset: 300, length: 200)
        XCTAssertEqual(data.count, 200)
        XCTAssertEqual(data.first, payload[300])
        XCTAssertEqual(data.last, payload[499])

        let size = try await reader.fileSize()
        XCTAssertEqual(size, Int64(payload.count))
    }

    func testCancellationCancelsInFlightRequest() async throws {
        let payload = Data((0..<1_000_000).map { UInt8($0 % 255) })
        MockRangeURLProtocol.storage = payload
        MockRangeURLProtocol.delayNanos = 700_000_000

        let reader = HTTPRangeReader(
            url: URL(string: "https://example.com/slow.mkv")!,
            headers: [:],
            config: .init(chunkSize: 256 * 1024, maxCacheSize: 2 * 256 * 1024, maxRetries: 1, baseRetryDelayMs: 10, timeoutInterval: 5, maxConcurrentRequests: 1, readAheadChunks: 0),
            sessionConfiguration: makeMockSessionConfiguration()
        )

        let task = Task {
            try await reader.read(offset: 0, length: 256 * 1024)
        }
        try? await Task.sleep(nanoseconds: 80_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            guard case NativeBridgeError.cancelled = error else {
                XCTFail("Expected NativeBridgeError.cancelled, got \(error)")
                return
            }
        }

        let metrics = await reader.metrics
        XCTAssertGreaterThan(metrics.cancelledRequestCount, 0)
    }

    private func makeMockSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockRangeURLProtocol.self]
        return configuration
    }
}

private final class MockRangeURLProtocol: URLProtocol {
    static var storage = Data()
    static var delayNanos: UInt64 = 0

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if Self.delayNanos > 0 {
            usleep(useconds_t(Self.delayNanos / 1_000))
        }

        let data = Self.storage
        let method = request.httpMethod?.uppercased() ?? "GET"
        if method == "HEAD" {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(data.count)"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if let range = request.value(forHTTPHeaderField: "Range"),
           let parsed = parseRange(range, upperBound: data.count) {
            let slice = data[parsed]
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 206,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Range": "bytes \(parsed.lowerBound)-\(parsed.upperBound - 1)/\(data.count)",
                    "Content-Length": "\(slice.count)"
                ]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(slice))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(data.count)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func parseRange(_ value: String, upperBound: Int) -> Range<Int>? {
        guard value.hasPrefix("bytes=") else { return nil }
        let components = value.dropFirst("bytes=".count).split(separator: "-", maxSplits: 1).map(String.init)
        guard components.count == 2,
              let start = Int(components[0]),
              let end = Int(components[1]),
              start >= 0,
              end >= start else { return nil }
        let boundedEnd = min(end, max(0, upperBound - 1))
        return start..<(boundedEnd + 1)
    }
}
