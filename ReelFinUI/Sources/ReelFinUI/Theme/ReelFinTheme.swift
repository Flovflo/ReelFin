import SwiftUI

public enum ReelFinTheme {
    // Colors
    public static let background = Color.black
    public static let surface = Color(white: 0.12)
    public static let card = Color(white: 0.16)
    public static let accent = Color.white
    public static let accentSecondary = Color.white.opacity(0.7)

    public static let onboardingBackground = Color(red: 0.018, green: 0.024, blue: 0.043)
    public static let onboardingSurface = Color(red: 0.062, green: 0.080, blue: 0.122)
    public static let onboardingSurfaceSecondary = Color(red: 0.094, green: 0.118, blue: 0.176)
    public static let onboardingPrimaryText = Color.white
    public static let onboardingSecondaryText = Color.white.opacity(0.64)
    public static let onboardingBorder = Color.white.opacity(0.09)
    public static let onboardingShadow = Color.black.opacity(0.32)
    public static let onboardingPrimaryButton = Color.white
    public static let onboardingPrimaryButtonText = Color(red: 0.031, green: 0.043, blue: 0.074)
    public static let onboardingSecondaryButtonText = Color.white
    public static let onboardingButtonTint = Color(red: 0.84, green: 0.88, blue: 0.94).opacity(0.84)
    public static let onboardingButtonText = Color(red: 0.10, green: 0.12, blue: 0.17).opacity(0.94)
    public static let onboardingQuietButtonTint = Color.white.opacity(0.20)
    public static let onboardingSuccess = Color(red: 0.141, green: 0.742, blue: 0.417)

    public static let onboardingCyan = Color(red: 0.169, green: 0.846, blue: 0.956)
    public static let onboardingBlue = Color(red: 0.118, green: 0.454, blue: 1.000)
    public static let onboardingOrange = Color(red: 1.000, green: 0.596, blue: 0.267)
    public static let onboardingViolet = Color(red: 0.482, green: 0.349, blue: 1.000)
    public static let onboardingPink = Color(red: 0.963, green: 0.404, blue: 0.827)
    public static let onboardingMint = Color(red: 0.352, green: 0.888, blue: 0.718)

    // Gradients
    public static let pageGradient = LinearGradient(
        colors: [
            Color.black,
            Color.black
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let heroGradientScrim = LinearGradient(
        colors: [
            Color.black.opacity(0.0),
            Color.black.opacity(0.4),
            Color.black.opacity(0.95),
            Color.black
        ],
        startPoint: .center,
        endPoint: .bottom
    )

    public static let heroTopGradient = LinearGradient(
        colors: [
            Color.black.opacity(0.5),
            Color.clear
        ],
        startPoint: .top,
        endPoint: .center
    )

    // Styling Constants
    public static let glassPanelCornerRadius: CGFloat = 26
    public static let cardCornerRadius: CGFloat = 16
    public static let glassStrokeColor = Color.white.opacity(0.12)
    public static let glassStrokeWidth: CGFloat = 0.5
    public static let tvHeroCornerRadius: CGFloat = 38
    public static let tvCardCornerRadius: CGFloat = 26
    public static let tvChipCornerRadius: CGFloat = 16
    public static let tvSurfaceFill = Color(red: 0.072, green: 0.086, blue: 0.124)
    public static let tvSurfaceElevatedFill = Color(red: 0.110, green: 0.126, blue: 0.177)
    public static let tvSurfaceMutedFill = Color.white.opacity(0.06)
    public static let tvSelectedFill = Color.white.opacity(0.13)
    public static let tvStroke = Color.white.opacity(0.10)
    public static let tvStrongStroke = Color.white.opacity(0.24)
    public static let tvBrightText = Color.white.opacity(0.96)
    public static let tvMutedText = Color.white.opacity(0.62)
    public static let tvSoftText = Color.white.opacity(0.48)
    public static let tvSectionSpacing: CGFloat = 36
    public static let tvRailSpacing: CGFloat = 28
    public static let tvSectionHeaderSpacing: CGFloat = 18
    public static let tvRailVerticalPadding: CGFloat = 20
    public static let tvCardMetadataSpacing: CGFloat = 16
    public static let tvSectionHorizontalPadding: CGFloat = 56
    public static let tvTopNavigationBarMaxWidth: CGFloat = 760
    public static let tvTopNavigationBarHeight: CGFloat = 64
    public static let tvTopNavigationItemHeight: CGFloat = 52
    public static let tvTopNavigationHorizontalPadding: CGFloat = 14

    // tvOS Focus & State Design Tokens
    public static let tvFocusScale: CGFloat = 1.06
    public static let tvFocusShadowRadius: CGFloat = 40
    public static let tvFocusShadowY: CGFloat = 22
    public static let tvFocusShadowOpacity: Double = 0.50
    public static let tvRestShadowRadius: CGFloat = 14
    public static let tvRestShadowY: CGFloat = 8
    public static let tvRestShadowOpacity: Double = 0.20
    public static let tvFocusSpecularOpacity: Double = 0.30
    public static let tvFocusSpring = Animation.spring(response: 0.35, dampingFraction: 0.78)
    public static let tvResumeAccent = Color(red: 0.30, green: 0.72, blue: 0.90)
    public static let tvProgressTrack = Color.white.opacity(0.18)
    public static let tvProgressFill = Color.white.opacity(0.88)
    public static let tvProgressResumeFill = Color(red: 0.30, green: 0.72, blue: 0.90)
    public static let tvWatchedDim: Double = 0.60

    public static let onboardingStageWidthCompact: CGFloat = 420
    public static let onboardingStageWidthRegular: CGFloat = 560
    public static let onboardingHeroCornerRadius: CGFloat = 34
    public static let onboardingCardCornerRadius: CGFloat = 30
    public static let onboardingSheetCornerRadius: CGFloat = 34
    public static let onboardingFieldCornerRadius: CGFloat = 22
    public static let onboardingPillHeight: CGFloat = 58
    public static let onboardingCardShadowRadius: CGFloat = 28
    public static let onboardingCardShadowYOffset: CGFloat = 18
}

public extension View {
    func reelFinTitleStyle() -> some View {
        self
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(.white)
    }

    func reelFinSectionStyle() -> some View {
        self
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
    }

    func glassPanelStyle(cornerRadius: CGFloat = ReelFinTheme.glassPanelCornerRadius) -> some View {
        reelFinGlassPanel(cornerRadius: cornerRadius)
    }

    func tvCardSurface(focused: Bool, selected: Bool = false, cornerRadius: CGFloat = ReelFinTheme.tvCardCornerRadius) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                focused ? ReelFinTheme.tvSurfaceElevatedFill : (selected ? ReelFinTheme.tvSelectedFill : ReelFinTheme.tvSurfaceMutedFill),
                                focused ? Color.white.opacity(0.10) : Color.white.opacity(selected ? 0.05 : 0.015)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tvCardSurfaceStroke(focused: focused, selected: selected), lineWidth: focused ? 1.6 : 1)
            }
            .shadow(color: .black.opacity(focused ? 0.42 : 0.24), radius: focused ? 32 : 18, x: 0, y: focused ? 18 : 10)
    }

    func tvSectionPanel(cornerRadius: CGFloat = 30) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.042),
                                Color.white.opacity(0.016)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.075), lineWidth: 1)
            }
    }

    private func tvCardSurfaceStroke(focused: Bool, selected: Bool) -> Color {
        if focused {
            return ReelFinTheme.tvStrongStroke
        }
        if selected {
            return Color.white.opacity(0.16)
        }
        return ReelFinTheme.tvStroke
    }

    /// Unified tvOS focus elevation: scale + shadow + specular rim.
    /// Use on artwork containers inside episode/poster cards.
    func tvFocusElevation(focused: Bool, cornerRadius: CGFloat = ReelFinTheme.tvCardCornerRadius) -> some View {
        self
            .scaleEffect(focused ? ReelFinTheme.tvFocusScale : 1)
            .shadow(
                color: .black.opacity(focused ? ReelFinTheme.tvFocusShadowOpacity : ReelFinTheme.tvRestShadowOpacity),
                radius: focused ? ReelFinTheme.tvFocusShadowRadius : ReelFinTheme.tvRestShadowRadius,
                x: 0,
                y: focused ? ReelFinTheme.tvFocusShadowY : ReelFinTheme.tvRestShadowY
            )
            .animation(ReelFinTheme.tvFocusSpring, value: focused)
    }
}

