import JellyfinAPI
import PlaybackEngine
import Shared

public struct ReelFinDependencies {
    public let apiClient: JellyfinAPIClientProtocol
    public let repository: MetadataRepositoryProtocol
    public let imagePipeline: ImagePipelineProtocol
    public let syncEngine: SyncEngineProtocol
    public let settingsStore: SettingsStoreProtocol
    public let seriesCache: SeriesLookupCache
    public let makePlaybackSession: @MainActor () -> PlaybackSessionController

    public init(
        apiClient: JellyfinAPIClientProtocol,
        repository: MetadataRepositoryProtocol,
        imagePipeline: ImagePipelineProtocol,
        syncEngine: SyncEngineProtocol,
        settingsStore: SettingsStoreProtocol,
        seriesCache: SeriesLookupCache,
        makePlaybackSession: @escaping @MainActor () -> PlaybackSessionController
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.imagePipeline = imagePipeline
        self.syncEngine = syncEngine
        self.settingsStore = settingsStore
        self.seriesCache = seriesCache
        self.makePlaybackSession = makePlaybackSession
    }
}
