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
        NativePlayerRuntimeDefaults.registerExperimentalBranchDefaults()
        if NativePlayerConfig.runtimeOverrideEnabled() {
            PlaybackSessionController.clearStoredPreferredTranscodeProfiles()
            AppLog.playback.notice("nativeplayer.runtime.enabled — platform=tvOS storedTranscodePinsCleared=true")
        }
        let metadata = AppMetadata.current
        self.metadata = metadata
        self.dependencies = TVAppBootstrap.makeDependencies(metadata: metadata)
        ErrorTracking.startIfConfigured(metadata: metadata)
    }

    var body: some Scene {
        WindowGroup {
            rootContent
        }
    }

    @ViewBuilder
    private var rootContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reelfin-tv-player-chrome-reference") {
            ReelFinTVPlayerChromeReferenceView()
                .preferredColorScheme(.dark)
        } else {
            productionContent
        }
#else
        productionContent
#endif
    }

    private var productionContent: some View {
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
