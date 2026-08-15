import Foundation
@testable import ImageCache
import Shared
import UIKit
import XCTest

final class DefaultImagePipelineTests: XCTestCase {
    override func tearDown() {
        BlockingImageURLProtocol.reset()
        AuthenticatedImageURLProtocol.reset()
        ControlledImageURLProtocol.reset()
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

    func testPersistsDiskCacheWithoutSensitiveQueryItems() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try LRUDiskCache(directoryURL: cacheDir)
        let session = makeBlockingSession()
        let pipeline = DefaultImagePipeline(diskCache: cache, urlSession: session)
        let url = URL(string: "mock-image://poster?api_key=secret-token&maxWidth=320")!

        let loadTask = Task { try await pipeline.image(for: url) }
        try await waitUntil(timeout: 2.0) {
            BlockingImageURLProtocol.requestCount == 1
        }
        BlockingImageURLProtocol.resumePendingRequests(with: Self.samplePNGData)

        _ = try await loadTask.value

        let indexURL = cacheDir.appendingPathComponent("index.json")
        let data = try Data(contentsOf: indexURL)
        let rawIndex = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(rawIndex.contains("secret-token"))
        XCTAssertFalse(rawIndex.contains("api_key"))
        XCTAssertTrue(rawIndex.contains("maxWidth"))
    }

    func testAddsTokenHeaderWhenFetchingImages() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try LRUDiskCache(directoryURL: cacheDir)
        let session = makeAuthenticatedSession()
        let tokenStore = MockImageTokenStore(storedToken: "header-token")
        let pipeline = DefaultImagePipeline(diskCache: cache, urlSession: session, tokenStore: tokenStore)

        _ = try await pipeline.image(for: URL(string: "https://example.com/Items/item-1/Images/Primary?maxWidth=320")!)

