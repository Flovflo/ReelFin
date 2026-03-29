import SwiftUI

struct TVTopBackdropOverlay: View {
    let appearance: TVTopNavigationAppearance

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        appearance.railGlowColor.opacity(appearance.backdropOpacity),
                        Color.black.opacity(0.16),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 132)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
