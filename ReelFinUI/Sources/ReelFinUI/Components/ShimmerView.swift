import SwiftUI

enum ShimmerAnimationBranch: String, Hashable, Identifiable {
    case `static`
    case animated

    var id: Self { self }
}

enum ShimmerAnimationPolicy {
    static func branch(animationEnabled: Bool, reduceMotion: Bool) -> ShimmerAnimationBranch {
        animationEnabled && !reduceMotion ? .animated : .static
    }
}

public struct ShimmerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let animationEnabled: Bool

    public init(animationEnabled: Bool = true) {
        self.animationEnabled = animationEnabled
    }

    @ViewBuilder
    public var body: some View {
#if os(tvOS)
        StaticShimmerView()
            .id(ShimmerAnimationBranch.static)
#else
        let branch = ShimmerAnimationPolicy.branch(
            animationEnabled: animationEnabled,
            reduceMotion: reduceMotion
        )

        switch branch {
        case .static:
            StaticShimmerView()
                .id(branch)
        case .animated:
            AnimatedShimmerView()
                .id(branch)
        }
#endif
    }
}

private struct StaticShimmerView: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.white.opacity(0.16),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.6)
            }
            .clipped()
    }
}

#if !os(tvOS)
private struct AnimatedShimmerView: View {
    @State private var phase: CGFloat = -0.7

    var body: some View {
        GeometryReader { geometry in
            let gradient = LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.26),
                    Color.white.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .overlay {
                    gradient
                        .frame(width: geometry.size.width * 0.9)
                        .offset(x: geometry.size.width * phase)
                }
                .clipped()
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1.2
                    }
                }
        }
    }
}
#endif
