import SwiftUI

public struct ShimmerView: View {
#if os(tvOS)
    public init() {}

    public var body: some View {
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
#else
    @State private var phase: CGFloat = -0.7

    public init() {}

    public var body: some View {
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
#endif
}
