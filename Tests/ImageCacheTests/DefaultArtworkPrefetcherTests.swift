import Foundation
@testable import ImageCache
import Shared
import UIKit
import XCTest

final class DefaultArtworkPrefetcherTests: XCTestCase {
    func testResolvesRequestsDeduplicatesURLsInFirstSeenOrderAndStartsOnePipelineBatch() async {
        let firstItem = MediaItem(id: "first", name: "First", posterTag: "first")
        let duplicateItem = MediaItem(id: "duplicate", name: "Duplicate", posterTag: "duplicate")
        let missingItem = MediaItem(id: "missing", name: "Missing", posterTag: "missing")
        let lastItem = MediaItem(id: "last", name: "Last", posterTag: "last")
        let requests = [firstItem, duplicateItem, missingItem, lastItem]
            .map { ArtworkRequest.make(for: $0, role: .posterRow) }
        let firstURL = URL(string: "https://example.com/first")!
        let lastURL = URL(string: "https://example.com/last")!
        let provider = RecordingArtworkURLProvider(
            resolvedURLs: [firstURL, firstURL, nil, lastURL]
        )
        let pipeline = RecordingImagePipeline()
        let prefetcher = DefaultArtworkPrefetcher(urlProvider: provider, imagePipeline: pipeline)

        await prefetcher.prefetch(requests)

        let resolvedRequests = await provider.capturedRequests
        let batches = await pipeline.prefetchBatches
        XCTAssertEqual(resolvedRequests, requests)
        XCTAssertEqual(batches, [[firstURL, lastURL]])
    }

    func testSkipsTaglessRequestsDuringSpeculativePrefetch() async {
        let tagless = ArtworkRequest.make(
            for: MediaItem(id: "tagless", name: "Tagless"),
            role: .posterRow
        )
        let available = ArtworkRequest.make(
            for: MediaItem(id: "available", name: "Available", posterTag: "primary"),
            role: .posterRow
        )
        let availableURL = URL(string: "https://example.com/available")!
        let provider = RecordingArtworkURLProvider(resolvedURLs: [availableURL])
        let pipeline = RecordingImagePipeline()
        let prefetcher = DefaultArtworkPrefetcher(urlProvider: provider, imagePipeline: pipeline)

        await prefetcher.prefetch([tagless, available])

        let resolvedRequests = await provider.capturedRequests
        let batches = await pipeline.prefetchBatches
        XCTAssertEqual(resolvedRequests, [available])
        XCTAssertEqual(batches, [[availableURL]])
    }

    func testCancellationDuringURLResolutionStopsResolutionAndPreventsPipelineStart() async throws {
        let provider = BlockingArtworkURLProvider()
        let pipeline = RecordingImagePipeline()
        let prefetcher = DefaultArtworkPrefetcher(urlProvider: provider, imagePipeline: pipeline)
        let requests = [
            MediaItem(id: "first", name: "First", posterTag: "first"),
            MediaItem(id: "second", name: "Second", posterTag: "second")
        ].map { ArtworkRequest.make(for: $0, role: .posterRow) }

        let task = Task {
            await prefetcher.prefetch(requests)
        }

        try await waitUntil { await provider.resolutionCount == 1 }
        task.cancel()
        await provider.resume(with: URL(string: "https://example.com/first")!)
        await task.value

        let resolutionCount = await provider.resolutionCount
        let batches = await pipeline.prefetchBatches
        XCTAssertEqual(resolutionCount, 1)
        XCTAssertTrue(batches.isEmpty)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

private actor RecordingArtworkURLProvider: ArtworkURLProviding {
    private let resolvedURLs: [URL?]
    private(set) var capturedRequests = [ArtworkRequest]()

    init(resolvedURLs: [URL?]) {
        self.resolvedURLs = resolvedURLs
    }

    func imageURL(for request: ArtworkRequest) async -> URL? {
        capturedRequests.append(request)
        return resolvedURLs[capturedRequests.count - 1]
    }
}

private actor BlockingArtworkURLProvider: ArtworkURLProviding {
    private var continuation: CheckedContinuation<URL?, Never>?
    private(set) var resolutionCount = 0

    func imageURL(for request: ArtworkRequest) async -> URL? {
        _ = request
        resolutionCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with url: URL?) {
        continuation?.resume(returning: url)
        continuation = nil
    }
}

private actor RecordingImagePipeline: ImagePipelineProtocol {
    private(set) var prefetchBatches = [[URL]]()

    func image(for url: URL) async throws -> UIImage {
        _ = url
        throw CancellationError()
    }

    func image(for url: URL, consumer consumerID: ImageRequestConsumerID) async throws -> UIImage {
        _ = url
        _ = consumerID
        throw CancellationError()
    }

    func cachedImage(for url: URL) async -> UIImage? {
        _ = url
        return nil
    }

    func prefetch(urls: [URL]) async {
        prefetchBatches.append(urls)
    }

    nonisolated func cancel(url: URL) {
        _ = url
    }

    nonisolated func cancel(url: URL, consumer consumerID: ImageRequestConsumerID) {
        _ = url
        _ = consumerID
    }
}
