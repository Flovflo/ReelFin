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
    static let version = 2

    static let items: [iOS26StyleOnBoarding.Item] = [
        .init(
            id: 0,
            title: "Native Jellyfin",
            subtitle: "Open Home, Continue Watching,\nand jump back in instantly.",
            screenshot: UIImage(named: "reelfin-onboarding-home.png")
        ),
        .init(
            id: 1,
            title: "Fluid Library",
            subtitle: "Browse movies and shows with\nfast filters and native controls.",
            screenshot: UIImage(named: "reelfin-onboarding-library.png"),
            zoomScale: 1.14,
            zoomAnchor: .init(x: 0.5, y: 0.36)
        ),
        .init(
            id: 2,
            title: "Better Details",
            subtitle: "Cast, actions, and playback info\nstay right where you expect them.",
            screenshot: UIImage(named: "reelfin-onboarding-detail.png"),
            zoomScale: 1.16,
            zoomAnchor: .init(x: 0.5, y: 0.34)
        ),
        .init(
            id: 3,
            title: "Ready to Connect",
            subtitle: "Set your preferences, sign in,\nand start watching.",
            screenshot: UIImage(named: "reelfin-onboarding-settings.png"),
            zoomScale: 1.12,
            zoomAnchor: .init(x: 0.5, y: 0.56)
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
    static let highlights = [
        "Native playback",
        "Fast browsing",
        "Apple TV ready"
    ]
}
#endif
