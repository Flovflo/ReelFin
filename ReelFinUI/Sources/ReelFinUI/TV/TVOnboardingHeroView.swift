#if os(tvOS)
import SwiftUI
import UIKit

struct TVOnboardingHeroView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    let item: TVOnboardingItem

    private var motion: TVOnboardingMotionConfiguration {
        TVOnboardingMotionPolicy.configuration(reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack {
            TVOnboardingScreenshotImage(name: item.screenshotName)
                .aspectRatio(contentMode: .fill)
                .scaleEffect(
                    item.zoomScale * (motion.allowsScale && drifting ? 1.025 : 1.0),
                    anchor: item.zoomAnchor
                )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.18),
                    .init(color: .black.opacity(0.48), location: 0.68),
                    .init(color: .black.opacity(0.80), location: 1)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
        .clipped()
        .accessibilityHidden(true)
        .onAppear {
            drifting = motion.allowsDrift
        }
        .animation(
            motion.allowsDrift
                ? .easeInOut(duration: 8).repeatForever(autoreverses: true)
                : .linear(duration: 0.01),
            value: drifting
        )
    }
}

struct TVOnboardingScreenshotImage: View {
    let name: String

    var body: some View {
        if let screenshot = UIImage(named: name, in: .main, with: nil) {
            Image(uiImage: screenshot)
                .resizable()
        } else {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.04),
                    Color.black.opacity(0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
#endif
