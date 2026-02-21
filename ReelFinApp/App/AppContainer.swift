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
    let repository: GRDBMetadataRepository
    let imagePipeline: DefaultImagePipeline
    let syncEngine: DefaultSyncEngine

    init() {
        settingsStore = DefaultSettingsStore()
        tokenStore = KeychainTokenStore()
        apiClient = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settingsStore)

        do {
            repository = try GRDBMetadataRepository()
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("reelfin-fallback.sqlite")
            do {
                repository = try GRDBMetadataRepository(databaseURL: fallbackURL)
            } catch {
                fatalError("Unable to initialize local metadata database: \(error.localizedDescription)")
            }
        }

        imagePipeline = DefaultImagePipeline()
        syncEngine = DefaultSyncEngine(
            apiClient: apiClient,
            repository: repository,
            imagePipeline: imagePipeline
        )
    }

    @MainActor
    func makeDependencies() -> ReelFinDependencies {
        ReelFinDependencies(
            apiClient: apiClient,
            repository: repository,
            imagePipeline: imagePipeline,
            syncEngine: syncEngine,
            settingsStore: settingsStore,
            makePlaybackSession: {
                PlaybackSessionController(apiClient: self.apiClient, repository: self.repository)
            }
        )
    }
}
