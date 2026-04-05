import DataStore
import ImageCache
import JellyfinAPI
import PlaybackEngine
import ReelFinUI
import Shared
import SyncEngine
import Foundation

final class AppContainer {
    let settingsStore: SettingsStoreProtocol
    let tokenStore: TokenStoreProtocol
    let apiClient: JellyfinAPIClient
    let repository: any MetadataRepositoryProtocol & Sendable
    let detailRepository: any MediaDetailRepositoryProtocol & Sendable
    let imagePipeline: DefaultImagePipeline
    let syncEngine: DefaultSyncEngine
    let seriesCache: SeriesLookupCache
    let playbackWarmupManager: PlaybackWarmupManager
    let tvFocusWarmupCoordinator: TVFocusWarmupCoordinator
    private var sharedPlaybackSessionController: PlaybackSessionController?

    init() {
        let settingsStore = DefaultSettingsStore()
        let tokenStore = KeychainTokenStore()
        let apiClient = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settingsStore)
        Self.applyUITestResetIfNeeded(settingsStore: settingsStore, tokenStore: tokenStore)

        self.settingsStore = settingsStore
        self.tokenStore = tokenStore
        self.apiClient = apiClient

        do {
            repository = try GRDBMetadataRepository()
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("reelfin-fallback.sqlite")
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
        tvFocusWarmupCoordinator = TVFocusWarmupCoordinator()
    }

    private static func applyUITestResetIfNeeded(
        settingsStore: SettingsStoreProtocol,
        tokenStore: TokenStoreProtocol
    ) {
        let arguments = Set(ProcessInfo.processInfo.arguments)
        guard arguments.contains(AppMetadata.uiResetAuthStateArgument) else { return }

        settingsStore.serverConfiguration = nil
        settingsStore.lastSession = nil
        settingsStore.hasCompletedOnboarding = false
        settingsStore.completedOnboardingVersion = 0
        try? tokenStore.clearToken()
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
            tvFocusWarmupCoordinator: tvFocusWarmupCoordinator,
            makePlaybackSession: {
                self.makeSharedPlaybackSessionController()
            }
        )
    }

    @MainActor
    private func makeSharedPlaybackSessionController() -> PlaybackSessionController {
        if let sharedPlaybackSessionController {
            return sharedPlaybackSessionController
        }

        let controller = PlaybackSessionController(
            apiClient: apiClient,
            repository: repository,
            warmupManager: playbackWarmupManager
        )
        sharedPlaybackSessionController = controller
        return controller
    }
}
