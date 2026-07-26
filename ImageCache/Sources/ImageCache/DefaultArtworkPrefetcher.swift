import Foundation
import Shared

public actor DefaultArtworkPrefetcher: ArtworkPrefetching {
    private let urlProvider: any ArtworkURLProviding
    private let imagePipeline: any ImagePipelineProtocol

    public init(
        urlProvider: any ArtworkURLProviding,
        imagePipeline: any ImagePipelineProtocol
    ) {
        self.urlProvider = urlProvider
        self.imagePipeline = imagePipeline
    }

    public func prefetch(_ requests: [ArtworkRequest]) async {
        var urls = [URL]()
        var seenURLs = Set<URL>()

        for request in requests {
            guard !Task.isCancelled else { return }
            let url = await urlProvider.imageURL(for: request)
            guard !Task.isCancelled else { return }
            guard let url, seenURLs.insert(url).inserted else { continue }
            urls.append(url)
        }

        guard !Task.isCancelled, !urls.isEmpty else { return }
        await imagePipeline.prefetch(urls: urls)
    }
}