public enum TVMotion {
    public enum FocusRole: Sendable {
        case heroButton
        case navItem
        case chip
        case posterCard
        case episodeCard
        case libraryPoster

        fileprivate var scale: CGFloat {
            switch self {
            case .heroButton:
                return 1.03
            case .navItem:
                return 1.02
            case .chip:
                return 1.03
            case .posterCard:
                return 1.04
            case .episodeCard:
                return 1.03
            case .libraryPoster:
                return 1.03
            }
        }

        fileprivate var focusedOpacity: Double {
            switch self {
            case .heroButton, .navItem, .chip, .posterCard, .episodeCard, .libraryPoster:
                return 1.0
            }
        }

        fileprivate var restingOpacity: Double {
            switch self {
            case .heroButton:
                return 0.97
            case .navItem:
                return 0.94
            case .chip:
                return 0.90
            case .posterCard:
                return 0.96
            case .episodeCard:
                return 0.95
            case .libraryPoster:
                return 0.96
            }
        }

        fileprivate var selectedOpacity: Double {
            switch self {
            case .heroButton:
                return 0.98
            case .navItem:
                return 0.98
            case .chip:
                return 0.96
            case .posterCard, .episodeCard, .libraryPoster:
                return 1.0
            }
        }
    }

    public static let focusAnimation = Animation.easeOut(duration: 0.16)
    public static let contentFadeAnimation = Animation.easeInOut(duration: 0.18)
    public static let titleLoadAnimation = Animation.easeInOut(duration: 0.22)
    public static let heroPageAnimation = Animation.easeInOut(duration: 0.20)
    public static let overlayFadeAnimation = Animation.easeInOut(duration: 0.14)
}

public extension View {
    func tvMotionFocus(
        _ role: TVMotion.FocusRole,
        isFocused: Bool,
        isSelected: Bool = false
    ) -> some View {
        modifier(
            TVMotionFocusModifier(
                role: role,
                isFocused: isFocused,
                isSelected: isSelected
            )
        )
    }
}

private struct TVMotionFocusModifier: ViewModifier {
    let role: TVMotion.FocusRole
    let isFocused: Bool
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? role.scale : 1)
            .opacity(isFocused ? role.focusedOpacity : (isSelected ? role.selectedOpacity : role.restingOpacity))
            .animation(TVMotion.focusAnimation, value: isFocused)
            .animation(TVMotion.focusAnimation, value: isSelected)
    }
}
