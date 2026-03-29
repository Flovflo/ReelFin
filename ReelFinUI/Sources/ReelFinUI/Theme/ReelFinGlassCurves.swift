import SwiftUI

public extension View {
    func reelFinGlassCapsule(
        interactive: Bool = false,
        tint: Color = Color.white.opacity(0.08),
        stroke: Color = Color.white.opacity(0.12),
        strokeWidth: CGFloat = 1,
        shadowOpacity: Double = 0.12,
        shadowRadius: CGFloat = 12,
        shadowYOffset: CGFloat = 6
    ) -> some View {
        modifier(
            ReelFinGlassCapsuleModifier(
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

    func reelFinGlassCircle(
        interactive: Bool = false,
        tint: Color = Color.white.opacity(0.08),
        stroke: Color = Color.white.opacity(0.12),
        strokeWidth: CGFloat = 1,
        shadowOpacity: Double = 0.12,
        shadowRadius: CGFloat = 12,
        shadowYOffset: CGFloat = 6
    ) -> some View {
        modifier(
            ReelFinGlassCircleModifier(
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

private struct ReelFinGlassCapsuleModifier: ViewModifier {
    let interactive: Bool
    let tint: Color
    let stroke: Color
    let strokeWidth: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .background { capsuleBackground }
            .overlay { Capsule(style: .continuous).stroke(stroke, lineWidth: strokeWidth) }
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowYOffset)
    }

    @ViewBuilder
    private var capsuleBackground: some View {
        if #available(iOS 26.0, tvOS 26.0, *) {
            Color.clear.glassEffect(resolvedGlass, in: .capsule)
        } else {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
        }
    }

    @available(iOS 26.0, tvOS 26.0, *)
    private var resolvedGlass: Glass {
        interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint)
    }
}

private struct ReelFinGlassCircleModifier: ViewModifier {
    let interactive: Bool
    let tint: Color
    let stroke: Color
    let strokeWidth: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .background { circleBackground }
            .overlay { Circle().stroke(stroke, lineWidth: strokeWidth) }
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowYOffset)
    }

    @ViewBuilder
    private var circleBackground: some View {
        if #available(iOS 26.0, tvOS 26.0, *) {
            Color.clear.glassEffect(resolvedGlass, in: .circle)
        } else {
            Circle().fill(.ultraThinMaterial)
        }
    }

    @available(iOS 26.0, tvOS 26.0, *)
    private var resolvedGlass: Glass {
        interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint)
    }
}
