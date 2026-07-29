import Foundation
import Shared
import UIKit

actor ImageTaskRegistry {
    private struct Entry {
        var task: Task<UIImage, Error>
        var consumers: [ImageRequestConsumerID: ImageLoadPriority]
    }

    private var entries: [URL: Entry] = [:]

    func existingOrRegisterTask(
        for url: URL,
        consumer consumerID: ImageRequestConsumerID,
        priority: ImageLoadPriority,
        makeTask: () -> Task<UIImage, Error>
    ) throws -> (task: Task<UIImage, Error>, isNew: Bool) {
        try Task.checkCancellation()

        if var existing = entries[url] {
            existing.consumers[consumerID] = max(
                existing.consumers[consumerID] ?? priority,
                priority
            )
            entries[url] = existing
            return (existing.task, false)
        }

        let task = makeTask()
        entries[url] = Entry(
            task: task,
            consumers: [consumerID: priority]
        )
        return (task, true)
    }

    func effectivePriority(
        for url: URL,
        fallback: ImageLoadPriority
    ) -> ImageLoadPriority {
        entries[url]?.consumers.values.max() ?? fallback
    }

    func release(url: URL, consumer consumerID: ImageRequestConsumerID) {
        guard var entry = entries[url] else { return }
        entry.consumers[consumerID] = nil
        if entry.consumers.isEmpty {
            entry.task.cancel()
            entries[url] = nil
        } else {
            entries[url] = entry
        }
    }

    func hasConsumer(_ consumerID: ImageRequestConsumerID, for url: URL) -> Bool {
        entries[url]?.consumers[consumerID] != nil
    }

    func cancel(url: URL) {
        entries[url]?.task.cancel()
        entries[url] = nil
    }
}

private actor MissingImageResponseCache {
    private let timeToLive: TimeInterval
    private var expirationByURL = [URL: Date]()

    init(timeToLive: TimeInterval = 5 * 60) {
        self.timeToLive = timeToLive
    }

    func contains(_ url: URL, now: Date = Date()) -> Bool {
        guard let expiration = expirationByURL[url] else { return false }
        guard expiration > now else {
            expirationByURL[url] = nil
            return false
        }
        return true
    }

    func insert(_ url: URL, now: Date = Date()) {
        expirationByURL[url] = now.addingTimeInterval(timeToLive)
    }
}

private final class ImageLoadTracker: @unchecked Sendable {
    var source: StaticString = "loaded"
}

private final class ImageConsumerWaitGate: @unchecked Sendable {
    typealias Continuation = CheckedContinuation<UIImage, Error>

    private let lock = NSLock()
    private var continuation: Continuation?
    private var pendingResult: Result<UIImage, Error>?
    private var isFinished = false

    func install(_ continuation: Continuation) -> Bool {
        let pendingResult = lock.withLock { () -> Result<UIImage, Error>? in
            if isFinished {
                let result = self.pendingResult
                self.pendingResult = nil
                return result
            }
            self.continuation = continuation
            return nil
        }

        if let pendingResult {
            continuation.resume(with: pendingResult)
            return false
        }
        return true
    }

    func finish(with result: Result<UIImage, Error>) {
        let continuation = lock.withLock { () -> Continuation? in
            guard !isFinished else { return nil }
            isFinished = true
            if let continuation = self.continuation {
                self.continuation = nil
                return continuation
            }
            pendingResult = result
            return nil
        }
        continuation?.resume(with: result)
    }
}

private final class ImagePrefetchAdmissionController: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private let lock = NSLock()
    private var activeCount = 0
    private var waiters = [Waiter]()

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    var snapshot: (activeCount: Int, waitingCount: Int) {
        lock.withLock { (activeCount, waiters.count) }
    }

    func perform(_ operation: @escaping @Sendable () async -> Void) async {
        let waiterID = UUID()
        guard await acquire(waiterID: waiterID) else { return }
        defer { release() }

        guard !Task.isCancelled else { return }
        await operation()
    }

    private func acquire(waiterID: UUID) async -> Bool {
        guard !Task.isCancelled else { return false }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediateResult: Bool? = lock.withLock {
                    guard !Task.isCancelled else { return false }
                    guard activeCount >= limit else {
                        activeCount += 1
                        return true
                    }
                    waiters.append(Waiter(id: waiterID, continuation: continuation))
                    return nil
                }
                if let immediateResult {
                    continuation.resume(returning: immediateResult)
                }
            }
        } onCancel: {
            self.cancel(waiterID: waiterID)
        }
    }

    private func cancel(waiterID: UUID) {
        let continuation: CheckedContinuation<Bool, Never>? = lock.withLock {
            guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else {
                return nil
            }
            return waiters.remove(at: index).continuation
        }
        continuation?.resume(returning: false)
    }

    private func release() {
        let continuation: CheckedContinuation<Bool, Never>? = lock.withLock {
            if waiters.isEmpty {
                activeCount = max(activeCount - 1, 0)
                return nil
            }
            return waiters.removeFirst().continuation
        }
        continuation?.resume(returning: true)
    }
}

