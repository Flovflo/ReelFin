import Shared
@testable import ReelFinUI
import UIKit
import XCTest

@MainActor
final class CachedRemoteImageLoaderTests: XCTestCase {
    func testOldURLResolutionCannotAttachAfterNewGenerationStarts() async {
        let harness = ControlledImageLoadHarness()
        let loader = makeLoader(harness: harness)
        let imageB = makeImage(color: .blue)
        var firstCallbackCount = 0

        let first = Task { @MainActor in
            await loader.load(descriptor: Self.descriptorA) {
                firstCallbackCount += 1
            }
        }
        await harness.waitUntilResolutionIsSuspended(for: Self.descriptorA)

        let second = Task { @MainActor in
            await loader.load(descriptor: Self.descriptorB)
        }
        await harness.waitUntilResolutionIsSuspended(for: Self.descriptorB)
        await harness.resumeResolution(for: Self.descriptorB, with: Self.urlB)
        await harness.waitUntilCacheLookupIsSuspended(for: Self.urlB)
        await harness.resumeCacheLookup(for: Self.urlB, with: imageB)
        await second.value

        await harness.resumeResolution(for: Self.descriptorA, with: Self.urlA)
        await first.value

        XCTAssertTrue(loader.image === imageB)
        XCTAssertEqual(firstCallbackCount, 0)
        let cancelledURLs = harness.cancelledRequests.map(\.url)
        XCTAssertFalse(cancelledURLs.contains(Self.urlA))
    }

    func testOldCachedLookupCannotPublishAfterNewGenerationStarts() async {
        let harness = ControlledImageLoadHarness()
        let loader = makeLoader(harness: harness)
        let imageA = makeImage(color: .red)
        let imageB = makeImage(color: .blue)
        var firstCallbackCount = 0

        let first = Task { @MainActor in
            await loader.load(descriptor: Self.descriptorA) {
                firstCallbackCount += 1
            }
        }
        await attachAndSuspendCache(taskDescriptor: Self.descriptorA, url: Self.urlA, harness: harness)

        await completeCachedLoad(
            descriptor: Self.descriptorB,
            url: Self.urlB,
            image: imageB,
            loader: loader,
            harness: harness
        )
        await harness.resumeCacheLookup(for: Self.urlA, with: imageA)
        await first.value

        XCTAssertTrue(loader.image === imageB)
        XCTAssertEqual(firstCallbackCount, 0)
    }

    func testOldPrimaryDownloadCannotPublishAfterNewGenerationStarts() async {
        let harness = ControlledImageLoadHarness()
        let loader = makeLoader(harness: harness)
        let imageA = makeImage(color: .red)
        let imageB = makeImage(color: .blue)
        var firstCallbackCount = 0

        let first = Task { @MainActor in
            await loader.load(descriptor: Self.descriptorA) {
                firstCallbackCount += 1
            }
        }
        await attachAndSuspendCache(taskDescriptor: Self.descriptorA, url: Self.urlA, harness: harness)
        await harness.resumeCacheLookup(for: Self.urlA, with: nil)
        await harness.waitUntilDownloadIsSuspended(for: Self.urlA)

        await completeCachedLoad(
            descriptor: Self.descriptorB,
            url: Self.urlB,
            image: imageB,
            loader: loader,
            harness: harness
        )
        await harness.resumeDownload(for: Self.urlA, with: .success(imageA))
        await first.value

        XCTAssertTrue(loader.image === imageB)
        XCTAssertEqual(firstCallbackCount, 0)
    }

    func testOldFallbackDownloadCannotPublishAfterNewGenerationStarts() async {
        let harness = ControlledImageLoadHarness()
        let loader = makeLoader(harness: harness)
        let fallbackDescriptorA = Self.descriptorA.replacing(type: .backdrop)
        let imageA = makeImage(color: .red)
        let imageB = makeImage(color: .blue)
        var firstCallbackCount = 0

        let first = Task { @MainActor in
            await loader.load(descriptor: Self.descriptorA) {
                firstCallbackCount += 1
            }
        }
        await attachAndSuspendCache(taskDescriptor: Self.descriptorA, url: Self.urlA, harness: harness)
        await harness.resumeCacheLookup(for: Self.urlA, with: nil)
        await harness.waitUntilDownloadIsSuspended(for: Self.urlA)
        await harness.resumeDownload(for: Self.urlA, with: .failure(TestImageError.failed))
        await harness.waitUntilResolutionIsSuspended(for: fallbackDescriptorA)
        await harness.resumeResolution(for: fallbackDescriptorA, with: Self.fallbackURLA)
        await harness.waitUntilDownloadIsSuspended(for: Self.fallbackURLA)

        await completeCachedLoad(
            descriptor: Self.descriptorB,
            url: Self.urlB,
            image: imageB,
            loader: loader,
            harness: harness
        )
        await harness.resumeDownload(for: Self.fallbackURLA, with: .success(imageA))
        await first.value

        XCTAssertTrue(loader.image === imageB)
        XCTAssertEqual(firstCallbackCount, 0)
    }

