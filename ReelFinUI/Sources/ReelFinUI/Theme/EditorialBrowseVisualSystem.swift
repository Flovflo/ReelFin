import Foundation
import Shared
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

struct DetailArtworkCompositionPlan: Equatable {
    let role: DetailArtworkRole
    let heroStackCount: Int
    let imageLayerCount: Int
    let canonicalRoles: [ArtworkRequestRole]
}

enum TVDetailPrimaryAction: CaseIterable, Equatable {
    case play
    case watchlist
    case watched

    var accessibilityIdentifier: String {
        switch self {
        case .play:
            return "detail_primary_play_button"
        case .watchlist:
            return "detail_watchlist_button"
        case .watched:
            return "detail_watched_button"
        }
    }
}

enum TVDetailSupportingContentRole: Equatable {
    case seasons
    case episodes
    case cast
    case related
}

enum TVDetailFocusTopology {
    static let primaryActionOrder: [TVDetailPrimaryAction] = [.play, .watchlist, .watched]
    static let defaultPrimaryAction: TVDetailPrimaryAction = .play

    static func acceptsFocus(_ role: TVDetailSupportingContentRole) -> Bool {
        switch role {
        case .cast:
            return false
        case .seasons, .episodes, .related:
            return true
        }
    }

    static func hasFocusableContentBeforeMoreLikeThis(
        hasSeasonPicker: Bool,
        hasEpisodes: Bool,
        hasCast: Bool
    ) -> Bool {
        (hasSeasonPicker && acceptsFocus(.seasons))
            || (hasEpisodes && acceptsFocus(.episodes))
            || (hasCast && acceptsFocus(.cast))
    }
}

enum HeroPageChangeOrigin: Equatable {
    case automatic
    case direct
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

    static func allowsHaptic(for origin: HeroPageChangeOrigin) -> Bool {
        origin == .direct
    }
}

enum CinematicBackdropLayerPolicy {
    enum Source: Equatable {
        case item
        case fallback
        case none
    }

    static let artworkLayerCount = 2

    static func source(hasItem: Bool, hasFallbackItem: Bool) -> Source {
        if hasItem {
            return .item
        }
        return hasFallbackItem ? .fallback : .none
    }
}

enum HomeEditorialPresentationPolicy {
    static let activeIndicatorWidth: CGFloat = 24
    static let inactiveIndicatorWidth: CGFloat = 8
    static let focusedShadowRadius: CGFloat = 34
    static let focusedShadowYOffset: CGFloat = 18

    static func focusedMediaGlass(
        isFocused: Bool,
        reduceTransparency: Bool
    ) -> EditorialGlassPresentation? {
        guard isFocused else { return nil }
        return EditorialGlassRole.focusedMedia.presentation(
            reduceTransparency: reduceTransparency
        )
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

    static func composition(isSelected: Bool) -> DetailArtworkCompositionPlan {
        if isSelected {
            return DetailArtworkCompositionPlan(
                role: .hero,
                heroStackCount: 1,
                imageLayerCount: 2,
                canonicalRoles: [.heroLow, .heroHigh]
            )
        }

        return DetailArtworkCompositionPlan(
            role: .preview,
            heroStackCount: 0,
            imageLayerCount: 1,
            canonicalRoles: [.landscapeRail]
        )
    }
}
