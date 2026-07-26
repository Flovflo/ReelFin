import Shared
import UIKit

struct CachedRemoteImageDescriptor: Hashable, Sendable {
    let itemID: String
    let type: JellyfinImageType
    let width: Int
    let quality: Int

    var contentKey: String {
        "\(itemID)-\(type.rawValue)"
    }

    func replacing(type: JellyfinImageType) -> CachedRemoteImageDescriptor {
        CachedRemoteImageDescriptor(itemID: itemID, type: type, width: width, quality: quality)
    }
}

@MainActor
final class CachedRemoteImageLoader: ObservableObject {
    typealias URLResolver = (CachedRemoteImageDescriptor) async -> URL?
    typealias CacheLookup = (URL) async -> UIImage?
    typealias ImageFetcher = (URL, ImageRequestConsumerID) async throws -> UIImage
    typealias Canceller = (URL, ImageRequestConsumerID) -> Void

    @Published private(set) var image: UIImage?

    private let resolveURL: URLResolver
    private let cachedImage: CacheLookup
    private let fetchImage: ImageFetcher
    private let cancelRequest: Canceller
    private var request = CachedRemoteImageRequestState()

    init(
        resolveURL: @escaping URLResolver,
        cachedImage: @escaping CacheLookup,
        fetchImage: @escaping ImageFetcher,
        cancel: @escaping Canceller
    ) {
        self.resolveURL = resolveURL
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
        if request.contentKey != descriptor.contentKey {
            image = nil
            request.contentKey = descriptor.contentKey
        }

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

        guard let url = await resolveURL(descriptor) else {
            return
        }
        guard isActive(token) else { return }
        cancel(request.attach(url, to: token))
        attachedURL = url

        if let cached = await cachedImage(url) {
            guard isActive(token) else { return }
            publish(cached, token: token, onImageLoaded: onImageLoaded)
            return
        }
        guard isActive(token) else { return }

        do {
            let downloaded = try await fetchImage(url, token.consumerID)
            guard isActive(token) else { return }
            publish(downloaded, token: token, onImageLoaded: onImageLoaded)
        } catch is CancellationError {
            return
        } catch {
            guard isActive(token) else { return }
            if CachedRemoteImage.shouldIgnoreImageError(error) {
                return
            }

            guard let fallbackType = CachedRemoteImage.fallbackType(for: descriptor.type) else {
                log(error: error, url: url, token: token)
                return
            }
            let fallbackDescriptor = descriptor.replacing(type: fallbackType)
            guard let fallbackURL = await resolveURL(fallbackDescriptor) else {
                guard isActive(token) else { return }
                log(error: error, url: url, token: token)
                return
            }
            guard isActive(token) else { return }
            cancel(request.attach(fallbackURL, to: token))
            attachedURL = fallbackURL

            do {
                let fallbackImage = try await fetchImage(fallbackURL, token.consumerID)
                guard isActive(token) else { return }
                publish(fallbackImage, token: token, onImageLoaded: onImageLoaded)
            } catch is CancellationError {
                return
            } catch {
                guard isActive(token) else { return }
                if !CachedRemoteImage.shouldIgnoreImageError(error) {
                    log(error: error, url: url, token: token)
                }
            }
        }
    }

    func invalidate() {
        let cancellation = request.invalidate()
        cancel(cancellation)
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
        onImageLoaded?()
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
