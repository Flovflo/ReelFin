#if os(tvOS)
import SwiftUI

struct TVOnboardingItem: Identifiable, Equatable {
    let id: Int
    let title: String
    let subtitle: String
    let screenshotName: String
}

enum TVOnboardingContent {
    static let items: [TVOnboardingItem] = [
        .init(
            id: 0,
            title: "Your Jellyfin on Apple TV",
            subtitle: "See your Jellyfin library in a true big-screen app with clean focus and fast resume.",
            screenshotName: "reelfin-tv-onboarding-home-live.png"
        ),
        .init(
            id: 1,
            title: "Find what to watch",
            subtitle: "Move through movies and shows with clear focus, large artwork, and remote-first rails.",
            screenshotName: "reelfin-tv-onboarding-library-live.png"
        ),
        .init(
            id: 2,
            title: "Pick up exactly where you left off",
            subtitle: "Resume an episode, start over, or jump straight into playback from a focused detail screen.",
            screenshotName: "reelfin-tv-onboarding-detail-live.png"
        ),
        .init(
            id: 3,
            title: "Playback that stays out of the way",
            subtitle: "Seek, change tracks, and skip intros with controls built for the Apple TV remote.",
            screenshotName: "reelfin-tv-onboarding-player-live.png"
        )
    ]
}

struct TVOnboardingLayoutMetrics: Equatable {
    let safeFrame: CGRect
    let heroFrame: CGRect
    let copyFrame: CGRect
    let actionsFrame: CGRect
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
        let safeFrame = CGRect(
            x: horizontalInset,
            y: verticalInset,
            width: safeWidth,
            height: safeHeight
        )
        let copyHeight = min(safeHeight, stacksActions ? 360 : 340)
        let actionsHeight = min(safeHeight, stacksActions ? 184 : 100)
        let copyFrame = CGRect(
            x: safeFrame.minX,
            y: safeFrame.maxY - copyHeight,
            width: copyMaximumWidth,
            height: copyHeight
        )
        let actionsFrame = CGRect(
            x: safeFrame.maxX - actionRailWidth,
            y: safeFrame.maxY - actionsHeight,
            width: actionRailWidth,
            height: actionsHeight
        )
        let heroColumnGap: CGFloat = stacksActions ? 32 : 64
        let heroColumnMinX = copyFrame.maxX + heroColumnGap
        let heroColumnWidth = max(safeFrame.maxX - heroColumnMinX, 0)
        let heroBottomGap: CGFloat = stacksActions ? 32 : 48
        let heroMaximumHeight = max(actionsFrame.minY - safeFrame.minY - heroBottomGap, 0)
        let heroWidth = min(heroColumnWidth, heroMaximumHeight * (16.0 / 9.0))
        let heroHeight = heroWidth * (9.0 / 16.0)
        let heroFrame = CGRect(
            x: safeFrame.maxX - heroWidth,
            y: safeFrame.minY,
            width: heroWidth,
            height: heroHeight
        )

        return TVOnboardingLayoutMetrics(
            safeFrame: safeFrame,
            heroFrame: heroFrame,
            copyFrame: copyFrame,
            actionsFrame: actionsFrame,
            copyMaximumWidth: copyMaximumWidth,
            copyToActionsSpacing: copyToActionsSpacing,
            actionRailWidth: actionRailWidth,
            stacksActions: stacksActions
        )
    }
}

struct TVOnboardingMotionConfiguration: Equatable {
    let pageOffset: CGFloat
}

enum TVOnboardingMotionPolicy {
    static func configuration(reduceMotion: Bool) -> TVOnboardingMotionConfiguration {
        TVOnboardingMotionConfiguration(
            pageOffset: reduceMotion ? 0 : 28
        )
    }
}
#endif
