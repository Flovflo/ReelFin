import Shared

actor ArtworkPrefetcherTestDouble: ArtworkPrefetching {
    func prefetch(_ requests: [ArtworkRequest]) async {
        _ = requests
    }
}
