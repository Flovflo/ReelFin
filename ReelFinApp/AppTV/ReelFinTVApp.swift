import PlaybackEngine
import ReelFinUI
import Shared
import SwiftUI

@main
struct ReelFinTVApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let metadata: AppMetadata
    private let dependencies: ReelFinDependencies

    init() {
        NativeVLCClassPlayerRuntimeDefaults.registerExperimentalBranchDefaults()
        if NativeVLCClassPlayerConfig.runtimeOverrideEnabled() {
            PlaybackSessionController.clearStoredPreferredTranscodeProfiles()
            AppLog.playback.notice("nativevlc.runtime.enabled — platform=tvOS branch=feature/vlc-class-native-swift-player storedTranscodePinsCleared=true")
        }
        let metadata = AppMetadata.current
        self.metadata = metadata
        self.dependencies = TVAppBootstrap.makeDependencies(metadata: metadata)
        ErrorTracking.startIfConfigured(metadata: metadata)
    }

    var body: some Scene {
        WindowGroup {
            ReelFinRootView(dependencies: dependencies)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, newValue in
                    if newValue == .active {
                        Task {
                            await dependencies.syncEngine.sync(reason: .appForeground)
                        }
                    }
                }
        }
    }
}
