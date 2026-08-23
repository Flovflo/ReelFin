import Shared

actor ArtworkPrefetcherTestDouble: ArtworkPrefetching {
    private var batches = [[ArtworkRequest]]()

    func prefetch(_ requests: [ArtworkRequest]) async {
        batches.append(requests)
    }

    func capturedRequests() -> [ArtworkRequest] {
        batches.flatMap { $0 }
    }
}
