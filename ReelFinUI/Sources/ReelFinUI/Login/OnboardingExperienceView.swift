#if os(iOS)
import Shared
import SwiftUI

struct PremiumOnboardingStageView: View {
    let compact: Bool
    let page: OnboardingPageContent
    let currentPage: Int
    let pageCount: Int
    let titleSize: CGFloat
    let bodySize: CGFloat
    let imagePipeline: any ImagePipelineProtocol
    let onSelectPage: (Int) -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: compact ? 26 : 32) {
            OnboardingHeroStack(
                page: page,
                compact: compact,
                imagePipeline: imagePipeline
            )
            .frame(height: compact ? 310 : 360)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            VStack(spacing: compact ? 18 : 22) {
                VStack(spacing: 12) {
                    Text(page.title)
                        .font(.system(size: titleSize, weight: .bold))
                        .tracking(-0.7)
                        .foregroundStyle(OnboardingPalette.primaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("onboarding_title")

                    Text(page.body)
                        .font(.system(size: bodySize, weight: .medium))
                        .foregroundStyle(OnboardingPalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CustomPageProgress(
                    currentPage: currentPage,
                    pageCount: pageCount,
                    onSelect: onSelectPage
                )
                .frame(maxWidth: compact ? 320 : 360)

                PremiumCTAButton(
                    title: page.ctaTitle,
                    action: onContinue
                )
                .accessibilityIdentifier("onboarding_primary_cta")
            }
            .frame(maxWidth: compact ? 360 : 430)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, compact ? 8 : 0)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
