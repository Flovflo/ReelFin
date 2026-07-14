#if os(tvOS)
import SwiftUI

struct TVOnboardingItem: Identifiable, Equatable {
    let id: Int
    let title: String
    let subtitle: String
    let screenshotName: String
    let zoomScale: CGFloat
    let zoomAnchor: UnitPoint
}

enum TVOnboardingContent {
    static let items: [TVOnboardingItem] = [
        .init(
            id: 0,
            title: "Native on Apple TV",
            subtitle: "See your Jellyfin library in a true big-screen app with clean focus and fast resume.",
            screenshotName: "reelfin-tv-onboarding-home.png",
            zoomScale: 1.25,
            zoomAnchor: .init(x: 0.70, y: 1)
        ),
        .init(
            id: 1,
            title: "Browse without friction",
            subtitle: "Move through posters, seasons, and episodes with large artwork and remote-first rails.",
            screenshotName: "reelfin-tv-onboarding-home.png",
            zoomScale: 1.40,
            zoomAnchor: .init(x: 0.50, y: 0.82)
        ),
        .init(
            id: 2,
            title: "Spot Direct Play",
            subtitle: "The lightning badge shows when a video can play unchanged through the native path.",
            screenshotName: "reelfin-tv-onboarding-detail.png",
            zoomScale: 1.06,
            zoomAnchor: .init(x: 0.46, y: 0.34)
        ),
        .init(
            id: 3,
            title: "Connect your way",
            subtitle: "Use Quick Connect from your phone or sign in with your Jellyfin password.",
            screenshotName: "reelfin-tv-onboarding-connect.png",
            zoomScale: 2.60,
            zoomAnchor: .init(x: 0.52, y: 0)
        )
    ]
}
#endif
