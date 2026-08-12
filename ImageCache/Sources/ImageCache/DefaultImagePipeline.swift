import Foundation
import Shared
import UIKit
import ImageIO

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

actor ImageLoadLimiter {
    enum Transition: Sendable {
        case queued(UUID)
        case willGrant(UUID)
    }

    private var availablePermits: Int
    private var waiting: [UUID: CheckedContinuation<UUID, Error>] = [:]
    private var granted: Set<UUID> = []
    private let transitionObserver: (@Sendable (Transition) -> Void)?

    init(
        maximumConcurrentLoads: Int,
        transitionObserver: (@Sendable (Transition) -> Void)? = nil
    ) {
        availablePermits = maximumConcurrentLoads
        self.transitionObserver = transitionObserver
    }

    func acquire() async throws -> UUID {
        let identifier = UUID()
        let grantedIdentifier = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard availablePermits > 0 else {
                    waiting[identifier] = continuation
                    transitionObserver?(.queued(identifier))
                    return
                }
                availablePermits -= 1
                granted.insert(identifier)
                continuation.resume(returning: identifier)
            }
        } onCancel: {
            Task { await self.cancel(identifier) }
        }
        do {
            try Task.checkCancellation()
            return grantedIdentifier
        } catch {
            release(grantedIdentifier)
            throw error
        }
    }

    func release(_ identifier: UUID) {
        guard granted.remove(identifier) != nil else { return }
        grantNextOrReturnPermit()
    }

    private func cancel(_ identifier: UUID) {
        if let continuation = waiting.removeValue(forKey: identifier) {
            continuation.resume(throwing: CancellationError())
            return
        }
        guard granted.remove(identifier) != nil else { return }
        grantNextOrReturnPermit()
    }

    private func grantNextOrReturnPermit() {
        if let identifier = waiting.keys.first, let continuation = waiting.removeValue(forKey: identifier) {
            granted.insert(identifier)
            transitionObserver?(.willGrant(identifier))
            continuation.resume(returning: identifier)
        } else {
            availablePermits += 1
        }
    }
}

public struct ImagePipelineLimits: Sendable {
    public var maximumEncodedBytes: Int
    public var maximumPixelCount: Int64
    public var maximumConcurrentLoads: Int

    public init(
        maximumEncodedBytes: Int = 12 * 1_024 * 1_024,
        maximumPixelCount: Int64 = 40_000_000,
        maximumConcurrentLoads: Int = 4
    ) {
        self.maximumEncodedBytes = max(maximumEncodedBytes, 1)
        self.maximumPixelCount = max(maximumPixelCount, 1)
        self.maximumConcurrentLoads = max(maximumConcurrentLoads, 1)
    }
}

public protocol ImageDataDecoding: Sendable {
    func decode(data: Data, maximumThumbnailPixelSize: Int) async -> UIImage?
}

public struct ImageIODecoder: ImageDataDecoding {
    public init() {}

    public func decode(data: Data, maximumThumbnailPixelSize: Int) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumThumbnailPixelSize
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value
    }
}

private final class ImageLoadTracker: @unchecked Sendable {
    var source: StaticString = "loaded"
}

public final class DefaultImagePipeline: ImagePipelineProtocol, @unchecked Sendable {
    private let memoryCache = NSCache<NSURL, UIImage>()
    private let diskCache: LRUDiskCache
    private let urlSession: URLSession
    private let tokenStore: TokenStoreProtocol
    private let registry = ImageTaskRegistry()
    private let limits: ImagePipelineLimits
    private let loadLimiter: ImageLoadLimiter
    private let decoder: any ImageDataDecoding

    public init(
        diskCache: LRUDiskCache? = nil,
        urlSession: URLSession? = nil,
        tokenStore: TokenStoreProtocol = KeychainTokenStore(),
        memoryCapacity: Int = 220,
        limits: ImagePipelineLimits = .init(),
        decoder: any ImageDataDecoding = ImageIODecoder()
    ) {
        self.diskCache = diskCache ?? Self.makeDiskCache()
        self.urlSession = urlSession ?? Self.makeImageSession()
        self.tokenStore = tokenStore
        self.limits = limits
        self.loadLimiter = ImageLoadLimiter(maximumConcurrentLoads: limits.maximumConcurrentLoads)
        self.decoder = decoder
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
            AppLog.caching.error("Image cache location fallback=temporary")
            return cache
        }

