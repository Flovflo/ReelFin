#if os(iOS)
import BackgroundTasks
import UIKit
import ReelFinUI
import Shared
import UserNotifications

@MainActor
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private enum BackgroundTask {
        static let refreshIdentifier = "com.reelfin.app.refresh"
    }

    private var syncEngine: SyncEngineProtocol?
    private var notificationManager: EpisodeReleaseNotificationManaging?
    private var hasConfiguredDependencies = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTask.refreshIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleAppRefresh(task)
        }
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return OrientationManager.shared.lock
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Task {
            await scheduleAppRefreshIfNeeded()
        }
    }

    func configure(dependencies: ReelFinDependencies) {
        syncEngine = dependencies.syncEngine
        notificationManager = dependencies.episodeReleaseNotificationManager

        guard !hasConfiguredDependencies else { return }
        hasConfiguredDependencies = true

        Task {
            await scheduleAppRefreshIfNeeded()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        let syncEngine = syncEngine
        Task {
            await scheduleAppRefreshIfNeeded()
            guard let syncEngine else {
                task.setTaskCompleted(success: false)
                return
            }

            await syncEngine.sync(reason: .backgroundRefresh)
            task.setTaskCompleted(success: true)
        }
    }

    private func scheduleAppRefreshIfNeeded() async {
        guard let notificationManager, await notificationManager.notificationsEnabled() else { return }

        let request = BGAppRefreshTaskRequest(identifier: BackgroundTask.refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLog.sync.warning(
                "Background refresh scheduling failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
#endif
