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
            title: "Your Jellyfin on Apple TV",
            subtitle: "See your Jellyfin library in a true big-screen app with clean focus and fast resume.",
            screenshotName: "reelfin-tv-onboarding-home.png",
            zoomScale: 1.25,
            zoomAnchor: .init(x: 0.70, y: 1)
        ),
        .init(
            id: 1,
            title: "Find what to watch",
            subtitle: "Move through posters, seasons, and episodes with large artwork and remote-first rails.",
            screenshotName: "reelfin-tv-onboarding-home.png",
            zoomScale: 1.40,
            zoomAnchor: .init(x: 0.50, y: 0.82)
        ),
        .init(
            id: 2,
            title: "Know the playback path",
            subtitle: "The lightning badge shows when a video can play unchanged through the native path.",
            screenshotName: "reelfin-tv-onboarding-detail.png",
            zoomScale: 1.06,
            zoomAnchor: .init(x: 0.46, y: 0.34)
        ),
        .init(
            id: 3,
            title: "Connect in seconds",
            subtitle: "Use Quick Connect from your phone or sign in with your Jellyfin password.",
            screenshotName: "reelfin-tv-onboarding-connect.png",
            zoomScale: 2.60,
            zoomAnchor: .init(x: 0.52, y: 0)
        )
    ]
}

struct TVOnboardingLayoutMetrics: Equatable {
    let safeFrame: CGRect
    let copyMaximumWidth: CGFloat
    let copyToActionsSpacing: CGFloat
    let actionRailWidth: CGFloat
    let stacksActions: Bool
}

enum TVOnboardingLayoutPolicy {
    static let horizontalInset: CGFloat = 80
    static let verticalInset: CGFloat = 60

    static func metrics(for canvas: CGSize) -> TVOnboardingLayoutMetrics {
        let safeWidth = max(canvas.width - (horizontalInset * 2), 0)
        let safeHeight = max(canvas.height - (verticalInset * 2), 0)
        let stacksActions = canvas.width < 1_500
        let copyToActionsSpacing: CGFloat = stacksActions ? 32 : 48
        let actionRailWidth = min(stacksActions ? 500 : 720, safeWidth * 0.46)
        let copyMaximumWidth = min(
            820,
            max(safeWidth - actionRailWidth - copyToActionsSpacing, 0)
        )

        return TVOnboardingLayoutMetrics(
            safeFrame: CGRect(
                x: horizontalInset,
                y: verticalInset,
                width: safeWidth,
                height: safeHeight
            ),
            copyMaximumWidth: copyMaximumWidth,
            copyToActionsSpacing: copyToActionsSpacing,
            actionRailWidth: actionRailWidth,
            stacksActions: stacksActions
        )
    }
}

struct TVOnboardingMotionConfiguration: Equatable {
    let allowsDrift: Bool
    let allowsScale: Bool
    let allowsBlur: Bool
    let allowsBounce: Bool
    let pageOffset: CGFloat
}

enum TVOnboardingMotionPolicy {
    static func configuration(reduceMotion: Bool) -> TVOnboardingMotionConfiguration {
        TVOnboardingMotionConfiguration(
            allowsDrift: !reduceMotion,
            allowsScale: !reduceMotion,
            allowsBlur: !reduceMotion,
            allowsBounce: !reduceMotion,
            pageOffset: reduceMotion ? 0 : 28
        )
    }
}
#endif
