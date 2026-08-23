import Shared
import UIKit

struct CachedRemoteImageDescriptor: Hashable, Sendable {
    let itemID: String
    let type: JellyfinImageType
    let width: Int
    let quality: Int
    let shouldProbeLocal: Bool

    init(
        itemID: String,
        type: JellyfinImageType,
        width: Int,
        quality: Int,
        shouldProbeLocal: Bool = true
    ) {
        self.itemID = itemID
        self.type = type
        self.width = width
        self.quality = quality
        self.shouldProbeLocal = shouldProbeLocal
    }

    var contentKey: String {
        "\(itemID)-\(type.rawValue)"
    }

    func replacing(type: JellyfinImageType) -> CachedRemoteImageDescriptor {
        CachedRemoteImageDescriptor(
            itemID: itemID,
            type: type,
            width: width,
            quality: quality,
            shouldProbeLocal: shouldProbeLocal
        )
    }
}

@MainActor
final class CachedRemoteImageLoader: ObservableObject {
    typealias URLResolver = (CachedRemoteImageDescriptor) async -> URL?
    typealias CacheLookup = (URL) async -> UIImage?
    typealias ImageFetcher = (URL, ImageRequestConsumerID) async throws -> UIImage
    typealias Canceller = (URL, ImageRequestConsumerID) -> Void

    @Published private(set) var image: UIImage?
    @Published private(set) var hasFailed = false

    private let resolveURL: URLResolver
    private let resolveRemoteURL: URLResolver
    private let cachedImage: CacheLookup
    private let fetchImage: ImageFetcher
    private let cancelRequest: Canceller
    private var request = CachedRemoteImageRequestState()

    init(
        resolveURL: @escaping URLResolver,
        resolveRemoteURL: @escaping URLResolver = { _ in nil },
        cachedImage: @escaping CacheLookup,
        fetchImage: @escaping ImageFetcher,
        cancel: @escaping Canceller
    ) {
        self.resolveURL = resolveURL
        self.resolveRemoteURL = resolveRemoteURL
        self.cachedImage = cachedImage
        self.fetchImage = fetchImage
        cancelRequest = cancel
    }

    convenience init(
        apiClient: any JellyfinAPIClientProtocol,
        imagePipeline: any ImagePipelineProtocol
    ) {
        self.init(
            resolveURL: { descriptor in
                await apiClient.imageURL(
                    for: descriptor.itemID,
                    type: descriptor.type,
                    width: descriptor.width,
                    quality: descriptor.quality
                )
            },
            resolveRemoteURL: { descriptor in
                await apiClient.remoteImageURL(
                    for: descriptor.itemID,
                    type: descriptor.type,
                    width: descriptor.width
                )
            },
            cachedImage: { url in
                await imagePipeline.cachedImage(for: url)
            },
            fetchImage: { url, consumerID in
                try await imagePipeline.image(for: url, consumer: consumerID)
            },
            cancel: { url, consumerID in
                imagePipeline.cancel(url: url, consumer: consumerID)
            }
        )
    }

    func load(
        descriptor: CachedRemoteImageDescriptor,
        onImageLoaded: (() -> Void)? = nil
    ) async {
        guard !Task.isCancelled else { return }

        if request.contentKey != descriptor.contentKey {
            image = nil
            request.contentKey = descriptor.contentKey
        }
        hasFailed = false

        let start = request.begin()
        cancel(start.cancellation)
        let token = start.token
        var attachedURL: URL?
        defer {
            if let attachedURL {
                cancelRequest(attachedURL, token.consumerID)
            }
            request.finish(token)
        }

        let fallbackDescriptor = CachedRemoteImage.fallbackType(for: descriptor.type)
            .map { descriptor.replacing(type: $0) }
        var candidates = [(resolver: URLResolver, descriptor: CachedRemoteImageDescriptor, checksCache: Bool)]()
        if descriptor.shouldProbeLocal {
            candidates.append((resolveURL, descriptor, true))
            if let fallbackDescriptor {
                // Preserve the existing hot fallback path; this URL has not been resolved before,
                // while the image pipeline itself still checks memory and disk.
                candidates.append((resolveURL, fallbackDescriptor, false))
            }
        }
        candidates.append((resolveRemoteURL, descriptor, true))
        if let fallbackDescriptor {
            candidates.append((resolveRemoteURL, fallbackDescriptor, true))
        }

        var lastFailure: (error: Error, url: URL)?
        var attemptedURLs = Set<URL>()
        for candidate in candidates {
            let resolvedURL = await candidate.resolver(candidate.descriptor)
            guard isActive(token) else { return }
            guard let url = resolvedURL, attemptedURLs.insert(url).inserted else { continue }

            cancel(request.attach(url, to: token))
            attachedURL = url

            if candidate.checksCache, let cached = await cachedImage(url) {
                guard isActive(token) else { return }
                publish(cached, token: token, onImageLoaded: onImageLoaded)
                return
            }
            guard isActive(token) else { return }

            do {
                let downloaded = try await fetchImage(url, token.consumerID)
                guard isActive(token) else { return }
                publish(downloaded, token: token, onImageLoaded: onImageLoaded)
                return
            } catch is CancellationError {
                return
            } catch {
                guard isActive(token) else { return }
                lastFailure = (error, url)
            }
        }

        if let lastFailure, !CachedRemoteImage.shouldIgnoreImageError(lastFailure.error) {
            log(error: lastFailure.error, url: lastFailure.url, token: token)
        }
        publishFailure(token: token)
    }

    func invalidate() {
        let cancellation = request.invalidate()
        cancel(cancellation)
    }

    func clear(for descriptor: CachedRemoteImageDescriptor) {
        let cancellation = request.invalidate()
        cancel(cancellation)
        request.contentKey = descriptor.contentKey
        image = nil
        hasFailed = false
    }

    private func isActive(_ token: CachedRemoteImageRequestToken) -> Bool {
        !Task.isCancelled && request.owns(token)
    }

    private func publish(
        _ image: UIImage,
        token: CachedRemoteImageRequestToken,
        onImageLoaded: (() -> Void)?
    ) {
        guard isActive(token) else { return }
        self.image = image
        hasFailed = false
        onImageLoaded?()
    }

    private func publishFailure(token: CachedRemoteImageRequestToken) {
        guard isActive(token) else { return }
        image = nil
        hasFailed = true
    }

    private func cancel(_ cancellation: CachedRemoteImageCancellation?) {
        guard let cancellation else { return }
        cancelRequest(cancellation.url, cancellation.consumerID)
    }

    private func log(error: Error, url: URL, token: CachedRemoteImageRequestToken) {
        guard isActive(token) else { return }
        AppLog.caching.error(
            "Image load failed for \(url.reelfinLogString, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }
}
