import ReelFinUI
import Shared
import SwiftUI
import UIKit

@main
struct ReelFinApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let container = AppContainer()

    init() {
        configureTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ReelFinRootView(dependencies: container.makeDependencies())
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { newValue in
                    if newValue == .active {
                        Task {
                            await container.syncEngine.sync(reason: .appForeground)
                        }
                    }
                }
        }
    }

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
}
