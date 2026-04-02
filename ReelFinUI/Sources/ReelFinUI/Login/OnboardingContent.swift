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

#endif
