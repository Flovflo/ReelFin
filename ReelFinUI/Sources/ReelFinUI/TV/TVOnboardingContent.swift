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
            title: "Native Jellyfin",
            subtitle: "See the real tvOS home screen, jump back in fast, and keep your watch queue one click away.",
            accent: Color(red: 0.34, green: 0.52, blue: 0.96),
            secondaryAccent: Color(red: 0.68, green: 0.78, blue: 0.98),
            screenshotName: "reelfin-tv-onboarding-home.png",
            zoomScale: 1.02,
            zoomAnchor: .center,
            highlight: .home
        ),
        .init(
            id: 1,
            title: "Fluid Library",
            subtitle: "Bigger art, cleaner rails, and a layout that feels fast with the Apple TV remote.",
            accent: Color(red: 0.22, green: 0.74, blue: 0.88),
            secondaryAccent: Color(red: 0.56, green: 0.90, blue: 0.86),
            screenshotName: "reelfin-tv-onboarding-home.png",
            zoomScale: 1.18,
            zoomAnchor: .init(x: 0.50, y: 0.82),
            highlight: .library
        ),
        .init(
            id: 2,
            title: "Direct Play Clarity",
            subtitle: "Playback badges and the lightning icon tell you instantly when the file is ready without server prep.",
            accent: Color(red: 1.00, green: 0.62, blue: 0.28),
            secondaryAccent: Color(red: 0.94, green: 0.44, blue: 0.36),
            screenshotName: "reelfin-tv-onboarding-detail.png",
            zoomScale: 1.06,
            zoomAnchor: .init(x: 0.46, y: 0.34),
            highlight: .detail
        ),
        .init(
            id: 3,
            title: "Ready to Connect",
            subtitle: "Approve from your phone or sign in directly, then drop straight into the full tvOS app.",
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