public final class DefaultImagePipeline: ImagePipelineProtocol, @unchecked Sendable {
    static let maximumConcurrentPrefetches = 4
    static let maximumPrefetchURLs = 24
    static let maximumConnectionsPerHost = 6

    var prefetchAdmissionSnapshot: (activeCount: Int, waitingCount: Int) {
        prefetchAdmission.snapshot
    }

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let diskCache: LRUDiskCache
    private let urlSession: URLSession
    private let tokenStore: TokenStoreProtocol
    private let registry = ImageTaskRegistry()
    private let missingResponses = MissingImageResponseCache()
    private let decodeScheduler = ImageDecodeScheduler()
    private let prefetchAdmission: ImagePrefetchAdmissionController

    public init(
        diskCache: LRUDiskCache? = nil,
        urlSession: URLSession? = nil,
        tokenStore: TokenStoreProtocol = KeychainTokenStore(),
        memoryCapacity: Int = 220
    ) {
        self.diskCache = diskCache ?? Self.makeDiskCache()
        self.urlSession = urlSession ?? Self.makeImageSession()
        self.tokenStore = tokenStore
        prefetchAdmission = ImagePrefetchAdmissionController(
            limit: Self.maximumConcurrentPrefetches
        )
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
        configuration.httpMaximumConnectionsPerHost = maximumConnectionsPerHost
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
        try await image(
            for: url,
            consumer: ImageRequestConsumerID(),
            priority: .visible
        )
    }

    public func image(for url: URL, consumer consumerID: ImageRequestConsumerID) async throws -> UIImage {
        try await image(for: url, consumer: consumerID, priority: .visible)
    }

    private func image(
        for url: URL,
        consumer consumerID: ImageRequestConsumerID,
        priority: ImageLoadPriority
    ) async throws -> UIImage {
        try Task.checkCancellation()
        let interval = SignpostInterval(signposter: Signpost.imageLoading, name: "image_request")

        if let memoryImage = memoryCache.object(forKey: url as NSURL) {
            interval.end(name: "image_request", message: "memory_hit")
            return memoryImage
        }

        let tracker = ImageLoadTracker()
        let cacheKey = url.reelfinCacheKey
        let registered = try await registry.existingOrRegisterTask(
            for: url,
            consumer: consumerID,
            priority: priority
        ) {
            Task(priority: priority.taskPriority) {
                if let diskData = await self.diskCache.data(forKey: cacheKey),
                   let image = try await self.decodeImage(
                       data: diskData,
                       for: url,
                       priority: await self.registry.effectivePriority(
                           for: url,
                           fallback: priority
                       )
                   ) {
                    tracker.source = "disk_hit"
                    self.memoryCache.setObject(image, forKey: url as NSURL, cost: self.memoryCost(for: image))
                    return image
                }

                let data = try await self.fetchImageData(url: url)

                guard let image = try await self.decodeImage(
                    data: data,
                    for: url,
                    priority: await self.registry.effectivePriority(
                        for: url,
                        fallback: priority
                    )
                ) else {
                    throw AppError.decoding("Invalid image payload.")
                }

                tracker.source = "network_hit"
                self.memoryCache.setObject(image, forKey: url as NSURL, cost: self.memoryCost(for: image))
                await self.diskCache.setData(data, forKey: cacheKey)
                return image
            }
        }

        do {
            let image = try await waitForImage(registered.task)
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

    private func waitForImage(_ task: Task<UIImage, Error>) async throws -> UIImage {
        let gate = ImageConsumerWaitGate()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                Task {
                    gate.finish(with: await task.result)
                }
            }
        } onCancel: {
            gate.finish(with: .failure(CancellationError()))
        }
    }

    private func fetchImageData(url: URL) async throws -> Data {
        if await missingResponses.contains(url) {
            throw AppError.network("Image request failed (cached 404)")
        }

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
            await missingResponses.insert(url)
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
                guard group.addTaskUnlessCancelled(operation: {
                    guard !Task.isCancelled else { return }
                    await self.prefetchAdmission.perform {
                        guard !Task.isCancelled else { return }
                        _ = try? await self.image(
                            for: url,
                            consumer: ImageRequestConsumerID(),
                            priority: .prefetch
                        )
                    }
                }) else {
                    group.cancelAll()
                    return
                }
            }

            while await group.next() != nil {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                guard let url = iterator.next() else { continue }
                guard group.addTaskUnlessCancelled(operation: {
                    guard !Task.isCancelled else { return }
                    await self.prefetchAdmission.perform {
                        guard !Task.isCancelled else { return }
                        _ = try? await self.image(
                            for: url,
                            consumer: ImageRequestConsumerID(),
                            priority: .prefetch
                        )
                    }
                }) else {
                    group.cancelAll()
                    return
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

    private func decodeImage(
        data: Data,
        for url: URL,
        priority: ImageLoadPriority = .visible
    ) async throws -> UIImage? {
        let maxPixelSize = max(requestedPixelSize(for: url), 320)
        return try await decodeScheduler.decode(
            data: data,
            maxPixelSize: maxPixelSize,
            priority: priority
        )
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

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
