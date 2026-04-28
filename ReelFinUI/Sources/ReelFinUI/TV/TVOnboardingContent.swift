#if os(tvOS)
import SwiftUI

struct TVOnboardingItem: Identifiable, Equatable {
    let id: Int
    let title: String
    let subtitle: String
    let accent: Color
    let secondaryAccent: Color
    let screenshotName: String
    let zoomScale: CGFloat
    let zoomAnchor: UnitPoint
    let highlight: TVOnboardingHighlight
}

enum TVOnboardingHighlight {
    case home
    case library
    case detail
    case connect
}

enum TVOnboardingContent {
    static let items: [TVOnboardingItem] = [
        .init(
            id: 0,
            title: "Native on Apple TV",
            subtitle: "See your Jellyfin library in a true big-screen app with clean focus and fast resume.",
            accent: Color(red: 0.34, green: 0.52, blue: 0.96),
            secondaryAccent: Color(red: 0.68, green: 0.78, blue: 0.98),
            screenshotName: "reelfin-tv-onboarding-home.png",
            zoomScale: 1.02,
            zoomAnchor: .center,
            highlight: .home
        ),
        .init(
            id: 1,
            title: "Browse without friction",
            subtitle: "Move through posters, seasons, and episodes with large artwork and remote-first rails.",
            accent: Color(red: 0.22, green: 0.74, blue: 0.88),
            secondaryAccent: Color(red: 0.56, green: 0.90, blue: 0.86),
            screenshotName: "reelfin-tv-onboarding-home.png",
            zoomScale: 1.18,
            zoomAnchor: .init(x: 0.50, y: 0.82),
            highlight: .library
        ),
        .init(
            id: 2,
            title: "Spot Direct Play",
            subtitle: "The lightning badge shows when a video can play unchanged through the native path.",
            accent: Color(red: 1.00, green: 0.62, blue: 0.28),
            secondaryAccent: Color(red: 0.94, green: 0.44, blue: 0.36),
            screenshotName: "reelfin-tv-onboarding-detail.png",
            zoomScale: 1.06,
            zoomAnchor: .init(x: 0.46, y: 0.34),
            highlight: .detail
        ),
        .init(
            id: 3,
            title: "Connect your way",
            subtitle: "Use Quick Connect from your phone or sign in with your Jellyfin password.",
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
