import Foundation
import Shared
import UIKit

actor ImageTaskRegistry {
    private var tasks: [URL: Task<UIImage, Error>] = [:]

    func existingTask(for url: URL) -> Task<UIImage, Error>? {
        tasks[url]
    }

    func register(task: Task<UIImage, Error>, for url: URL) {
        tasks[url] = task
    }

    func removeTask(for url: URL) {
        tasks[url] = nil
    }

    func cancel(url: URL) {
        tasks[url]?.cancel()
        tasks[url] = nil
    }
}

public final class DefaultImagePipeline: ImagePipelineProtocol, @unchecked Sendable {
    private let memoryCache = NSCache<NSURL, UIImage>()
    private let diskCache: LRUDiskCache
    private let urlSession: URLSession
    private let registry = ImageTaskRegistry()

    public init(
        diskCache: LRUDiskCache? = nil,
        urlSession: URLSession = .shared,
        memoryCapacity: Int = 220
    ) {
        self.diskCache = diskCache ?? (try? LRUDiskCache()) ?? {
            fatalError("Unable to initialize disk cache")
        }()
        self.urlSession = urlSession
        memoryCache.countLimit = memoryCapacity
        memoryCache.totalCostLimit = 130 * 1_024 * 1_024
    }

    public func image(for url: URL) async throws -> UIImage {
        let interval = SignpostInterval(signposter: Signpost.imageLoading, name: "image_request")

        if let memoryImage = memoryCache.object(forKey: url as NSURL) {
            interval.end(name: "image_request", message: "memory_hit")
            return memoryImage
        }

        if let diskData = await diskCache.data(forKey: url.absoluteString), let image = UIImage(data: diskData) {
            memoryCache.setObject(image, forKey: url as NSURL, cost: diskData.count)
            interval.end(name: "image_request", message: "disk_hit")
            return image
        }

        if let task = await registry.existingTask(for: url) {
            let image = try await task.value
            interval.end(name: "image_request", message: "dedupe_hit")
            return image
        }

        let task = Task<UIImage, Error> {
            let data = try await self.fetchImageData(url: url)

            guard let image = UIImage(data: data) else {
                throw AppError.decoding("Invalid image payload.")
            }

            self.memoryCache.setObject(image, forKey: url as NSURL, cost: data.count)
            await self.diskCache.setData(data, forKey: url.absoluteString)
            return image
        }

        await registry.register(task: task, for: url)

        do {
            let image = try await task.value
            await registry.removeTask(for: url)
            interval.end(name: "image_request", message: "network_hit")
            return image
        } catch {
            await registry.removeTask(for: url)
            interval.end(name: "image_request", message: "network_error")
            throw error
        }
    }

    private func fetchImageData(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Invalid image response.")
        }

        if (200 ..< 300).contains(httpResponse.statusCode) {
            return data
        }

        if (httpResponse.statusCode == 401 || httpResponse.statusCode == 403), let token = tokenFromImageURL(url) {
            var retryRequest = request
            retryRequest.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            let (retryData, retryResponse) = try await urlSession.data(for: retryRequest)
            if let retryHTTP = retryResponse as? HTTPURLResponse, (200 ..< 300).contains(retryHTTP.statusCode) {
                return retryData
            }
        }

        if httpResponse.statusCode == 404 {
            throw AppError.network("Image request failed (404)")
        }

        throw AppError.network("Image request failed (\(httpResponse.statusCode))")
    }

    private func tokenFromImageURL(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "api_key" })?.value
    }

    public func cachedImage(for url: URL) async -> UIImage? {
        if let image = memoryCache.object(forKey: url as NSURL) {
            return image
        }
        guard let data = await diskCache.data(forKey: url.absoluteString) else {
            return nil
        }
        guard let image = UIImage(data: data) else {
            return nil
        }
        memoryCache.setObject(image, forKey: url as NSURL, cost: data.count)
        return image
    }

    public func prefetch(urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls.prefix(36) {
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
}