    func testInvalidationCancelsAttachedURLAndPreventsPublication() async {
        let harness = ControlledImageLoadHarness()
        let loader = makeLoader(harness: harness)
        let staleImage = makeImage(color: .red)
        var callbackCount = 0

        let task = Task { @MainActor in
            await loader.load(descriptor: Self.descriptorA) {
                callbackCount += 1
            }
        }
        await attachAndSuspendCache(taskDescriptor: Self.descriptorA, url: Self.urlA, harness: harness)

        loader.invalidate()
        let cancelledRequests = harness.cancelledRequests
        XCTAssertEqual(cancelledRequests.map(\.url), [Self.urlA])

        await harness.resumeCacheLookup(for: Self.urlA, with: staleImage)
        await task.value

        XCTAssertNil(loader.image)
        XCTAssertEqual(callbackCount, 0)
    }

    func testTaskCancellationPreventsPublication() async {
        let harness = ControlledImageLoadHarness()
        let loader = makeLoader(harness: harness)
        let staleImage = makeImage(color: .red)
        var callbackCount = 0

        let task = Task { @MainActor in
            await loader.load(descriptor: Self.descriptorA) {
                callbackCount += 1
            }
        }
        await attachAndSuspendCache(taskDescriptor: Self.descriptorA, url: Self.urlA, harness: harness)

        task.cancel()
        await harness.resumeCacheLookup(for: Self.urlA, with: staleImage)
        await task.value

        XCTAssertNil(loader.image)
        XCTAssertEqual(callbackCount, 0)
    }

    func testPreCancelledLoadCannotEvictSuspendedActiveGeneration() async {
        let harness = ControlledImageLoadHarness()
        let loader = CachedRemoteImageLoader(
            resolveURL: { descriptor in
                descriptor == Self.descriptorA ? Self.urlA : Self.urlB
            },
            cachedImage: { url in
                guard url == Self.urlB else { return nil }
                return await harness.cachedImage(for: url)
            },
            fetchImage: { _, _ in
                throw TestImageError.failed
            },
            cancel: { url, consumerID in
                harness.recordCancellation(url: url, consumerID: consumerID)
            }
        )
        let imageB = makeImage(color: .blue)
        let active = Task { @MainActor in
            await loader.load(descriptor: Self.descriptorB)
        }
        await harness.waitUntilCacheLookupIsSuspended(for: Self.urlB)

        let preCancelled = Task { @MainActor in
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            await loader.load(descriptor: Self.descriptorA)
        }
        await preCancelled.value

        XCTAssertEqual(harness.cancelledRequests, [])
        await harness.resumeCacheLookup(for: Self.urlB, with: imageB)
        await active.value
        XCTAssertTrue(loader.image === imageB)
    }

    func testOldGenerationFinishingCannotClearNewerURL() {
        var state = CachedRemoteImageRequestState()

        let first = state.begin().token
        XCTAssertNil(state.attach(Self.urlA, to: first))
        let secondStart = state.begin()
        XCTAssertEqual(secondStart.cancellation?.url, Self.urlA)
        XCTAssertNil(state.attach(Self.urlB, to: secondStart.token))

        state.finish(first)

        XCTAssertTrue(state.owns(secondStart.token))
        XCTAssertEqual(state.requestURL, Self.urlB)
    }

    private func makeLoader(harness: ControlledImageLoadHarness) -> CachedRemoteImageLoader {
        CachedRemoteImageLoader(
            resolveURL: { descriptor in
                await harness.resolveURL(for: descriptor)
            },
            cachedImage: { url in
                await harness.cachedImage(for: url)
            },
            fetchImage: { url, consumerID in
                try await harness.fetchImage(for: url, consumerID: consumerID)
            },
            cancel: { url, consumerID in
                harness.recordCancellation(url: url, consumerID: consumerID)
            }
        )
    }

    private func attachAndSuspendCache(
        taskDescriptor: CachedRemoteImageDescriptor,
        url: URL,
        harness: ControlledImageLoadHarness
    ) async {
        await harness.waitUntilResolutionIsSuspended(for: taskDescriptor)
        await harness.resumeResolution(for: taskDescriptor, with: url)
        await harness.waitUntilCacheLookupIsSuspended(for: url)
    }