        XCTAssertEqual(AuthenticatedImageURLProtocol.lastTokenHeader, "header-token")
    }

    func testRejectsDeclaredEncodedPayloadOverLimitBeforeDecode() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try LRUDiskCache(directoryURL: cacheDir)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeclaredOversizeImageURLProtocol.self]
        let decoder = DecodeSpy()
        let pipeline = DefaultImagePipeline(
            diskCache: cache,
            urlSession: URLSession(configuration: configuration),
            limits: .init(maximumEncodedBytes: Self.samplePNGData.count),
            decoder: decoder
        )

        do {
            _ = try await pipeline.image(for: URL(string: "declared-oversize-image://poster")!)
            XCTFail("Expected declared payload over the image limit to be rejected")
        } catch {
            // Expected: transport must reject the declared body before decode.
        }
        XCTAssertEqual(decoder.decodeCount, 0)
    }

    func testAllowsDeclaredEncodedPayloadAtLimit() async throws {
        let byteLimit = Self.samplePNGData.count
        ControlledImageURLProtocol.setResponse(
            statusCode: 200,
            headers: ["Content-Type": "image/png", "Content-Length": String(byteLimit)],
            chunks: [Self.samplePNGData]
        )
        let pipeline = try makeControlledPipeline(limits: .init(maximumEncodedBytes: byteLimit))

        let image = try await pipeline.image(for: URL(string: "controlled-image://declared-boundary")!)
        XCTAssertNotNil(image)
    }

    func testRejectsChunkedPayloadOverLimitBeforeDecode() async throws {
        let byteLimit = Self.samplePNGData.count
        ControlledImageURLProtocol.setResponse(
            statusCode: 200,
            headers: ["Content-Type": "image/png"],
            chunks: [Self.samplePNGData, Data([0])]
        )
        let decoder = DecodeSpy()
        let pipeline = try makeControlledPipeline(
            limits: .init(maximumEncodedBytes: byteLimit),
            decoder: decoder
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await pipeline.image(for: URL(string: "controlled-image://chunked-oversize")!)
        }
        XCTAssertEqual(decoder.decodeCount, 0)
    }

    func testCountsChunkedPayloadWhenContentLengthIsInvalid() async throws {
        let byteLimit = Self.samplePNGData.count
        ControlledImageURLProtocol.setResponse(
            statusCode: 200,
            headers: ["Content-Type": "image/png", "Content-Length": "not-a-number"],
            chunks: [Self.samplePNGData, Data([0])]
        )
        let decoder = DecodeSpy()
        let pipeline = try makeControlledPipeline(
            limits: .init(maximumEncodedBytes: byteLimit),
            decoder: decoder
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await pipeline.image(for: URL(string: "controlled-image://invalid-length")!)
        }
        XCTAssertEqual(decoder.decodeCount, 0)
    }

    func testCountsPayloadWhenContentLengthIsNegative() async throws {
        let byteLimit = Self.samplePNGData.count
        ControlledImageURLProtocol.setResponse(
            statusCode: 200,
            headers: ["Content-Type": "image/png", "Content-Length": "-1"],
            chunks: [Self.samplePNGData, Data([0])]
        )
        let decoder = DecodeSpy()
        let pipeline = try makeControlledPipeline(
            limits: .init(maximumEncodedBytes: byteLimit),
            decoder: decoder
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await pipeline.image(for: URL(string: "controlled-image://negative-length")!)
        }
        XCTAssertEqual(decoder.decodeCount, 0)
    }

    func testCountsActualPayloadWhenDeclaredLengthLiesShort() async throws {
        let byteLimit = Self.samplePNGData.count
        ControlledImageURLProtocol.setResponse(
            statusCode: 200,
            headers: ["Content-Type": "image/png", "Content-Length": "1"],
            chunks: [Self.samplePNGData, Data([0])]
        )
        let decoder = DecodeSpy()
        let pipeline = try makeControlledPipeline(
            limits: .init(maximumEncodedBytes: byteLimit),
            decoder: decoder
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await pipeline.image(for: URL(string: "controlled-image://lying-short-length")!)
        }
        XCTAssertEqual(decoder.decodeCount, 0)
    }

    func testRejectsNonSuccessStatusBeforeDecode() async throws {
        ControlledImageURLProtocol.setResponse(
            statusCode: 503,
            headers: ["Content-Type": "image/png"],
            chunks: [Self.samplePNGData]
        )
        let decoder = DecodeSpy()
        let pipeline = try makeControlledPipeline(decoder: decoder)

        await XCTAssertThrowsErrorAsync {
            _ = try await pipeline.image(for: URL(string: "controlled-image://status")!)
        }
        XCTAssertEqual(decoder.decodeCount, 0)
    }

    func testRejectsNonImageMIMEBeforeDecode() async throws {
        ControlledImageURLProtocol.setResponse(
            statusCode: 200,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            chunks: [Self.samplePNGData]
        )
        let decoder = DecodeSpy()
        let pipeline = try makeControlledPipeline(decoder: decoder)

        await XCTAssertThrowsErrorAsync {
            _ = try await pipeline.image(for: URL(string: "controlled-image://mime")!)
        }
        XCTAssertEqual(decoder.decodeCount, 0)
    }

    func testRejectsImageOverPixelLimitBeforeDecode() async throws {
        ControlledImageURLProtocol.setResponse(
            statusCode: 200,
            headers: ["Content-Type": "image/png"],
            chunks: [Self.twoByTwoPNGData]
        )
        let decoder = DecodeSpy()
        let pipeline = try makeControlledPipeline(
            limits: .init(maximumPixelCount: 3),
            decoder: decoder
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await pipeline.image(for: URL(string: "controlled-image://pixel-limit")!)
        }
        XCTAssertEqual(decoder.decodeCount, 0)
    }

    func testRejectsOversizeDiskPayloadBeforeDecode() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try LRUDiskCache(directoryURL: cacheDir)
        let url = URL(string: "controlled-image://disk-oversize")!
        await cache.setData(Data(repeating: 0, count: 1_025), forKey: url.reelfinCacheKey)
        let decoder = DecodeSpy()
        let pipeline = DefaultImagePipeline(
            diskCache: cache,
            limits: .init(maximumEncodedBytes: 1_024),
            decoder: decoder
        )

        let cachedImage = await pipeline.cachedImage(for: url)
        XCTAssertNil(cachedImage)
        XCTAssertEqual(decoder.decodeCount, 0)
        let cachedData = await cache.data(forKey: url.reelfinCacheKey)
        XCTAssertNil(cachedData)
    }

    func testRejectsDiskImageOverPixelLimitBeforeDecodeAndEvictsIt() async throws {
        let cache = try LRUDiskCache(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let url = URL(string: "controlled-image://disk-pixel-limit")!
        await cache.setData(Self.twoByTwoPNGData, forKey: url.reelfinCacheKey)
        let decoder = DecodeSpy()
        let pipeline = DefaultImagePipeline(
            diskCache: cache,
            limits: .init(maximumPixelCount: 3),
            decoder: decoder
        )

        let cachedImage = await pipeline.cachedImage(for: url)
        let cachedData = await cache.data(forKey: url.reelfinCacheKey)
        XCTAssertNil(cachedImage)
        XCTAssertNil(cachedData)
        XCTAssertEqual(decoder.decodeCount, 0)
    }

    func testDuplicateURLUsesOneTransportPermitAndOneDecode() async throws {
        let cache = try LRUDiskCache(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let decoder = DecodeSpy()
        let pipeline = DefaultImagePipeline(
            diskCache: cache,
            urlSession: makeBlockingSession(),
            limits: .init(maximumConcurrentLoads: 1),
            decoder: decoder
        )
        let url = URL(string: "mock-image://deduplicated-permit")!
        let first = Task { try await pipeline.image(for: url) }
        try await waitUntil(timeout: 2) { BlockingImageURLProtocol.requestCount == 1 }
        let second = Task { try await pipeline.image(for: url) }
        try await waitUntil(timeout: 2) { BlockingImageURLProtocol.requestCount == 1 }

        BlockingImageURLProtocol.resumePendingRequests(with: Self.samplePNGData)
        let firstImage = try await first.value
        let secondImage = try await second.value
        XCTAssertNotNil(firstImage)
        XCTAssertNotNil(secondImage)
        XCTAssertEqual(BlockingImageURLProtocol.requestCount, 1)
        XCTAssertEqual(decoder.decodeCount, 1)
    }

    func testTokenLookupIsDeferredUntilAdmissionAndSkippedForDiskHits() async throws {
        let cache = try LRUDiskCache(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let diskURL = URL(string: "mock-image://disk-token-free")!
        await cache.setData(Self.samplePNGData, forKey: diskURL.reelfinCacheKey)
        let tokenStore = CountingImageTokenStore(storedToken: "header-token")
        let pipeline = DefaultImagePipeline(
            diskCache: cache,
            urlSession: makeBlockingSession(),
            tokenStore: tokenStore,
            limits: .init(maximumConcurrentLoads: 1)
        )

        let diskImage = await pipeline.cachedImage(for: diskURL)
        XCTAssertNotNil(diskImage)
        XCTAssertEqual(tokenStore.fetchCount, 0)

        let active = Task { try await pipeline.image(for: URL(string: "mock-image://token-active")!) }
        try await waitUntil(timeout: 2) { BlockingImageURLProtocol.requestCount == 1 }
        XCTAssertEqual(tokenStore.fetchCount, 1)
        let queued = Task { try await pipeline.image(for: URL(string: "mock-image://token-queued")!) }
        try await waitUntil(timeout: 2) { tokenStore.fetchCount == 1 }

        BlockingImageURLProtocol.resumePendingRequests(with: Self.samplePNGData)
        _ = try await active.value
        try await waitUntil(timeout: 2) {
            BlockingImageURLProtocol.requestCount == 2 && tokenStore.fetchCount == 2
        }
        BlockingImageURLProtocol.resumePendingRequests(with: Self.samplePNGData)
        _ = try await queued.value
        XCTAssertEqual(tokenStore.fetchCount, 2)
    }

    func testLimitsDistinctURLLoadsGloballyAfterDeduplication() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try LRUDiskCache(directoryURL: cacheDir)
        let pipeline = DefaultImagePipeline(
            diskCache: cache,
            urlSession: makeBlockingSession(),
            limits: .init(maximumConcurrentLoads: 2)
        )
        let urls = (0 ..< 5).map { URL(string: "mock-image://limit-\($0)")! }
        let tasks = urls.map { url in Task { try await pipeline.image(for: url) } }

        try await waitUntil(timeout: 2.0) { BlockingImageURLProtocol.requestCount == 2 }
        XCTAssertEqual(BlockingImageURLProtocol.requestCount, 2)

        BlockingImageURLProtocol.resumePendingRequests(with: Self.samplePNGData)
        try await waitUntil(timeout: 2.0) { BlockingImageURLProtocol.requestCount == 4 }
        BlockingImageURLProtocol.resumePendingRequests(with: Self.samplePNGData)
        try await waitUntil(timeout: 2.0) { BlockingImageURLProtocol.requestCount == 5 }
        BlockingImageURLProtocol.resumePendingRequests(with: Self.samplePNGData)

        for task in tasks {
            let image = try await task.value
            XCTAssertNotNil(image)
        }
    }

    func testCancelsQueuedLoadWithoutStartingTransport() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try LRUDiskCache(directoryURL: cacheDir)
        let pipeline = DefaultImagePipeline(
            diskCache: cache,
            urlSession: makeBlockingSession(),
            limits: .init(maximumConcurrentLoads: 1)
        )
        let activeURL = URL(string: "mock-image://active")!
        let queuedURL = URL(string: "mock-image://queued")!
        let activeTask = Task { try await pipeline.image(for: activeURL) }
        try await waitUntil(timeout: 2.0) { BlockingImageURLProtocol.requestCount == 1 }
        let queuedTask = Task { try await pipeline.image(for: queuedURL) }
        try await Task.sleep(nanoseconds: 50_000_000)

        pipeline.cancel(url: queuedURL)
        await XCTAssertThrowsErrorAsync { _ = try await queuedTask.value }
        XCTAssertEqual(BlockingImageURLProtocol.requestCount, 1)

        BlockingImageURLProtocol.resumePendingRequests(with: Self.samplePNGData)
        let image = try await activeTask.value
        XCTAssertNotNil(image)
    }

    func testCancelsActiveLoadAndReleasesGlobalPermit() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try LRUDiskCache(directoryURL: cacheDir)
        let pipeline = DefaultImagePipeline(
            diskCache: cache,
            urlSession: makeBlockingSession(),
            limits: .init(maximumConcurrentLoads: 1)
        )
        let cancelledURL = URL(string: "mock-image://cancelled-active")!
        let nextURL = URL(string: "mock-image://after-active-cancel")!
        let cancelledTask = Task { try await pipeline.image(for: cancelledURL) }
        try await waitUntil(timeout: 2.0) { BlockingImageURLProtocol.requestCount == 1 }

        pipeline.cancel(url: cancelledURL)
        await XCTAssertThrowsErrorAsync { _ = try await cancelledTask.value }

        let nextTask = Task { try await pipeline.image(for: nextURL) }
        try await waitUntil(timeout: 2.0) { BlockingImageURLProtocol.requestCount == 2 }
        BlockingImageURLProtocol.resumePendingRequests(with: Self.samplePNGData)
        let image = try await nextTask.value
        XCTAssertNotNil(image)
    }

    func testRepeatedCancellationDuringPermitHandoffNeverLosesCapacity() async throws {
        let cancellationBox = TaskCancellationBox()
        let transitions = AsyncStream<ImageLoadLimiter.Transition> { continuation in
            cancellationBox.setTransitionContinuation(continuation)
        }
        let limiter = ImageLoadLimiter(maximumConcurrentLoads: 1) { transition in
            cancellationBox.record(transition)
            if case .willGrant = transition {
                cancellationBox.cancelTask()
            }
        }
        var transitionIterator = transitions.makeAsyncIterator()

        for _ in 0 ..< 20 {
            let activePermit = try await limiter.acquire()
            let cancelledTask = Task { try await limiter.acquire() }
            cancellationBox.setTask(cancelledTask)

            guard case .queued = await transitionIterator.next() else {
                return XCTFail("Expected the waiter to queue before handoff")
            }
            await limiter.release(activePermit)
            guard case .willGrant = await transitionIterator.next() else {
                return XCTFail("Expected cancellation at the exact grant boundary")
            }
            await XCTAssertThrowsErrorAsync { _ = try await cancelledTask.value }

            let survivorPermit = try await limiter.acquire()
            await limiter.release(survivorPermit)
        }
    }

    func testCancellationDuringSuspendingDecodeHasNoCacheSideEffectsAndRecoversPermit() async throws {
        let cache = try LRUDiskCache(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let decoder = SuspendingDecodeSpy()
        let pipeline = DefaultImagePipeline(
            diskCache: cache,
            urlSession: makeControlledSession(),
            limits: .init(maximumConcurrentLoads: 1),
            decoder: decoder
        )
        ControlledImageURLProtocol.setResponse(
            statusCode: 200,
            headers: ["Content-Type": "image/png"],
            chunks: [Self.samplePNGData]
        )
        let cancelledURL = URL(string: "controlled-image://cancel-during-decode")!
        let cancelledTask = Task { try await pipeline.image(for: cancelledURL) }
        try await decoder.waitUntilDecodeStarts()

        pipeline.cancel(url: cancelledURL)
        await decoder.resumeDecode()

        await XCTAssertThrowsErrorAsync { _ = try await cancelledTask.value }
        let cachedImage = await pipeline.cachedImage(for: cancelledURL)
        let diskData = await cache.data(forKey: cancelledURL.reelfinCacheKey)
        XCTAssertNil(cachedImage)
        XCTAssertNil(diskData)

        let nextURL = URL(string: "controlled-image://after-cancelled-decode")!
        let nextTask = Task { try await pipeline.image(for: nextURL) }
        try await decoder.waitUntilDecodeStarts(expectedCount: 2)
        await decoder.resumeDecode()
        let nextImage = try await nextTask.value
        XCTAssertNotNil(nextImage)
    }

    func testCancellationDuringCachedDecodePreservesValidDiskEntryAndRecoversPermit() async throws {
        let cache = try LRUDiskCache(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let url = URL(string: "controlled-image://cancel-cached-decode")!
        await cache.setData(Self.samplePNGData, forKey: url.reelfinCacheKey)
        let decoder = SuspendingDecodeSpy()
        let pipeline = DefaultImagePipeline(
            diskCache: cache,
            limits: .init(maximumConcurrentLoads: 1),
            decoder: decoder
        )
        let cancelledTask = Task { await pipeline.cachedImage(for: url) }
        try await decoder.waitUntilDecodeStarts()

        cancelledTask.cancel()
        await decoder.resumeDecode()

        let cancelledImage = await cancelledTask.value
        XCTAssertNil(cancelledImage)
        let preservedData = await cache.data(forKey: url.reelfinCacheKey)
        XCTAssertEqual(preservedData, Self.samplePNGData)

        let retryTask = Task { await pipeline.cachedImage(for: url) }
        try await decoder.waitUntilDecodeStarts(expectedCount: 2)
        await decoder.resumeDecode()
        let retryImage = await retryTask.value
        XCTAssertNotNil(retryImage)
    }

    func testCachedImagesShareTheGlobalDecodeLimit() async throws {
        let cache = try LRUDiskCache(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let urls = (0 ..< 4).map { URL(string: "controlled-image://disk-limit-\($0)")! }
        for url in urls {
            await cache.setData(Self.samplePNGData, forKey: url.reelfinCacheKey)
        }
        let decoder = ConcurrentDecodeSpy()
        let pipeline = DefaultImagePipeline(
            diskCache: cache,
            limits: .init(maximumConcurrentLoads: 1),
            decoder: decoder
        )

        await withTaskGroup(of: UIImage?.self) { group in
            for url in urls {
                group.addTask { await pipeline.cachedImage(for: url) }
            }
            for await image in group {
                XCTAssertNotNil(image)
            }
        }

        XCTAssertEqual(decoder.peakConcurrentDecodes, 1)
    }

    private func makeBlockingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlockingImageURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeAuthenticatedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticatedImageURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeControlledPipeline(
        limits: ImagePipelineLimits = .init(),
        decoder: any ImageDataDecoding = ImageIODecoder()
    ) throws -> DefaultImagePipeline {
        return DefaultImagePipeline(
            diskCache: try LRUDiskCache(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            urlSession: makeControlledSession(),
            limits: limits,
            decoder: decoder
        )
    }

    private func makeControlledSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledImageURLProtocol.self]
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

    fileprivate static let samplePNGData: Data = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return image.pngData()!
    }()

    fileprivate static let twoByTwoPNGData: Data = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.pngData()!
    }()
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        // Expected.
    }
}

