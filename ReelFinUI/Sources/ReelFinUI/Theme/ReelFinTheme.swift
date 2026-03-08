import SwiftUI

public enum ReelFinTheme {
    // Colors
    public static let background = Color.black
    public static let surface = Color(white: 0.12)
    public static let card = Color(white: 0.16)
    public static let accent = Color.white
    public static let accentSecondary = Color.white.opacity(0.7)

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
