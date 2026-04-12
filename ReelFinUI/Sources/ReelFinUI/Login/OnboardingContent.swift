#if os(iOS)
import SwiftUI

enum OnboardingPalette {
    static let backgroundTop = Color(red: 0.060, green: 0.030, blue: 0.180)
    static let backgroundBottom = Color(red: 0.040, green: 0.460, blue: 0.150)
    static let primaryText = Color.white.opacity(0.98)
    static let secondaryText = Color.white.opacity(0.82)
    static let tertiaryText = Color.white.opacity(0.54)
    static let glowWhite = Color.white.opacity(0.92)
    static let panelTint = Color.black.opacity(0.42)
    static let panelStroke = Color.white.opacity(0.08)
    static let shadow = Color.black.opacity(0.22)

    static let blue = Color(red: 0.110, green: 0.550, blue: 1.000)
    static let pink = Color(red: 1.000, green: 0.360, blue: 0.440)
    static let violet = Color(red: 0.520, green: 0.460, blue: 1.000)
    static let lime = Color(red: 0.690, green: 0.930, blue: 0.250)
    static let orange = Color(red: 1.000, green: 0.610, blue: 0.280)
    static let mint = Color(red: 0.260, green: 0.850, blue: 0.620)
}

enum ReelFinOnboardingContent {
    static let tint = OnboardingPalette.blue
    static let version = ReelFinOnboardingVersion.current

    static let items: [iOS26StyleOnBoarding.Item] = [
        .init(
            id: 0,
            eyebrow: "APPLE-FIRST SPEED",
            title: "Feels fast the second it opens",
            subtitle: "ReelFin is built for iPhone and iPad first, with a richer home screen, faster resume, and no generic web-shell feel.",
            screenshot: UIImage(named: "reelfin-onboarding-home.png"),
            highlights: ["Native UI", "Fast resume", "Continue Watching"],
            footnote: "Built on Apple playback frameworks from browse to first frame."
        ),
        .init(
            id: 1,
            eyebrow: "DISCOVERY",
            title: "Browse without the usual friction",
            subtitle: "Move through movies and shows with cleaner art, quick search, and controls that feel made for touch.",
            screenshot: UIImage(named: "reelfin-onboarding-library.png"),
            highlights: ["Movies + Shows", "Quick search", "Touch-first"],
            footnote: "Your library stays lightweight before you even hit play.",
            zoomScale: 1.14,
            zoomAnchor: .init(x: 0.5, y: 0.36)
        ),
        .init(
            id: 2,
            eyebrow: "PLAYBACK SIGNAL",
            title: "See the bolt, press play",
            subtitle: "The lightning badge means the title is already ready for the Apple playback path, so ReelFin can skip extra server prep.",
            screenshot: UIImage(named: "reelfin-onboarding-detail.png"),
            highlights: ["Bolt = ready", "Direct Play", "Apple-safe path"],
            footnote: "That is the fastest path ReelFin can give you on Apple devices.",
            zoomScale: 1.16,
            zoomAnchor: .init(x: 0.5, y: 0.34)
        ),
        .init(
            id: 3,
            eyebrow: "SMART FALLBACK",
            title: "Hard files still get an Apple-first route",
            subtitle: "When a title needs help, ReelFin asks Jellyfin for an Apple-optimized stream instead of leaving you with a generic fallback.",
            screenshot: UIImage(named: "reelfin-onboarding-detail.png"),
            highlights: ["Apple-optimized HLS", "HEVC / fMP4", "Predictable startup"],
            footnote: "This is how ReelFin keeps difficult media feeling more reliable on iPhone and iPad.",
            zoomScale: 1.08,
            zoomAnchor: .init(x: 0.5, y: 0.26)
        ),
        .init(
            id: 4,
            eyebrow: "EPISODE ALERTS",
            title: "Know when the next episode lands",
            subtitle: "Turn on New Episode Alerts and ReelFin only pings you for shows you already follow, so notifications stay useful.",
            screenshot: UIImage(named: "reelfin-onboarding-settings.png"),
            highlights: ["Followed shows only", "Local alerts", "No noisy spam"],
            footnote: "You stay in sync without checking your server every night.",
            zoomScale: 1.12,
            zoomAnchor: .init(x: 0.5, y: 0.56)
        ),
        .init(
            id: 5,
            eyebrow: "READY TO WATCH",
            title: "Connect once. Start watching.",
            subtitle: "Save your server, keep your playback preferences, and jump into a Jellyfin experience tuned for Apple devices.",
            screenshot: UIImage(named: "reelfin-onboarding-settings.png"),
            highlights: ["Server saved", "Playback presets", "Start faster"],
            footnote: "If the bolt is there, hit play. If not, ReelFin prepares the best Apple route it can.",
            buttonTitle: "Connect My Server",
            zoomScale: 1.02,
            zoomAnchor: .init(x: 0.5, y: 0.58)
        )
    ]
}

enum ReelFinShowcaseContent {
    static let accent = OnboardingPalette.blue
    static let glow = OnboardingPalette.violet
    static let posters = [
        "onboarding-poster-1.jpg",
        "onboarding-poster-3.jpg",
        "onboarding-poster-2.jpg",
        "onboarding-poster-4.jpg",
        "onboarding-poster-5.webp"
    ]
}
#endif
