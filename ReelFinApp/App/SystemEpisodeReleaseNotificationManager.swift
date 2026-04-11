#if os(iOS)
import Foundation
import Shared
import UserNotifications

actor SystemEpisodeReleaseNotificationManager: EpisodeReleaseNotificationManaging {
    private let settingsStore: SettingsStoreProtocol
    private let center: UNUserNotificationCenter

    init(
        settingsStore: SettingsStoreProtocol,
        center: UNUserNotificationCenter = .current()
    ) {
        self.settingsStore = settingsStore
        self.center = center
    }

    func authorizationStatus() async -> EpisodeReleaseNotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unsupported
        }
    }

    func notificationsEnabled() async -> Bool {
        guard settingsStore.episodeReleaseNotificationsEnabled else { return false }
        return await authorizationStatus() == .authorized
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        guard enabled else {
            settingsStore.episodeReleaseNotificationsEnabled = false
            return
        }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            settingsStore.episodeReleaseNotificationsEnabled = granted
        } catch {
            settingsStore.episodeReleaseNotificationsEnabled = false
        }
    }

    func deliver(alerts: [EpisodeReleaseAlert], reason: SyncReason) async {
        guard await notificationsEnabled(), !alerts.isEmpty else { return }

        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.seriesName
            content.body = body(for: alert)
            content.sound = .default
            content.userInfo = [
                "seriesID": alert.seriesID,
                "episodeID": alert.episodeID,
                "syncReason": reason.rawValue
            ]

            let request = UNNotificationRequest(
                identifier: "episode-release.\(alert.episodeID)",
                content: content,
                trigger: nil
            )

            do {
                try await add(request)
            } catch {
                AppLog.sync.warning(
                    "Episode release notification failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func body(for alert: EpisodeReleaseAlert) -> String {
        switch (alert.seasonNumber, alert.episodeNumber) {
        case let (season?, episode?):
            return "New episode available: S\(season) E\(episode) • \(alert.episodeTitle)"
        case let (_, episode?):
            return "New episode available: Episode \(episode) • \(alert.episodeTitle)"
        default:
            return "New episode available: \(alert.episodeTitle)"
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
#endif
