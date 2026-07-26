import Foundation
import SwiftUI

enum EditorialGlassPresentation: Equatable {
    case interactiveGlass
    case passiveGlass
    case opaque
}

enum EditorialGlassRole {
    case navigation
    case actionCluster
    case compactControl
    case focusedMedia

    func presentation(reduceTransparency: Bool) -> EditorialGlassPresentation {
        guard !reduceTransparency else {
            return .opaque
        }

        switch self {
        case .navigation, .actionCluster, .compactControl:
            return .interactiveGlass
        case .focusedMedia:
            return .passiveGlass
        }
    }
}

enum DetailArtworkRole: Equatable {
    case hero
    case preview
}

enum HeroRotationPolicy {
    static func allowsAutomaticAdvance(
        sceneIsActive: Bool,
        isUserInteracting: Bool,
        reduceMotion: Bool,
        voiceOverEnabled: Bool,
        itemCount: Int
    ) -> Bool {
        sceneIsActive
            && !isUserInteracting
            && !reduceMotion
            && !voiceOverEnabled
            && itemCount > 1
    }

    static func nextIndex(currentIndex: Int, itemCount: Int) -> Int? {
        guard itemCount > 1, (0..<itemCount).contains(currentIndex) else {
            return nil
        }
        return (currentIndex + 1) % itemCount
    }
}

enum EditorialMotion {
    static func heroPageDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.18 : 0.21
    }

    static func focusScale(role: TVMotion.FocusRole, reduceMotion: Bool) -> CGFloat {
        TVFocusGeometry.scale(for: role, reduceMotion: reduceMotion)
    }

    static func buttonPressAnimation(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.10 : 0.09)
    }
}

enum DetailArtworkCostPolicy {
    static func role(isSelected: Bool) -> DetailArtworkRole {
        isSelected ? .hero : .preview
    }

    static func heroLayerBudget(isSelected: Bool) -> Int {
        isSelected ? 1 : 0
    }
}
