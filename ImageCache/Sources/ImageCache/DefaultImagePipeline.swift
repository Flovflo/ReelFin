import Foundation
import Shared
import UIKit

actor ImageTaskRegistry {
    private struct Entry {
        var task: Task<UIImage, Error>
        var consumers: Set<ImageRequestConsumerID>
    }

    private var entries: [URL: Entry] = [:]

    func existingOrRegisterTask(
        for url: URL,
        consumer consumerID: ImageRequestConsumerID,
        makeTask: () -> Task<UIImage, Error>
    ) -> (task: Task<UIImage, Error>, isNew: Bool) {
        if var existing = entries[url] {
            existing.consumers.insert(consumerID)
            entries[url] = existing
            return (existing.task, false)
        }

        let task = makeTask()
        entries[url] = Entry(task: task, consumers: [consumerID])
        return (task, true)
    }

    func release(url: URL, consumer consumerID: ImageRequestConsumerID) {
        guard var entry = entries[url] else { return }
        entry.consumers.remove(consumerID)
        if entry.consumers.isEmpty {
            entry.task.cancel()
            entries[url] = nil
        } else {
            entries[url] = entry
        }
    }

    func hasConsumer(_ consumerID: ImageRequestConsumerID, for url: URL) -> Bool {
        entries[url]?.consumers.contains(consumerID) == true
    }

    func cancel(url: URL) {
        entries[url]?.task.cancel()
        entries[url] = nil
    }
}

private final class ImageLoadTracker: @unchecked Sendable {
    var source: StaticString = "loaded"
}

public final class DefaultImagePipeline: ImagePipelineProtocol, @unchecked Sendable {
    static let maximumConcurrentPrefetches = 4
    static let maximumPrefetchURLs = 24

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let diskCache: LRUDiskCache
    private let urlSession: URLSession
    private let tokenStore: TokenStoreProtocol
    private let registry = ImageTaskRegistry()
    private let decodeScheduler = ImageDecodeScheduler()

    public init(
        diskCache: LRUDiskCache? = nil,
        urlSession: URLSession? = nil,
        tokenStore: TokenStoreProtocol = KeychainTokenStore(),
        memoryCapacity: Int = 220
    ) {
        self.diskCache = diskCache ?? Self.makeDiskCache()
        self.urlSession = urlSession ?? Self.makeImageSession()
        self.tokenStore = tokenStore
        memoryCache.countLimit = memoryCapacity
        memoryCache.totalCostLimit = 130 * 1_024 * 1_024
    }

    /// Dedicated transport for artwork. On `URLSession.shared`, a burst of image fetches queued
    /// on the SAME per-host connections as the API/sync/PlaybackInfo traffic — on a degraded link
    /// images at 20s timeouts kept the pool wedged for the requests users actually wait on.
    /// Bounded connections + shorter timeouts; caching stays ours (the LRU disk cache).
    private static func makeImageSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    private static func makeDiskCache(fileManager: FileManager = .default) -> LRUDiskCache {
        if let cache = try? LRUDiskCache(fileManager: fileManager) {
            return cache
        }

        let fallbackURL = fileManager.temporaryDirectory.appendingPathComponent("ReelFinImageCache", isDirectory: true)
        if let cache = try? LRUDiskCache(directoryURL: fallbackURL, fileManager: fileManager) {
            AppLog.caching.error("Falling back to temporary directory for image cache at \(fallbackURL.path, privacy: .public)")
            return cache
        }

        let emergencyURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        if let cache = try? LRUDiskCache(directoryURL: emergencyURL, fileManager: fileManager) {
            AppLog.caching.fault("Image cache initialization required emergency fallback at \(emergencyURL.path, privacy: .public)")
            return cache
        }

        preconditionFailure("Unable to initialize image cache in caches or temporary directories.")
    }

    public func image(for url: URL) async throws -> UIImage {
        try await image(for: url, consumer: ImageRequestConsumerID())
    }