        let emergencyURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        if let cache = try? LRUDiskCache(directoryURL: emergencyURL, fileManager: fileManager) {
            AppLog.caching.fault("Image cache location fallback=emergency")
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
                let permit = try await self.loadLimiter.acquire()
                defer { Task { await self.loadLimiter.release(permit) } }
                try Task.checkCancellation()

                if let diskData = await self.diskCache.data(forKey: cacheKey, maximumSizeBytes: self.limits.maximumEncodedBytes) {
                    if self.isEncodedDataWithinLimit(diskData),
                       let image = await self.decodeImage(data: diskData, for: url) {
                        try Task.checkCancellation()
                        tracker.source = "disk_hit"
                        self.memoryCache.setObject(image, forKey: url as NSURL, cost: self.memoryCost(for: image))
                        return image
                    }
                    await self.diskCache.remove(forKey: cacheKey)
                }

                let data = try await self.fetchImageData(url: url)
                try Task.checkCancellation()

                guard let image = await self.decodeImage(data: data, for: url) else {
                    throw AppError.decoding("Invalid image payload.")
                }
                try Task.checkCancellation()

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

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Invalid image response.")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AppError.network("Image request failed (\(httpResponse.statusCode))")
        }

        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
              contentType.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).hasPrefix("image/") == true
        else {
            throw AppError.network("Image response is not an image.")
        }

        if let rawContentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let contentLength = Int(rawContentLength), contentLength > limits.maximumEncodedBytes {
            throw AppError.network("Image response exceeds the encoded-byte limit.")
        }

        var data = Data()
        data.reserveCapacity(min(limits.maximumEncodedBytes, 64 * 1_024))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limits.maximumEncodedBytes else {
                throw AppError.network("Image response exceeds the encoded-byte limit.")
            }
            data.append(byte)
        }
        return data
    }

    public func cachedImage(for url: URL) async -> UIImage? {
        if let image = memoryCache.object(forKey: url as NSURL) {
            return image
        }
        guard let permit = try? await loadLimiter.acquire() else {
            return nil
        }
        defer { Task { await self.loadLimiter.release(permit) } }
        guard let data = await diskCache.data(forKey: url.reelfinCacheKey, maximumSizeBytes: limits.maximumEncodedBytes) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        guard isEncodedDataWithinLimit(data) else {
            await diskCache.remove(forKey: url.reelfinCacheKey)
            return nil
        }
        guard let image = await decodeImage(data: data, for: url) else {
            guard !Task.isCancelled else { return nil }
            await diskCache.remove(forKey: url.reelfinCacheKey)
            return nil
        }
        guard !Task.isCancelled else { return nil }
        memoryCache.setObject(image, forKey: url as NSURL, cost: memoryCost(for: image))
        return image
    }

    public func prefetch(urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls.prefix(24) {
                guard !Task.isCancelled else { return }
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

    private func decodeImage(data: Data, for url: URL) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        guard isPixelCountWithinLimit(data: data) else {
            return nil
        }
        let maximumThumbnailPixelSize = min(
            max(requestedPixelSize(for: url), 320),
            max(Int(Double(limits.maximumPixelCount).squareRoot()), 1)
        )
        let image = await decoder.decode(data: data, maximumThumbnailPixelSize: maximumThumbnailPixelSize)
        guard !Task.isCancelled else { return nil }
        return image
    }

    private func isEncodedDataWithinLimit(_ data: Data) -> Bool {
        data.count <= limits.maximumEncodedBytes
    }

    private func isPixelCountWithinLimit(data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value,
              width > 0,
              height > 0
        else {
            return false
        }

        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        return !overflow && pixelCount <= limits.maximumPixelCount
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