    private func completeCachedLoad(
        descriptor: CachedRemoteImageDescriptor,
        url: URL,
        image: UIImage,
        loader: CachedRemoteImageLoader,
        harness: ControlledImageLoadHarness
    ) async {
        let task = Task { @MainActor in
            await loader.load(descriptor: descriptor)
        }
        await harness.waitUntilResolutionIsSuspended(for: descriptor)
        await harness.resumeResolution(for: descriptor, with: url)
        await harness.waitUntilCacheLookupIsSuspended(for: url)
        await harness.resumeCacheLookup(for: url, with: image)
        await task.value
    }

    private func makeImage(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private static let descriptorA = CachedRemoteImageDescriptor(
        itemID: "item-a",
        type: .primary,
        width: 640,
        quality: 82
    )
    private static let descriptorB = CachedRemoteImageDescriptor(
        itemID: "item-b",
        type: .primary,
        width: 640,
        quality: 82
    )
    private static let urlA = URL(string: "https://a.example/image")!
    private static let urlB = URL(string: "https://b.example/image")!
    private static let fallbackURLA = URL(string: "https://a.example/fallback")!
}

private enum TestImageError: Error {
    case failed
}

private actor ControlledImageLoadHarness {
    private var resolutionContinuations = [CachedRemoteImageDescriptor: CheckedContinuation<URL?, Never>]()
    private var resolutionWaiters = [CachedRemoteImageDescriptor: [CheckedContinuation<Void, Never>]]()
    private var cacheContinuations = [URL: CheckedContinuation<UIImage?, Never>]()
    private var cacheWaiters = [URL: [CheckedContinuation<Void, Never>]]()
    private var downloadContinuations = [URL: CheckedContinuation<UIImage, Error>]()
    private var downloadWaiters = [URL: [CheckedContinuation<Void, Never>]]()
    nonisolated private let cancellationRecorder = ImageCancellationRecorder()

    nonisolated var cancelledRequests: [CachedRemoteImageCancellation] {
        cancellationRecorder.requests
    }

    func resolveURL(for descriptor: CachedRemoteImageDescriptor) async -> URL? {
        await withCheckedContinuation { continuation in
            resolutionContinuations[descriptor] = continuation
            resolutionWaiters.removeValue(forKey: descriptor)?.forEach { $0.resume() }
        }
    }

    func waitUntilResolutionIsSuspended(for descriptor: CachedRemoteImageDescriptor) async {
        guard resolutionContinuations[descriptor] == nil else { return }
        await withCheckedContinuation { continuation in
            resolutionWaiters[descriptor, default: []].append(continuation)
        }
    }

    func resumeResolution(for descriptor: CachedRemoteImageDescriptor, with url: URL?) {
        resolutionContinuations.removeValue(forKey: descriptor)?.resume(returning: url)
    }

    func cachedImage(for url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            cacheContinuations[url] = continuation
            cacheWaiters.removeValue(forKey: url)?.forEach { $0.resume() }
        }
    }

    func waitUntilCacheLookupIsSuspended(for url: URL) async {
        guard cacheContinuations[url] == nil else { return }
        await withCheckedContinuation { continuation in
            cacheWaiters[url, default: []].append(continuation)
        }
    }

    func resumeCacheLookup(for url: URL, with image: UIImage?) {
        cacheContinuations.removeValue(forKey: url)?.resume(returning: image)
    }

    func fetchImage(for url: URL, consumerID: ImageRequestConsumerID) async throws -> UIImage {
        _ = consumerID
        return try await withCheckedThrowingContinuation { continuation in
            downloadContinuations[url] = continuation
            downloadWaiters.removeValue(forKey: url)?.forEach { $0.resume() }
        }
    }

    func waitUntilDownloadIsSuspended(for url: URL) async {
        guard downloadContinuations[url] == nil else { return }
        await withCheckedContinuation { continuation in
            downloadWaiters[url, default: []].append(continuation)
        }
    }

    func resumeDownload(for url: URL, with result: Result<UIImage, Error>) {
        guard let continuation = downloadContinuations.removeValue(forKey: url) else { return }
        continuation.resume(with: result)
    }

    nonisolated func recordCancellation(url: URL, consumerID: ImageRequestConsumerID) {
        cancellationRecorder.record(
            CachedRemoteImageCancellation(url: url, consumerID: consumerID)
        )
    }
}

private final class ImageCancellationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [CachedRemoteImageCancellation]()

    var requests: [CachedRemoteImageCancellation] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ request: CachedRemoteImageCancellation) {
        lock.lock()
        storage.append(request)
        lock.unlock()
    }
}
