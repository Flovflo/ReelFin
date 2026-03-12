import DataStore
import ImageCache
import JellyfinAPI
import PlaybackEngine
import ReelFinUI
import Shared
import SyncEngine
import Foundation

enum TVAppBootstrap {
    @MainActor
    static func makeDependencies(metadata: AppMetadata) -> ReelFinDependencies {
        if metadata.isMockModeEnabled || metadata.isScreenshotModeEnabled {
            let arguments = Set(ProcessInfo.processInfo.arguments)
            let shouldStartLoggedOut = arguments.contains(AppMetadata.mockLoggedOutArgument)
            return ReelFinPreviewFactory.appStoreDependencies(authenticated: !shouldStartLoggedOut)
        }

        let container = TVAppContainer()
        return container.makeDependencies()
    }
}

final class TVAppContainer {
    let settingsStore: SettingsStoreProtocol
    let tokenStore: TokenStoreProtocol
    let apiClient: JellyfinAPIClient
    let repository: any MetadataRepositoryProtocol & Sendable
    let detailRepository: any MediaDetailRepositoryProtocol & Sendable
    let imagePipeline: DefaultImagePipeline
    let syncEngine: DefaultSyncEngine
    let seriesCache: SeriesLookupCache
    let playbackWarmupManager: PlaybackWarmupManager

    init() {
        settingsStore = DefaultSettingsStore()
        tokenStore = KeychainTokenStore()
        apiClient = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settingsStore)

        do {
            repository = try GRDBMetadataRepository()
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("reelfin-tv-fallback.sqlite")
            do {
                repository = try GRDBMetadataRepository(databaseURL: fallbackURL)
            } catch {
                AppLog.persistence.fault(
                    "Metadata database initialization failed twice. Falling back to non-persistent repository: \(error.localizedDescription, privacy: .public)"
                )
                repository = NullMetadataRepository()
            }
        }

        imagePipeline = DefaultImagePipeline()
        detailRepository = DefaultMediaDetailRepository(
            apiClient: apiClient,
            repository: repository
        )
        syncEngine = DefaultSyncEngine(
            apiClient: apiClient,
            repository: repository,
            imagePipeline: imagePipeline
        )
        seriesCache = SeriesLookupCache(apiClient: apiClient)
        playbackWarmupManager = PlaybackWarmupManager(apiClient: apiClient)
    }

    @MainActor
    func makeDependencies() -> ReelFinDependencies {
        ReelFinDependencies(
            apiClient: apiClient,
            repository: repository,
            detailRepository: detailRepository,
            imagePipeline: imagePipeline,
            syncEngine: syncEngine,
            settingsStore: settingsStore,
            seriesCache: seriesCache,
            playbackWarmupManager: playbackWarmupManager,
            makePlaybackSession: {
                PlaybackSessionController(
                    apiClient: self.apiClient,
                    repository: self.repository,
                    warmupManager: self.playbackWarmupManager
                )
            }
        )
    }
}
