#if os(tvOS)
import SwiftUI
import UIKit

struct TVOnboardingHeroView: View {
    let item: TVOnboardingItem

    var body: some View {
        GeometryReader { proxy in
            let metrics = TVOnboardingLayoutPolicy.metrics(for: proxy.size)

            ZStack(alignment: .topTrailing) {
                TVOnboardingBackdrop()

                TVOnboardingScreenshotImage(name: item.screenshotName)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(
                        width: metrics.heroFrame.width,
                        height: metrics.heroFrame.height
                    )
                    .clipShape(.rect(cornerRadius: 38))
                    .overlay {
                        RoundedRectangle(cornerRadius: 38, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.42),
                                        .white.opacity(0.12),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                    .shadow(color: .black.opacity(0.58), radius: 44, y: 24)
                    .position(
                        x: metrics.heroFrame.midX,
                        y: metrics.heroFrame.midY
                    )
                    .accessibilityIdentifier("tv_onboarding_product_screen")
            }
        }
        .accessibilityHidden(true)
    }
}

private struct TVOnboardingBackdrop: View {
    var body: some View {
        ZStack {
            Color.black

            RadialGradient(
                colors: [
                    Color(red: 0.10, green: 0.22, blue: 0.34).opacity(0.42),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 1_150
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.54),
                    Color.black.opacity(0.92)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }
}

struct TVOnboardingScreenshotImage: View {
    let name: String

    var body: some View {
        if let screenshot = UIImage(named: name, in: .main, with: nil) {
            Image(uiImage: screenshot)
                .resizable()
        } else {
            ContentUnavailableView(
                "Product screen unavailable",
                systemImage: "photo.badge.exclamationmark",
                description: Text(name)
            )
            .background(Color.black.opacity(0.82))
        }
    }
}
#endif
