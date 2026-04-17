#if os(tvOS)
import SwiftUI

struct TVOnboardingItem: Identifiable, Equatable {
    let id: Int
    let eyebrow: String
    let title: String
    let subtitle: String
    let highlights: [String]
    let footnote: String?
    let accent: Color
    let secondaryAccent: Color
    let screenshotName: String
    let zoomScale: CGFloat
    let zoomAnchor: UnitPoint
    let highlight: TVOnboardingHighlight
}

enum TVOnboardingHighlight {
    case speed
    case discovery
    case playback
    case fallback
    case connect
}

enum TVOnboardingContent {
    static let items: [TVOnboardingItem] = [
        .init(
            id: 0,
            eyebrow: "Apple-first speed",
            title: "Jump back in fast on the best screen in the house.",
            subtitle: "A native tvOS home built around instant resume, a real hero carousel, and focus behavior that feels right with the Siri Remote.",
            highlights: ["Hero Play", "Continue Watching", "Native Focus"],
            footnote: "Built for couch distance, not a stretched iPhone layout.",
            accent: Color(red: 0.34, green: 0.52, blue: 0.96),
            secondaryAccent: Color(red: 0.68, green: 0.78, blue: 0.98),
            screenshotName: "reelfin-tv-onboarding-home.png",
            zoomScale: 1.02,
            zoomAnchor: .center,
            highlight: .speed
        ),
        .init(
            id: 1,
            eyebrow: "Discovery",
            title: "Browse deeper without losing your place.",
            subtitle: "Featured picks, rails, and details now connect with the same visual language so discovery feels calm, direct, and premium on tvOS.",
            highlights: ["Featured Carousel", "Stable Rails", "Return Focus"],
            footnote: "The app remembers where you came from and lands you back there cleanly.",
            accent: Color(red: 0.22, green: 0.74, blue: 0.88),
            secondaryAccent: Color(red: 0.56, green: 0.90, blue: 0.86),
            screenshotName: "reelfin-tv-onboarding-home.png",
            zoomScale: 1.08,
            zoomAnchor: .init(x: 0.50, y: 0.46),
            highlight: .discovery
        ),
        .init(
            id: 2,
            eyebrow: "Playback signal",
            title: "Know before you press play.",
            subtitle: "Direct Play status, source clarity, and playback readiness are surfaced right in the detail hero so you can trust what happens next.",
            highlights: ["Direct Play", "Playback Badges", "Episode Context"],
            footnote: "The player stays Apple-native. We improved the shell around it.",
            accent: Color(red: 1.00, green: 0.62, blue: 0.28),
            secondaryAccent: Color(red: 0.94, green: 0.44, blue: 0.36),
            screenshotName: "reelfin-tv-onboarding-detail.png",
            zoomScale: 1.06,
            zoomAnchor: .init(x: 0.46, y: 0.34),
            highlight: .playback
        ),
        .init(
            id: 3,
            eyebrow: "Smart fallback",
            title: "Series, seasons, and handoff stay under control.",
            subtitle: "When a title needs the next episode or extra context, ReelFin keeps the default focus on Play first and reveals the rest only when you ask for it.",
            highlights: ["Play First", "Season Picker", "Clean Motion"],
            footnote: "The detail screen prioritizes action, then expands into browse mode.",
            accent: Color(red: 0.82, green: 0.48, blue: 0.84),
            secondaryAccent: Color(red: 0.98, green: 0.72, blue: 0.82),
            screenshotName: "reelfin-tv-onboarding-detail.png",
            zoomScale: 1.14,
            zoomAnchor: .init(x: 0.54, y: 0.62),
            highlight: .fallback
        ),
        .init(
            id: 4,
            eyebrow: "Connect",
            title: "Link your Jellyfin server in a few clicks.",
            subtitle: "Approve from your phone or sign in directly on Apple TV, then land straight in the full ReelFin experience.",
            highlights: ["Quick Connect", "Password Sign-In", "No Detours"],
            footnote: "Episode alerts stay on iPhone and iPad. tvOS stays focused on playback and browsing.",
            accent: Color(red: 0.28, green: 0.84, blue: 0.66),
            secondaryAccent: Color(red: 0.58, green: 0.92, blue: 0.90),
            screenshotName: "reelfin-tv-onboarding-connect.png",
            zoomScale: 1.0,
            zoomAnchor: .center,
            highlight: .connect
        )
    ]
}
#endif
