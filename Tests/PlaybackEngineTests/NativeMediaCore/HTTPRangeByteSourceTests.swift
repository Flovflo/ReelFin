import NativeMediaCore
import XCTest

final class HTTPRangeByteSourceTests: XCTestCase {
    override func tearDown() {
        MockRangeProtocol.handler = nil
        MockRangeProtocol.resetPrematureStopLoadingCount()
        SuspendingRangeProtocol.reset()
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

    func testCompletedClosedRangesKeepSourceUsableWithoutPrematureTransportStop() async throws {
        MockRangeProtocol.handler = { request in
            let range = request.value(forHTTPHeaderField: "Range")
            let data: Data
            let contentRange: String
            switch range {
            case "bytes=0-3":
                data = Data([0, 1, 2, 3])
                contentRange = "bytes 0-3/10"
            case "bytes=4-7":
                data = Data([4, 5, 6, 7])
                contentRange = "bytes 4-7/10"
            default:
                XCTFail("Unexpected range request: \(range ?? "nil")")
                data = Data()
                contentRange = "bytes */10"
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 206,
                httpVersion: "HTTP/2",
                headerFields: ["Content-Range": contentRange]
            )!
            return (response, data)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRangeProtocol.self]
        let source = HTTPRangeByteSource(
            url: URL(string: "https://example.com/movie.mkv")!,
            sessionConfiguration: config
        )

        let first = try await source.read(range: ByteRange(offset: 0, length: 4))
        let second = try await source.read(range: ByteRange(offset: 4, length: 4))

        XCTAssertEqual(first, Data([0, 1, 2, 3]))
        XCTAssertEqual(second, Data([4, 5, 6, 7]))
        XCTAssertEqual(
            MockRangeProtocol.prematureStopLoadingCount,
            0,
            "A completed closed range must not stop its transport before normal completion."
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

    func testCancelStopsAnInFlightRangeExactlyOnce() async {
        let started = expectation(description: "range request started")
        SuspendingRangeProtocol.onStart = { started.fulfill() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SuspendingRangeProtocol.self]
        let source = HTTPRangeByteSource(
            url: URL(string: "https://example.com/movie.mkv")!,
            sessionConfiguration: config
        )
        let readTask = Task {
            try await source.read(range: ByteRange(offset: 0, length: 4))
        }
        await fulfillment(of: [started], timeout: 1)

        await source.cancel()
        _ = await readTask.result

        XCTAssertEqual(SuspendingRangeProtocol.stopLoadingCount, 1)
    }
}

private final class MockRangeProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private let lifecycleLock = NSLock()
    private var didSignalNormalFinish = false
    private static let stopLock = NSLock()
    private static var _prematureStopLoadingCount = 0

    static var prematureStopLoadingCount: Int {
        stopLock.withLock { _prematureStopLoadingCount }
    }

    static func resetPrematureStopLoadingCount() {
        stopLock.withLock { _prematureStopLoadingCount = 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler?(request) ?? (HTTPURLResponse(), Data())
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            lifecycleLock.withLock { didSignalNormalFinish = true }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        let stoppedBeforeNormalFinish = lifecycleLock.withLock { !didSignalNormalFinish }
        if stoppedBeforeNormalFinish {
            Self.stopLock.withLock { Self._prematureStopLoadingCount += 1 }
        }
    }
}

private final class SuspendingRangeProtocol: URLProtocol {
    static var onStart: (() -> Void)?
    private static let stopLock = NSLock()
    private static var _stopLoadingCount = 0

    static var stopLoadingCount: Int {
        stopLock.withLock { _stopLoadingCount }
    }

    static func reset() {
        stopLock.withLock {
            _stopLoadingCount = 0
            onStart = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.onStart?()
    }

    override func stopLoading() {
        Self.stopLock.withLock { Self._stopLoadingCount += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
}
