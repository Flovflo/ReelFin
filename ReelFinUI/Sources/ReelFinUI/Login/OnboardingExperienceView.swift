#if os(iOS)
import SwiftUI

struct PremiumOnboardingStageView: View {
    let currentPage: Int
    let onPageChange: (Int) -> Void
    let onComplete: () -> Void

    var body: some View {
        iOS26StyleOnBoarding(
            tint: ReelFinOnboardingContent.tint,
            hideBezels: false,
            items: ReelFinOnboardingContent.items,
            initialIndex: currentPage,
            onIndexChange: onPageChange,
            onComplete: onComplete
        )
    }
}

#endif
