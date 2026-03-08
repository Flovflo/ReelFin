import Foundation

public struct AppMetadata: Sendable {
    public static let privacyPolicyURLKey = "REELFIN_PRIVACY_POLICY_URL"
    public static let termsOfServiceURLKey = "REELFIN_TERMS_OF_SERVICE_URL"
    public static let supportEmailKey = "REELFIN_SUPPORT_EMAIL"
    public static let supportURLKey = "REELFIN_SUPPORT_URL"
    public static let sentryDSNKey = "REELFIN_SENTRY_DSN"

    public static let mockModeArgument = "-reelfin-mock-mode"
    public static let screenshotModeArgument = "-reelfin-screenshot-mode"

    public let privacyPolicyURL: URL?
    public let termsOfServiceURL: URL?
    public let supportURL: URL?
    public let supportEmail: String?
    public let supportEmailURL: URL?
    public let sentryDSN: String?
    public let isMockModeEnabled: Bool
    public let isScreenshotModeEnabled: Bool

    public init(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) {
        privacyPolicyURL = AppMetadata.urlValue(for: Self.privacyPolicyURLKey, bundle: bundle)
        termsOfServiceURL = AppMetadata.urlValue(for: Self.termsOfServiceURLKey, bundle: bundle)
        supportURL = AppMetadata.urlValue(for: Self.supportURLKey, bundle: bundle)
        supportEmail = AppMetadata.stringValue(for: Self.supportEmailKey, bundle: bundle)
        supportEmailURL = supportEmail.flatMap { URL(string: "mailto:\($0)") }
        sentryDSN = AppMetadata.stringValue(for: Self.sentryDSNKey, bundle: bundle)

        let arguments = Set(processInfo.arguments)
        isMockModeEnabled = arguments.contains(Self.mockModeArgument) || processInfo.environment["REELFIN_MOCK_MODE"] == "1"
        isScreenshotModeEnabled = arguments.contains(Self.screenshotModeArgument) || processInfo.environment["REELFIN_SCREENSHOT_MODE"] == "1"
    }

    public static let current = AppMetadata()

    public var hasSupportSurface: Bool {
        privacyPolicyURL != nil || termsOfServiceURL != nil || supportURL != nil || supportEmailURL != nil
    }

    private static func stringValue(for key: String, bundle: Bundle) -> String? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static func urlValue(for key: String, bundle: Bundle) -> URL? {
        guard let rawValue = stringValue(for: key, bundle: bundle) else {
            return nil
        }

        return URL(string: rawValue)
    }
}
