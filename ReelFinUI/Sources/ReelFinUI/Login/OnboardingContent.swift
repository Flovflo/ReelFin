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
            title: "Your Jellyfin, faster",
            subtitle: "ReelFin turns your server into a native iPhone and iPad app tuned for quick launch, fast resume, and smooth browsing.",
            screenshot: UIImage(named: "reelfin-onboarding-home.png")
        ),
        .init(
            id: 1,
            eyebrow: "CLEAN BROWSING",
            title: "Find what to watch",
            subtitle: "Posters, rails, search, and touch controls stay focused on getting you to the next movie or episode.",
            screenshot: UIImage(named: "reelfin-onboarding-library.png"),
            zoomScale: 1.14,
            zoomAnchor: .init(x: 0.5, y: 0.36)
        ),
        .init(
            id: 2,
            eyebrow: "DIRECT PLAY",
            title: "Spot the fastest path",
            subtitle: "The lightning badge tells you when ReelFin can play the original file through Apple's native player.",
            screenshot: UIImage(named: "reelfin-onboarding-detail.png"),
            zoomScale: 1.16,
            zoomAnchor: .init(x: 0.5, y: 0.34)
        ),
        .init(
            id: 3,
            eyebrow: "SMART STREAMS",
            title: "Optimized when needed",
            subtitle: "If a file is not Apple-ready, ReelFin asks Jellyfin for a compatible HLS stream instead of leaving playback to chance.",
            screenshot: UIImage(named: "reelfin-onboarding-detail.png"),
            buttonTitle: "Connect My Server",
            zoomScale: 1.08,
            zoomAnchor: .init(x: 0.5, y: 0.26)
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
