import Foundation
import Sentry
import Shared

enum ErrorTracking {
    static func startIfConfigured(metadata: AppMetadata) {
        guard !metadata.isMockModeEnabled, !metadata.isScreenshotModeEnabled else {
            return
        }

        guard let dsn = metadata.sentryDSN, !dsn.isEmpty else {
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.enableAppHangTracking = true
#if os(iOS)
            options.enableMetricKit = true
#endif
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.tracesSampleRate = 0.1
            options.environment = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "1" ? "release" : "debug"
            options.beforeSend = { event in
                event.user = nil
                return event
            }
        }
    }
}
