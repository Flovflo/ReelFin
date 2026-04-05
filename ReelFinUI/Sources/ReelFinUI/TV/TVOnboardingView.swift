#if os(tvOS)
import SwiftUI

struct TVOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedControl: TVOnboardingControl?

    @State private var currentIndex: Int
    @State private var contentVisible = false

    let onComplete: () -> Void

    init(initialIndex: Int? = nil, onComplete: @escaping () -> Void) {
        let lastIndex = max(TVOnboardingContent.items.count - 1, 0)
        let clampedIndex = min(max(initialIndex ?? 0, 0), lastIndex)
        _currentIndex = State(initialValue: clampedIndex)
        self.onComplete = onComplete
    }

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = min(proxy.size.width - 150, 960)

            ZStack(alignment: .bottom) {
                TVLoginBackgroundView(
                    accent: currentItem.accent,
                    secondaryAccent: currentItem.secondaryAccent
                )

                TVOnboardingShowcaseView(
                    items: TVOnboardingContent.items,
                    currentIndex: currentIndex
                )
                .padding(.top, 54)
                .padding(.horizontal, 28)
                .padding(.bottom, 226)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                VStack(spacing: 12) {
                    TVOnboardingCopyBlock(item: currentItem, currentIndex: currentIndex)
                    TVOnboardingIndicator(count: TVOnboardingContent.items.count, currentIndex: currentIndex)
                    TVOnboardingControls(
                        isFirstPage: currentIndex == 0,
                        isLastPage: currentIndex == TVOnboardingContent.items.count - 1,
                        focusedControl: $focusedControl,
                        onBack: retreat,
                        onContinue: advance
                    )
                }
                .frame(width: panelWidth)
                .padding(.top, 22)
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
                .background {
                    TVOnboardingBottomPanel()
                }
                .padding(.bottom, 42)

                TVLoginBrandHeader()
                    .padding(.top, 42)
                    .padding(.leading, 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .opacity(contentVisible ? 1 : 0)
            .offset(y: contentVisible ? 0 : 18)
        }
        .preferredColorScheme(.dark)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear(perform: handleAppear)
        .animation(pageAnimation, value: currentIndex)
    }

    private var currentItem: TVOnboardingItem {
        TVOnboardingContent.items[currentIndex]
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.42, extraBounce: 0.02)
    }

    private func handleAppear() {
        guard !contentVisible else { return }

        withAnimation(pageAnimation) {
            contentVisible = true
        }

        Task {
            if !reduceMotion {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            await MainActor.run {
                focusedControl = .primary
            }
        }
    }

    private func advance() {
        if currentIndex == TVOnboardingContent.items.count - 1 {
            onComplete()
            return
        }

        withAnimation(pageAnimation) {
            currentIndex += 1
        }
        focusedControl = .primary
    }

    private func retreat() {
        guard currentIndex > 0 else { return }

        withAnimation(pageAnimation) {
            currentIndex -= 1
        }
        focusedControl = .primary
    }
}

private enum TVOnboardingControl: Hashable {
    case back
    case primary
}

private struct TVOnboardingCopyBlock: View {
    let item: TVOnboardingItem
    let currentIndex: Int

    var body: some View {
        VStack(spacing: 8) {
            Text(item.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("tv_onboarding_title_\(currentIndex)")

            Text(item.subtitle)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TVOnboardingIndicator: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(index == currentIndex ? 1 : 0.34))
                    .frame(width: index == currentIndex ? 28 : 7, height: 7)
            }
        }
        .accessibilityIdentifier("tv_onboarding_progress")
    }
}

private struct TVOnboardingControls: View {
    let isFirstPage: Bool
    let isLastPage: Bool
    @FocusState.Binding var focusedControl: TVOnboardingControl?
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            TVLoginActionButton(
                title: "Back",
                icon: "chevron.left",
                style: .secondary,
                isEnabled: !isFirstPage,
                action: onBack
            )
            .focused($focusedControl, equals: .back)
            .opacity(isFirstPage ? 0.001 : 1)

            TVLoginActionButton(
                title: isLastPage ? "Get Started" : "Continue",
                icon: isLastPage ? "arrow.right.circle.fill" : "arrow.right",
                style: .primary,
                action: onContinue
            )
            .focused($focusedControl, equals: .primary)
            .accessibilityIdentifier("tv_onboarding_primary_cta")
        }
    }
}

private struct TVOnboardingBottomPanel: View {
    var body: some View {
        ZStack {
            Color.clear.reelFinGlassRoundedRect(
                cornerRadius: 34,
                tint: Color.white.opacity(0.04),
                stroke: Color.white.opacity(0.08),
                shadowOpacity: 0.14,
                shadowRadius: 24,
                shadowYOffset: 14
            )

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.30),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

#Preview("TV Onboarding") {
    TVOnboardingView { }
}
#endif
