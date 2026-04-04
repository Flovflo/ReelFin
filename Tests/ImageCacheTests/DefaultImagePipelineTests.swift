import Foundation
@testable import ImageCache
import Shared
import UIKit
import XCTest

final class DefaultImagePipelineTests: XCTestCase {
    override func tearDown() {
        BlockingImageURLProtocol.reset()
        super.tearDown()
    }

    func testConsumerCancellationDoesNotCancelSharedInFlightRequest() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try LRUDiskCache(directoryURL: cacheDir)
        let session = makeBlockingSession()
        let pipeline = DefaultImagePipeline(diskCache: cache, urlSession: session)
        let url = URL(string: "mock-image://poster")!
        let consumerA = ImageRequestConsumerID()
        let consumerB = ImageRequestConsumerID()

        let taskA = Task { try await pipeline.image(for: url, consumer: consumerA) }

        try await waitUntil(timeout: 2.0) {
            BlockingImageURLProtocol.requestCount == 1
        }

        let taskB = Task { try await pipeline.image(for: url, consumer: consumerB) }
        try await Task.sleep(nanoseconds: 50_000_000)

        pipeline.cancel(url: url, consumer: consumerA)
        taskA.cancel()

        BlockingImageURLProtocol.resumePendingRequests(with: Self.samplePNGData)

        let image = try await taskB.value
        XCTAssertNotNil(image)

        do {
            _ = try await taskA.value
            XCTFail("Expected consumer A to cancel")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(BlockingImageURLProtocol.requestCount, 1)
    }

    private func makeBlockingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlockingImageURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping @Sendable () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(condition(), "Timed out waiting for condition")
    }

    private static let samplePNGData: Data = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return image.pngData()!
    }()
}

private final class BlockingImageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var pendingRequests: [BlockingImageURLProtocol] = []
    private static var requestCountStorage = 0

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "mock-image"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.withLock {
            Self.requestCountStorage += 1
            Self.pendingRequests.append(self)
        }
    }

    override func stopLoading() {
        Self.lock.withLock {
            Self.pendingRequests.removeAll { $0 === self }
        }
    }

    static func reset() {
        lock.withLock {
            pendingRequests.removeAll()
            requestCountStorage = 0
        }
    }

    static var requestCount: Int {
        lock.withLock { requestCountStorage }
    }

    static func resumePendingRequests(with data: Data) {
        let requests = lock.withLock {
            let requests = pendingRequests
            pendingRequests.removeAll()
            return requests
        }

        for request in requests {
            guard let url = request.request.url else { continue }
            guard let client = request.client else { continue }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/png"]
            )!
            client.urlProtocol(request, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(request, didLoad: data)
            client.urlProtocolDidFinishLoading(request)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
