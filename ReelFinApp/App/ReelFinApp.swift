import PlaybackEngine
import ReelFinUI
import Shared
import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct ReelFinApp: App {
    @Environment(\.scenePhase) private var scenePhase
#if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
    private let metadata: AppMetadata
    private let dependencies: ReelFinDependencies

    init() {
        NativePlayerRuntimeDefaults.registerExperimentalBranchDefaults()
        if NativePlayerConfig.runtimeOverrideEnabled() {
            PlaybackSessionController.clearStoredPreferredTranscodeProfiles()
            AppLog.playback.notice("nativeplayer.runtime.enabled — platform=iOS branch=feature/native-swift-player storedTranscodePinsCleared=true")
        }
        let metadata = AppMetadata.current
        self.metadata = metadata
        self.dependencies = AppBootstrap.makeDependencies(metadata: metadata)
#if os(iOS)
        configureTabBarAppearance()
#endif
        ErrorTracking.startIfConfigured(metadata: metadata)
    }

    var body: some Scene {
        WindowGroup {
            ReelFinRootView(dependencies: dependencies)
                .preferredColorScheme(.dark)
                .onAppear {
                    appDelegate.configure(dependencies: dependencies)
                }
                .onChange(of: scenePhase) { _, newValue in
                    if newValue == .active {
                        Task {
                            await dependencies.syncEngine.sync(reason: .appForeground)
                        }
                    }
                }
        }
    }

#if os(iOS)
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.06)

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.62)
        itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.68)]
        itemAppearance.selected.iconColor = UIColor(red: 0.05, green: 0.52, blue: 1.0, alpha: 1)
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(red: 0.05, green: 0.52, blue: 1.0, alpha: 1)]
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().isTranslucent = true
    }
#endif
}