private final class AuthenticatedImageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var lastTokenHeaderStorage: String?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.withLock {
            Self.lastTokenHeaderStorage = request.value(forHTTPHeaderField: "X-Emby-Token")
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: DefaultImagePipelineTests.samplePNGData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        lock.withLock {
            lastTokenHeaderStorage = nil
        }
    }

    static var lastTokenHeader: String? {
        lock.withLock { lastTokenHeaderStorage }
    }
}

private final class DeclaredOversizeImageURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "declared-oversize-image"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "image/png",
                "Content-Length": "104857601"
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: DefaultImagePipelineTests.samplePNGData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ControlledImageURLProtocol: URLProtocol {
    private struct Response {
        let statusCode: Int
        let headers: [String: String]
        let chunks: [Data]
    }

    private static let lock = NSLock()
    private static var response = Response(statusCode: 200, headers: [:], chunks: [])

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "controlled-image"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = Self.lock.withLock { Self.response }
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        for chunk in response.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func setResponse(statusCode: Int, headers: [String: String], chunks: [Data]) {
        lock.withLock {
            response = Response(statusCode: statusCode, headers: headers, chunks: chunks)
        }
    }

    static func reset() {
        setResponse(statusCode: 200, headers: [:], chunks: [])
    }
}

private final class DecodeSpy: ImageDataDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var decodeCount: Int {
        lock.withLock { count }
    }

    func decode(data _: Data, maximumThumbnailPixelSize _: Int) async -> UIImage? {
        lock.withLock { count += 1 }
        return UIImage(data: DefaultImagePipelineTests.samplePNGData)
    }
}

