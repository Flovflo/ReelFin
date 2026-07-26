import Foundation
@testable import ImageCache
import Shared
import UIKit
import XCTest

final class ImagePrefetchConcurrencyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BlockingPrefetchURLProtocol.reset()
    }

    override func tearDown() {
        BlockingPrefetchURLProtocol.reset()
        super.tearDown()
    }

    func testExactlyFourRequestsStartBeforeACompletionAndOneCompletionAdmitsOne() async throws {
        let (pipeline, session) = try makePipeline()
        let urls = makeURLs(count: 6)
        let task = Task {
            await pipeline.prefetch(urls: urls)
        }

        await BlockingPrefetchURLProtocol.waitUntilStarted(count: 4)
        XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs.count, 4)

        BlockingPrefetchURLProtocol.complete(url: urls[0], with: Self.samplePNGData)
        await BlockingPrefetchURLProtocol.waitUntilStarted(count: 5)
        XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs.count, 5)

        task.cancel()
        session.invalidateAndCancel()
        await task.value
    }

    func testCancellingParentNeverAdmitsWaitingURLs() async throws {
        let (pipeline, session) = try makePipeline()
        let urls = makeURLs(count: 8)
        let task = Task {
            await pipeline.prefetch(urls: urls)
        }

        await BlockingPrefetchURLProtocol.waitUntilStarted(count: 4)
        XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs.count, 4)

        task.cancel()
        session.invalidateAndCancel()
        await task.value

        XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs.count, 4)
    }

    func testDuplicateURLsConsumeOneSlotAndPreserveFirstSeenOrder() async throws {
        let (pipeline, _) = try makePipeline()
        let urls = makeURLs(count: 5)
        let candidates = [urls[0], urls[0], urls[1], urls[2], urls[3], urls[4]]
        let task = Task {
            await pipeline.prefetch(urls: candidates)
        }

        await BlockingPrefetchURLProtocol.waitUntilStarted(count: 4)
        XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs.count, 4)
        XCTAssertEqual(Set(BlockingPrefetchURLProtocol.startedURLs), Set(urls.prefix(4)))

        BlockingPrefetchURLProtocol.complete(url: urls[0], with: Self.samplePNGData)
        await BlockingPrefetchURLProtocol.waitUntilStarted(count: 5)
        XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs.count, urls.count)
        XCTAssertEqual(Set(BlockingPrefetchURLProtocol.startedURLs), Set(urls))

        BlockingPrefetchURLProtocol.completeAll(with: Self.samplePNGData)
        await task.value
    }

    func testPrefetchCandidatesRemainCappedAtTwentyFour() async throws {
        let (pipeline, _) = try makePipeline()
        let urls = makeURLs(count: 30)
        let task = Task {
            await pipeline.prefetch(urls: urls)
        }

        await BlockingPrefetchURLProtocol.waitUntilStarted(count: 4)
        for admittedCount in 5 ... 24 {
            BlockingPrefetchURLProtocol.completeOldestPending(with: Self.samplePNGData)
            await BlockingPrefetchURLProtocol.waitUntilStarted(count: admittedCount)
            XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs.count, admittedCount)
        }

        BlockingPrefetchURLProtocol.completeAll(with: Self.samplePNGData)
        await task.value

        XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs.count, 24)
        XCTAssertEqual(Set(BlockingPrefetchURLProtocol.startedURLs), Set(urls.prefix(24)))
    }

    private func makePipeline() throws -> (DefaultImagePipeline, URLSession) {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = try LRUDiskCache(directoryURL: cacheDirectory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlockingPrefetchURLProtocol.self]
        configuration.httpMaximumConnectionsPerHost = 30
        let session = URLSession(configuration: configuration)
        let pipeline = DefaultImagePipeline(
            diskCache: cache,
            urlSession: session
        )
        return (pipeline, session)
    }

    private func makeURLs(count: Int) -> [URL] {
        (0 ..< count).map { index in
            URL(string: "https://host-\(index).prefetch.test/image.png")!
        }
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

private final class BlockingPrefetchURLProtocol: URLProtocol {
    private struct StartWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private static let lock = NSLock()
    private static var pendingRequests = [URL: BlockingPrefetchURLProtocol]()
    private static var startedURLStorage = [URL]()
    private static var startWaiters = [StartWaiter]()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host()?.hasSuffix(".prefetch.test") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let resumptions = Self.lock.withLock {
            Self.pendingRequests[url] = self
            Self.startedURLStorage.append(url)
            let ready = Self.startWaiters.filter { $0.count <= Self.startedURLStorage.count }
            Self.startWaiters.removeAll { $0.count <= Self.startedURLStorage.count }
            return ready.map(\.continuation)
        }
        resumptions.forEach { $0.resume() }
    }

    override func stopLoading() {
        guard let url = request.url else { return }
        Self.lock.withLock {
            if Self.pendingRequests[url] === self {
                Self.pendingRequests[url] = nil
            }
        }
    }

    static var startedURLs: [URL] {
        lock.withLock { startedURLStorage }
    }

    static func waitUntilStarted(count: Int) async {
        if lock.withLock({ startedURLStorage.count >= count }) {
            return
        }
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock {
                guard startedURLStorage.count < count else { return true }
                startWaiters.append(StartWaiter(count: count, continuation: continuation))
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    static func complete(url: URL, with data: Data) {
        let request = lock.withLock { pendingRequests.removeValue(forKey: url) }
        request?.complete(with: data)
    }

    static func completeOldestPending(with data: Data) {
        let request = lock.withLock { () -> BlockingPrefetchURLProtocol? in
            guard let url = startedURLStorage.first(where: { pendingRequests[$0] != nil }) else {
                return nil
            }
            return pendingRequests.removeValue(forKey: url)
        }
        request?.complete(with: data)
    }

    static func completeAll(with data: Data) {
        let requests = lock.withLock {
            let requests = Array(pendingRequests.values)
            pendingRequests.removeAll()
            return requests
        }
        requests.forEach { $0.complete(with: data) }
    }

    static func reset() {
        let requests = lock.withLock {
            let requests = Array(pendingRequests.values)
            pendingRequests.removeAll()
            startedURLStorage.removeAll()
            startWaiters.removeAll()
            return requests
        }
        requests.forEach { $0.client?.urlProtocol($0, didFailWithError: CancellationError()) }
    }

    private func complete(with data: Data) {
        guard let url = request.url, let client else { return }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: data)
        client.urlProtocolDidFinishLoading(self)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
