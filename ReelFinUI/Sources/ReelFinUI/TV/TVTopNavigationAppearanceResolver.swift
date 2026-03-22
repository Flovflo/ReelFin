import Shared
import UIKit

actor TVTopNavigationAppearanceResolver {
    private let apiClient: any JellyfinAPIClientProtocol
    private let imagePipeline: any ImagePipelineProtocol
    private var cache: [String: TVTopNavigationAppearance] = [:]

    init(
        apiClient: any JellyfinAPIClientProtocol,
        imagePipeline: any ImagePipelineProtocol
    ) {
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
    }

    func appearance(for item: MediaItem) async -> TVTopNavigationAppearance {
        if let cached = cache[item.id] {
            return cached
        }

        let fallback = TVTopNavigationAppearance.fallback(for: item)
        guard let url = await apiClient.imageURL(
            for: item.id,
            type: item.backdropTag == nil ? .primary : .backdrop,
            width: 640,
            quality: 70
        ) else {
            cache[item.id] = fallback
            return fallback
        }

        let image: UIImage?
        if let cached = await imagePipeline.cachedImage(for: url) {
            image = cached
        } else {
            image = try? await imagePipeline.image(for: url)
        }
        let appearance = image.map { TVArtworkColorAnalyzer.appearance(for: $0, fallback: fallback) } ?? fallback
        cache[item.id] = appearance
        return appearance
    }
}