private final class ConcurrentDecodeSpy: ImageDataDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private var activeDecodes = 0
    private var peakDecodes = 0

    var peakConcurrentDecodes: Int {
        lock.withLock { peakDecodes }
    }

    func decode(data _: Data, maximumThumbnailPixelSize _: Int) async -> UIImage? {
        lock.withLock {
            activeDecodes += 1
            peakDecodes = max(peakDecodes, activeDecodes)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        lock.withLock { activeDecodes -= 1 }
        return UIImage(data: DefaultImagePipelineTests.samplePNGData)
    }
}

private actor SuspendingDecodeSpy: ImageDataDecoding {
    private var decodeCount = 0
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []

    func decode(data _: Data, maximumThumbnailPixelSize _: Int) async -> UIImage? {
        decodeCount += 1
        await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
        }
        return UIImage(data: DefaultImagePipelineTests.samplePNGData)
    }

    func waitUntilDecodeStarts(expectedCount: Int = 1) async throws {
        let deadline = Date().addingTimeInterval(2)
        while decodeCount < expectedCount {
            guard Date() < deadline else {
                throw DecodeSpyError.timedOut
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func resumeDecode() {
        guard !pendingContinuations.isEmpty else { return }
        pendingContinuations.removeFirst().resume()
    }

    private enum DecodeSpyError: Error {
        case timedOut
    }
}

private final class TaskCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<UUID, Error>?
    private var transitionContinuation: AsyncStream<ImageLoadLimiter.Transition>.Continuation?

    func setTask(_ task: Task<UUID, Error>) {
        lock.withLock { self.task = task }
    }

    func cancelTask() {
        lock.withLock { task?.cancel() }
    }

    func setTransitionContinuation(_ continuation: AsyncStream<ImageLoadLimiter.Transition>.Continuation) {
        lock.withLock { transitionContinuation = continuation }
    }

    func record(_ transition: ImageLoadLimiter.Transition) {
        lock.withLock { _ = transitionContinuation?.yield(transition) }
    }
}

private final class MockImageTokenStore: TokenStoreProtocol, @unchecked Sendable {
    var storedToken: String?

    init(storedToken: String?) {
        self.storedToken = storedToken
    }

    func saveToken(_ token: String) throws {
        storedToken = token
    }

    func fetchToken() throws -> String? {
        storedToken
    }

    func clearToken() throws {
        storedToken = nil
    }
}

private final class CountingImageTokenStore: TokenStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private var fetchCountStorage = 0

    init(storedToken: String?) {
        token = storedToken
    }

    var fetchCount: Int {
        lock.withLock { fetchCountStorage }
    }

    func saveToken(_ token: String) throws {
        lock.withLock { self.token = token }
    }

    func fetchToken() throws -> String? {
        lock.withLock {
            fetchCountStorage += 1
            return token
        }
    }

    func clearToken() throws {
        lock.withLock { token = nil }
    }
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
