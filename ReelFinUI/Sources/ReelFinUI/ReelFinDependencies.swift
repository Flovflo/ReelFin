import JellyfinAPI
import PlaybackEngine
import Shared

public struct ReelFinDependencies {
    public let apiClient: JellyfinAPIClientProtocol
    public let repository: MetadataRepositoryProtocol
    public let detailRepository: MediaDetailRepositoryProtocol
    public let imagePipeline: ImagePipelineProtocol
    public let syncEngine: SyncEngineProtocol
    public let settingsStore: SettingsStoreProtocol
    public let episodeReleaseNotificationManager: EpisodeReleaseNotificationManaging
    public let seriesCache: SeriesLookupCache
    public let playbackWarmupManager: PlaybackWarmupManaging
    public let tvFocusWarmupCoordinator: TVFocusWarmupCoordinator?
    public let makePlaybackSession: @MainActor () -> PlaybackSessionController

    public init(
        apiClient: JellyfinAPIClientProtocol,
        repository: MetadataRepositoryProtocol,
        detailRepository: MediaDetailRepositoryProtocol,
        imagePipeline: ImagePipelineProtocol,
        syncEngine: SyncEngineProtocol,
        settingsStore: SettingsStoreProtocol,
        episodeReleaseNotificationManager: EpisodeReleaseNotificationManaging,
        seriesCache: SeriesLookupCache,
        playbackWarmupManager: PlaybackWarmupManaging,
        tvFocusWarmupCoordinator: TVFocusWarmupCoordinator? = nil,
        makePlaybackSession: @escaping @MainActor () -> PlaybackSessionController
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.detailRepository = detailRepository
        self.imagePipeline = imagePipeline
        self.syncEngine = syncEngine
        self.settingsStore = settingsStore
        self.episodeReleaseNotificationManager = episodeReleaseNotificationManager
        self.seriesCache = seriesCache
        self.playbackWarmupManager = playbackWarmupManager
        self.tvFocusWarmupCoordinator = tvFocusWarmupCoordinator
        self.makePlaybackSession = makePlaybackSession
    }
}
