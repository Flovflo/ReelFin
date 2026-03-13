import SwiftUI

struct TVTopBackdropOverlay: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.03),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 120)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.018))
                    .frame(height: 1)
            }
            .blur(radius: 10)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