    public func image(for url: URL, consumer consumerID: ImageRequestConsumerID) async throws -> UIImage {
        let interval = SignpostInterval(signposter: Signpost.imageLoading, name: "image_request")

        if let memoryImage = memoryCache.object(forKey: url as NSURL) {
            interval.end(name: "image_request", message: "memory_hit")
            return memoryImage
        }

        let tracker = ImageLoadTracker()
        let cacheKey = url.reelfinCacheKey
        let registered = await registry.existingOrRegisterTask(for: url, consumer: consumerID) {
            Task {
                if let diskData = await self.diskCache.data(forKey: cacheKey),
                   let image = try await self.decodeImage(data: diskData, for: url) {
                    tracker.source = "disk_hit"
                    self.memoryCache.setObject(image, forKey: url as NSURL, cost: self.memoryCost(for: image))
                    return image
                }

                let data = try await self.fetchImageData(url: url)

                guard let image = try await self.decodeImage(data: data, for: url) else {
                    throw AppError.decoding("Invalid image payload.")
                }

                tracker.source = "network_hit"
                self.memoryCache.setObject(image, forKey: url as NSURL, cost: self.memoryCost(for: image))
                await self.diskCache.setData(data, forKey: cacheKey)
                return image
            }
        }

        do {
            let image = try await registered.task.value
            try Task.checkCancellation()
            guard await registry.hasConsumer(consumerID, for: url) else {
                throw CancellationError()
            }
            interval.end(name: "image_request", message: registered.isNew ? tracker.source : "dedupe_hit")
            await self.registry.release(url: url, consumer: consumerID)
            return image
        } catch {
            interval.end(name: "image_request", message: "network_error")
            await self.registry.release(url: url, consumer: consumerID)
            throw error
        }
    }

    private func fetchImageData(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        if let token = try? tokenStore.fetchToken(), !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Invalid image response.")
        }

        if (200 ..< 300).contains(httpResponse.statusCode) {
            return data
        }

        if httpResponse.statusCode == 404 {
            throw AppError.network("Image request failed (404)")
        }

        throw AppError.network("Image request failed (\(httpResponse.statusCode))")
    }

    public func cachedImage(for url: URL) async -> UIImage? {
        if let image = memoryCache.object(forKey: url as NSURL) {
            return image
        }
        guard let data = await diskCache.data(forKey: url.reelfinCacheKey) else {
            return nil
        }
        let image: UIImage
        do {
            guard let decodedImage = try await decodeImage(data: data, for: url) else {
                return nil
            }
            image = decodedImage
        } catch {
            return nil
        }
        memoryCache.setObject(image, forKey: url as NSURL, cost: memoryCost(for: image))
        return image
    }

    public func prefetch(urls: [URL]) async {
        var seenURLs = Set<URL>()
        var candidates = [URL]()
        candidates.reserveCapacity(min(urls.count, Self.maximumPrefetchURLs))
        for url in urls where seenURLs.insert(url).inserted {
            candidates.append(url)
            if candidates.count == Self.maximumPrefetchURLs {
                break
            }
        }
        var iterator = candidates.makeIterator()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< Self.maximumConcurrentPrefetches {
                guard !Task.isCancelled, let url = iterator.next() else {
                    if Task.isCancelled {
                        group.cancelAll()
                    }
                    return
                }
                group.addTask {
                    _ = try? await self.image(for: url)
                }
            }

            while await group.next() != nil {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                guard let url = iterator.next() else { continue }
                group.addTask {
                    _ = try? await self.image(for: url)
                }
            }
        }
    }

    public func cancel(url: URL) {
        let taskRegistry = registry
        Task {
            await taskRegistry.cancel(url: url)
        }
    }

    public func cancel(url: URL, consumer consumerID: ImageRequestConsumerID) {
        let taskRegistry = registry
        Task {
            await taskRegistry.release(url: url, consumer: consumerID)
        }
    }

    private func decodeImage(data: Data, for url: URL) async throws -> UIImage? {
        let maxPixelSize = max(requestedPixelSize(for: url), 320)
        return try await decodeScheduler.decode(data: data, maxPixelSize: maxPixelSize)
    }

    private func requestedPixelSize(for url: URL) -> Int {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let rawWidth = components.queryItems?.first(where: { $0.name == "maxWidth" })?.value,
            let width = Int(rawWidth)
        else {
            return 1_280
        }

        return width
    }

    private func memoryCost(for image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }

        let scale = max(image.scale, 1)
        let width = max(Int((image.size.width * scale).rounded(.up)), 1)
        let height = max(Int((image.size.height * scale).rounded(.up)), 1)
        return width * height * 4
    }
}
