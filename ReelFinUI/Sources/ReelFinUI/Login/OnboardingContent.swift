#if os(iOS)
import SwiftUI

enum OnboardingPalette {
    static let backgroundTop = Color(red: 0.046, green: 0.052, blue: 0.072)
    static let backgroundBottom = Color(red: 0.010, green: 0.012, blue: 0.018)
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.72)
    static let tertiaryText = Color.white.opacity(0.54)
    static let glowWhite = Color.white.opacity(0.84)
    static let panelTint = Color.white.opacity(0.028)
    static let panelStroke = Color.white.opacity(0.06)
    static let edgeHighlight = Color.white.opacity(0.18)
    static let buttonText = Color.white.opacity(0.97)
    static let buttonTint = Color(red: 0.430, green: 0.480, blue: 0.760)
    static let buttonGlow = Color(red: 0.660, green: 0.720, blue: 0.960)
    static let chromeFill = Color.white.opacity(0.04)
    static let shadow = Color.black.opacity(0.18)

    static let iceBlue = Color(red: 0.520, green: 0.670, blue: 0.860)
    static let moonstone = Color(red: 0.760, green: 0.830, blue: 0.940)
    static let steel = Color(red: 0.470, green: 0.610, blue: 0.790)
    static let teal = Color(red: 0.450, green: 0.740, blue: 0.760)
    static let violet = Color(red: 0.520, green: 0.560, blue: 0.820)
    static let gold = Color(red: 0.820, green: 0.700, blue: 0.470)
    static let brass = Color(red: 0.620, green: 0.520, blue: 0.330)
}

struct OnboardingPageContent: Identifiable {
    enum HeroStyle {
        case floatingCards
        case playbackPipeline
        case qualityBadges
        case browserPreview
    }

    let id: Int
    let title: String
    let body: String
    let ctaTitle: String
    let heroStyle: HeroStyle
    let accent: Color
    let glow: Color
    let heroPosterAssets: [String]

    init(
        id: Int,
        title: String,
        body: String,
        ctaTitle: String,
        heroStyle: HeroStyle,
        accent: Color,
        glow: Color,
        heroPosterAssets: [String] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.ctaTitle = ctaTitle
        self.heroStyle = heroStyle
        self.accent = accent
        self.glow = glow
        self.heroPosterAssets = heroPosterAssets
    }

    static let pages: [OnboardingPageContent] = [
        .init(
            id: 0,
            title: "Built to feel at home on Apple",
            body: "Native motion, focus, and playback for iPhone, iPad, and Apple TV.",
            ctaTitle: "Continue",
            heroStyle: .floatingCards,
            accent: OnboardingPalette.iceBlue,
            glow: OnboardingPalette.moonstone,
            heroPosterAssets: OnboardingPosterLibrary.appleNativeHero
        ),
        .init(
            id: 1,
            title: "Playback that adapts intelligently",
            body: "ReelFin chooses the best path automatically, keeping direct play fast, remux precise, and difficult formats graceful.",
            ctaTitle: "Next",
            heroStyle: .playbackPipeline,
            accent: OnboardingPalette.steel,
            glow: OnboardingPalette.violet
        ),
        .init(
            id: 2,
            title: "Quality handled with care",
            body: "HDR, Dolby Vision, surround audio, and high bitrate masters keep their impact, detail, and atmosphere.",
            ctaTitle: "Next",
            heroStyle: .qualityBadges,
            accent: OnboardingPalette.gold,
            glow: OnboardingPalette.teal
        ),
        .init(
            id: 3,
            title: "Fast, fluid, and ready to watch",
            body: "Browse quickly, open details instantly, and settle into playback with an interface designed for focus and momentum.",
            ctaTitle: "Get Started",
            heroStyle: .browserPreview,
            accent: OnboardingPalette.teal,
            glow: OnboardingPalette.iceBlue
        )
    ]
}

enum OnboardingPosterLibrary {
    static let appleNativeHero = [
        "onboarding-poster-1.jpg",
        "onboarding-poster-3.jpg",
        "onboarding-poster-2.jpg",
        "onboarding-poster-4.jpg",
        "onboarding-poster-5.webp"
    ]
}
#endif
