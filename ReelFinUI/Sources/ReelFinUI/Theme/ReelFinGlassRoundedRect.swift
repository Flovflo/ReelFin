import SwiftUI

public extension View {
    func reelFinGlassPanel(
        cornerRadius: CGFloat = ReelFinTheme.glassPanelCornerRadius
    ) -> some View {
        reelFinGlassRoundedRect(
            cornerRadius: cornerRadius,
            tint: Color.white.opacity(0.06),
            stroke: ReelFinTheme.glassStrokeColor,
            strokeWidth: ReelFinTheme.glassStrokeWidth,
            shadowOpacity: 0.15,
            shadowRadius: 20,
            shadowYOffset: 10
        )
    }

    func reelFinGlassRoundedRect(
        cornerRadius: CGFloat,
        interactive: Bool = false,
        tint: Color = Color.white.opacity(0.08),
        stroke: Color = Color.white.opacity(0.12),
        strokeWidth: CGFloat = 1,
        shadowOpacity: Double = 0.14,
        shadowRadius: CGFloat = 16,
        shadowYOffset: CGFloat = 8
    ) -> some View {
        modifier(
            ReelFinGlassRoundedRectModifier(
                cornerRadius: cornerRadius,
                interactive: interactive,
                tint: tint,
                stroke: stroke,
                strokeWidth: strokeWidth,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowYOffset: shadowYOffset
            )
        )
    }

}

private struct ReelFinGlassRoundedRectModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool
    let tint: Color
    let stroke: Color
    let strokeWidth: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .background { backgroundShape }
            .overlay { strokeShape }
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowYOffset)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if #available(iOS 26.0, tvOS 26.0, *) {
            Color.clear.glassEffect(resolvedGlass, in: .rect(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var strokeShape: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(stroke, lineWidth: strokeWidth)
    }

    private var resolvedGlass: Glass {
        interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint)
    }
}
