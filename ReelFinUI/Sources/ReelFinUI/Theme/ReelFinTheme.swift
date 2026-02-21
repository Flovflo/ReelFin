import SwiftUI

public enum ReelFinTheme {
    public static let background = Color(red: 0.02, green: 0.03, blue: 0.05)
    public static let surface = Color(red: 0.08, green: 0.09, blue: 0.13)
    public static let card = Color(red: 0.11, green: 0.13, blue: 0.19)
    public static let accent = Color(red: 0.05, green: 0.52, blue: 1.0)
    public static let accentSecondary = Color(red: 0.35, green: 0.78, blue: 0.98)

    public static let pageGradient = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.13, blue: 0.20).opacity(0.95),
            Color(red: 0.04, green: 0.05, blue: 0.08),
            Color.black.opacity(0.96)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let heroGradient = LinearGradient(
        colors: [
            Color.black.opacity(0.08),
            Color.black.opacity(0.38),
            Color.black.opacity(0.84)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let panelStroke = Color.white.opacity(0.08)
}

public extension View {
    func reelFinTitleStyle() -> some View {
        self
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(.white)
    }

    func reelFinSectionStyle() -> some View {
        self
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
    }
}
