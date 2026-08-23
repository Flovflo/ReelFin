import Foundation
import Shared
import SwiftUI

enum EditorialGlassPresentation: Equatable {
    case interactiveGlass
    case passiveGlass
    case opaque
}

enum EditorialOpaqueHeaderPolicy {
    static func opacity(
        revealProgress: CGFloat,
        activationThreshold: CGFloat
    ) -> Double {
        guard revealProgress.isFinite, activationThreshold.isFinite else { return 0 }
        let progress = min(max(revealProgress, 0), 1)
        let threshold = min(max(activationThreshold, 0), 1)
        return progress > 0 && progress >= threshold ? 1 : 0
    }
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
    let primaryRole: ArtworkRequestRole
    let secondaryRole: ArtworkRequestRole?

    var imageLayerCount: Int { canonicalRoles.count }

    var canonicalRoles: [ArtworkRequestRole] {
        [primaryRole] + (secondaryRole.map { [$0] } ?? [])
    }
}

enum TVDetailPrimaryAction: CaseIterable, Hashable {
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

enum EditorialMediaIdentityAccessibility {
    static func identifier(itemID: String) -> String {
        "editorial_media_identity_\(itemID)"
    }

    static func label(
        itemName: String,
        kicker: String?,
        metadata: String?
    ) -> String {
        [kicker, itemName, metadata]
            .compactMap(normalized)
            .joined(separator: ", ")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty
        else {
            return nil
        }
        return normalized
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

enum HeroArtworkLoadingLayer: Equatable {
    case lowResolution
    case highResolution
    case logo
}

enum HeroArtworkLoadingPolicy {
    static func layers(
        pageIndex: Int,
        currentIndex: Int,
        lowResolutionReady: Bool
    ) -> [HeroArtworkLoadingLayer] {
        guard pageIndex >= 0, currentIndex >= 0, pageIndex == currentIndex else {
            return []
        }

        if lowResolutionReady {
            return [.lowResolution, .highResolution, .logo]
        }
        return [.lowResolution, .logo]
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
    static let stickyChromeRevealThreshold: CGFloat = 0.82

    static func iosHeroHeight(compact: Bool, accessibilitySize: Bool) -> CGFloat {
        if compact {
            return accessibilitySize ? 520 : 430
        }
        return accessibilitySize ? 680 : 600
    }

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
                primaryRole: .heroLow,
                secondaryRole: .heroHigh
            )
        }

        return DetailArtworkCompositionPlan(
            role: .preview,
            heroStackCount: 0,
            primaryRole: .landscapeRail,
            secondaryRole: nil
        )
    }
}
