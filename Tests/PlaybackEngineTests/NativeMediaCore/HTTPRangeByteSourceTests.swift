import NativeMediaCore
import XCTest

final class HTTPRangeByteSourceTests: XCTestCase {
    override func tearDown() {
        MockRangeProtocol.handler = nil
        MockRangeProtocol.resetStopLoadingCount()
        super.tearDown()
    }

    func testSendsByteRangeHeaderAndReadsPartialData() async throws {
        MockRangeProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=2-5")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 206,
                httpVersion: nil,
                headerFields: ["Content-Range": "bytes 2-5/10"]
            )!
            return (response, Data([2, 3, 4, 5]))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRangeProtocol.self]
        let source = HTTPRangeByteSource(url: URL(string: "https://example.com/movie.mkv")!, sessionConfiguration: config)

        let data = try await source.read(range: ByteRange(offset: 2, length: 4))

        XCTAssertEqual(data, Data([2, 3, 4, 5]))
        let metrics = await source.metrics()
        XCTAssertEqual(metrics.rangeRequestCount, 1)
    }

    func testCompletedClosedRangeDoesNotCancelTransportTask() async throws {
        MockRangeProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 206,
                httpVersion: "HTTP/2",
                headerFields: ["Content-Range": "bytes 0-3/10"]
            )!
            return (response, Data([0, 1, 2, 3]))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRangeProtocol.self]
        let source = HTTPRangeByteSource(
            url: URL(string: "https://example.com/movie.mkv")!,
            sessionConfiguration: config
        )

        _ = try await source.read(range: ByteRange(offset: 0, length: 4))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(
            MockRangeProtocol.stopLoadingCount,
            0,
            "A completed closed range must return its connection to the persistent session, not cancel it."
        )
    }

    func testTruncatesIgnoredZeroOffsetRangeResponseToRequestedLength() async throws {
        MockRangeProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-3")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "10"]
            )!
            return (response, Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRangeProtocol.self]
        let source = HTTPRangeByteSource(url: URL(string: "https://example.com/movie.mp4")!, sessionConfiguration: config)

        let data = try await source.read(range: ByteRange(offset: 0, length: 4))

        XCTAssertEqual(data, Data([0, 1, 2, 3]))
    }

    func testRejectsIgnoredNonZeroOffsetRangeResponse() async throws {
        MockRangeProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=4-6")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "10"]
            )!
            return (response, Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRangeProtocol.self]
        let source = HTTPRangeByteSource(url: URL(string: "https://example.com/movie.mp4")!, sessionConfiguration: config)

        do {
            _ = try await source.read(range: ByteRange(offset: 4, length: 3))
            XCTFail("Expected non-zero ignored range to fail")
        } catch MediaAccessError.httpStatus(200) {
        } catch {
            XCTFail("Expected HTTP status 200 error, got \(error)")
        }
    }

    func testReadsByteRangeFromLocalFileWithoutLoadingWholeFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bin")
        try Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = HTTPRangeByteSource(url: url)

        let data = try await source.read(range: ByteRange(offset: 4, length: 3))
        let size = try await source.size()

        XCTAssertEqual(data, Data([4, 5, 6]))
        XCTAssertEqual(size, 10)
    }
}

private final class MockRangeProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static let stopLock = NSLock()
    private static var _stopLoadingCount = 0

    static var stopLoadingCount: Int {
        stopLock.withLock { _stopLoadingCount }
    }

    static func resetStopLoadingCount() {
        stopLock.withLock { _stopLoadingCount = 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler?(request) ?? (HTTPURLResponse(), Data())
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        Self.stopLock.withLock { Self._stopLoadingCount += 1 }
    }
}
