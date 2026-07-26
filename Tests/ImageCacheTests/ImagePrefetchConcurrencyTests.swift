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
        XCTAssertEqual(BlockingPrefetchURLProtocol.startEvents.map(\.completionEpoch), [0, 0, 0, 0])

        BlockingPrefetchURLProtocol.complete(url: urls[0], with: Self.samplePNGData)
        await BlockingPrefetchURLProtocol.waitUntilStarted(count: 5)
        XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs.count, 5)
        XCTAssertEqual(BlockingPrefetchURLProtocol.startEvents[4].completionEpoch, 1)

        task.cancel()
        await task.value
        session.finishTasksAndInvalidate()
    }

    func testCancellingParentCompletesWithoutTransportCompletionOrSessionInvalidation() async throws {
        let (pipeline, session) = try makePipeline()
        let urls = makeURLs(count: 8)
        let task = Task {
            await pipeline.prefetch(urls: urls)
        }

        await BlockingPrefetchURLProtocol.waitUntilStarted(count: 4)
        XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs.count, 4)

        task.cancel()
        await task.value

        XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs.count, 4)
        session.finishTasksAndInvalidate()
    }

    func testPreCancelledConsumerNeverStartsTransport() async throws {
        let (pipeline, session) = try makePipeline()
        BlockingPrefetchURLProtocol.respondImmediately(with: Self.samplePNGData)
        let url = makeURLs(count: 1)[0]

        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            do {
                _ = try await pipeline.image(for: url, consumer: ImageRequestConsumerID())
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        let wasCancelled = await task.value
        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs, [])
        session.finishTasksAndInvalidate()
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

    func testPrefetchCandidatesPreserveStableOrderAcrossDuplicatesAndRemainCappedAtTwentyFour() async throws {
        let (pipeline, _) = try makePipeline()
        let urls = makeURLs(count: 26)
        var candidates = [urls[0], urls[0], urls[1], urls[2], urls[1], urls[3]]
        for index in 4 ..< 26 {
            candidates.append(urls[index])
            if index.isMultiple(of: 3) {
                candidates.append(urls[2])
            }
        }
        let task = Task {
            await pipeline.prefetch(urls: candidates)
        }

        await BlockingPrefetchURLProtocol.waitUntilStarted(count: 4)
        XCTAssertEqual(Set(BlockingPrefetchURLProtocol.startedURLs), Set(urls.prefix(4)))

        BlockingPrefetchURLProtocol.complete(url: urls[0], with: Self.samplePNGData)
        await BlockingPrefetchURLProtocol.waitUntilStarted(count: 5)
        for admittedIndex in 4 ..< 23 {
            BlockingPrefetchURLProtocol.complete(url: urls[admittedIndex], with: Self.samplePNGData)
            await BlockingPrefetchURLProtocol.waitUntilStarted(count: admittedIndex + 2)
        }

        BlockingPrefetchURLProtocol.completeAll(with: Self.samplePNGData)
        await task.value

        XCTAssertEqual(BlockingPrefetchURLProtocol.startedURLs.count, 24)
        XCTAssertEqual(
            Array(BlockingPrefetchURLProtocol.startedURLs.dropFirst(4)),
            Array(urls[4 ..< 24])
        )
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
    struct StartEvent: Equatable {
        let url: URL
        let completionEpoch: Int
    }

    private struct StartWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private static let lock = NSLock()
    private static var pendingRequests = [URL: BlockingPrefetchURLProtocol]()
    private static var startedURLStorage = [URL]()
    private static var startEventStorage = [StartEvent]()
    private static var startWaiters = [StartWaiter]()
    private static var completionEpoch = 0
    private static var immediateResponseData: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host()?.hasSuffix(".prefetch.test") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let (resumptions, immediateResponseData) = Self.lock.withLock {
            Self.pendingRequests[url] = self
            Self.startedURLStorage.append(url)
            Self.startEventStorage.append(
                StartEvent(url: url, completionEpoch: Self.completionEpoch)
            )
            let ready = Self.startWaiters.filter { $0.count <= Self.startedURLStorage.count }
            Self.startWaiters.removeAll { $0.count <= Self.startedURLStorage.count }
            return (ready.map(\.continuation), Self.immediateResponseData)
        }
        resumptions.forEach { $0.resume() }
        if let immediateResponseData {
            Self.complete(url: url, with: immediateResponseData)
        }
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

    static var startEvents: [StartEvent] {
        lock.withLock { startEventStorage }
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
        let request: BlockingPrefetchURLProtocol? = lock.withLock {
            guard let request = pendingRequests.removeValue(forKey: url) else { return nil }
            completionEpoch += 1
            return request
        }
        request?.complete(with: data)
    }

    static func respondImmediately(with data: Data) {
        lock.withLock {
            immediateResponseData = data
        }
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
            startEventStorage.removeAll()
            startWaiters.removeAll()
            completionEpoch = 0
            immediateResponseData = nil
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
