#if os(tvOS)
import SwiftUI

struct TVLoginBackgroundView: View {
    let accent: Color
    let secondaryAccent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.026, green: 0.032, blue: 0.052),
                    Color(red: 0.009, green: 0.012, blue: 0.022),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [accent.opacity(0.13), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 920
            )

            RadialGradient(
                colors: [secondaryAccent.opacity(0.07), .clear],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 840
            )

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
