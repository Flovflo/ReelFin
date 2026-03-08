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
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ReelFinTheme.glassStrokeColor, lineWidth: ReelFinTheme.glassStrokeWidth)
            }
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
    }
}
