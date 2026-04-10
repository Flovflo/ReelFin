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

private final class ImageLoadTracker: @unchecked Sendable {
    var source: StaticString = "loaded"
}

public final class DefaultImagePipeline: ImagePipelineProtocol, @unchecked Sendable {
    private let memoryCache = NSCache<NSURL, UIImage>()
    private let diskCache: LRUDiskCache
    private let urlSession: URLSession
    private let tokenStore: TokenStoreProtocol
    private let registry = ImageTaskRegistry()

    public init(
        diskCache: LRUDiskCache? = nil,
        urlSession: URLSession = .shared,
        tokenStore: TokenStoreProtocol = KeychainTokenStore(),
        memoryCapacity: Int = 220
    ) {
        self.diskCache = diskCache ?? Self.makeDiskCache()
        self.urlSession = urlSession
        self.tokenStore = tokenStore
        memoryCache.countLimit = memoryCapacity
        memoryCache.totalCostLimit = 130 * 1_024 * 1_024
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
                   let image = await self.decodeImage(data: diskData, for: url) {
                    tracker.source = "disk_hit"
                    self.memoryCache.setObject(image, forKey: url as NSURL, cost: self.memoryCost(for: image))
                    return image
                }

                let data = try await self.fetchImageData(url: url)

                guard let image = await self.decodeImage(data: data, for: url) else {
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
        guard let image = await decodeImage(data: data, for: url) else {
            return nil
        }
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
        let maxPixelSize = max(requestedPixelSize(for: url), 320)
        return await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return UIImage(data: data)
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]

            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return UIImage(cgImage: cgImage)
            }

            return UIImage(data: data)
        }.value
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
