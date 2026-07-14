#if os(tvOS)
import SwiftUI

struct TVOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedControl: TVOnboardingControl?

    @State private var deck: TVOnboardingDeckState

    let onComplete: () -> Void

    init(initialIndex: Int? = nil, onComplete: @escaping () -> Void) {
        _deck = State(
            initialValue: TVOnboardingDeckState(
                initialIndex: initialIndex,
                count: TVOnboardingContent.items.count
            )
        )
        self.onComplete = onComplete
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = TVOnboardingLayoutPolicy.metrics(for: proxy.size)

            ZStack {
                TVOnboardingHeroView(item: currentItem)
                    .id("onboarding-hero-\(deck.index)")
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(.opacity)

                TVOnboardingForeground(
                    item: currentItem,
                    currentIndex: deck.index,
                    count: deck.count,
                    metrics: metrics,
                    focusedControl: $focusedControl,
                    onBack: retreat,
                    onContinue: advance
                )
                .id("onboarding-content-\(deck.index)")
                .transition(foregroundTransition)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tv_onboarding_screen")
        .preferredColorScheme(.dark)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .defaultFocus($focusedControl, .primary, priority: .userInitiated)
        .onAppear {
            focusedControl = .primary
        }
        .onExitCommand(perform: retreat)
    }

    private var currentItem: TVOnboardingItem {
        TVOnboardingContent.items[deck.index]
    }

    private var motion: TVOnboardingMotionConfiguration {
        TVOnboardingMotionPolicy.configuration(reduceMotion: reduceMotion)
    }

    private var pageAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .smooth(duration: 0.42, extraBounce: motion.allowsBounce ? 0.02 : 0)
    }

    private var foregroundTransition: AnyTransition {
        guard motion.pageOffset > 0 else { return .opacity }

        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: motion.pageOffset)),
            removal: .opacity.combined(with: .offset(x: -(motion.pageOffset * 0.55)))
        )
    }

    private func advance() {
        guard !deck.isLastPage else {
            onComplete()
            return
        }

        focusedControl = nil
        withAnimation(pageAnimation) {
            _ = deck.advance()
        }
        focusedControl = .primary
    }

    private func retreat() {
        guard !deck.isFirstPage else {
            focusedControl = .primary
            return
        }

        focusedControl = nil
        withAnimation(pageAnimation) {
            _ = deck.retreat()
        }
        focusedControl = .primary
    }
}

private enum TVOnboardingControl: Hashable {
    case back
    case primary
}

private struct TVOnboardingForeground: View {
    let item: TVOnboardingItem
    let currentIndex: Int
    let count: Int
    let metrics: TVOnboardingLayoutMetrics
    @FocusState.Binding var focusedControl: TVOnboardingControl?
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ReelFin")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))

            Spacer(minLength: 32)

            HStack(alignment: .bottom, spacing: metrics.copyToActionsSpacing) {
                TVOnboardingCopyBlock(
                    item: item,
                    currentIndex: currentIndex,
                    count: count
                )
                .frame(width: metrics.copyMaximumWidth, alignment: .leading)

                Spacer(minLength: 0)

                TVOnboardingControls(
                    isFirstPage: currentIndex == 0,
                    isLastPage: currentIndex == count - 1,
                    stacksActions: metrics.stacksActions,
                    focusedControl: $focusedControl,
                    onBack: onBack,
                    onContinue: onContinue
                )
                .padding(.trailing, 8)
                .padding(.bottom, 8)
                .frame(width: metrics.actionRailWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, TVOnboardingLayoutPolicy.horizontalInset)
        .padding(.vertical, TVOnboardingLayoutPolicy.verticalInset)
    }
}

private struct TVOnboardingCopyBlock: View {
    let item: TVOnboardingItem
    let currentIndex: Int
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.title)
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(item.subtitle)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.title). \(item.subtitle)")
            .accessibilityIdentifier("tv_onboarding_title")

            TVOnboardingIndicator(count: count, currentIndex: currentIndex)
        }
        .layoutPriority(1)
    }
}

private struct TVOnboardingIndicator: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(index == currentIndex ? 1 : 0.34))
                    .frame(width: index == currentIndex ? 32 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue("Step \(currentIndex + 1) of \(count)")
        .accessibilityIdentifier("tv_onboarding_progress")
    }
}

private struct TVOnboardingControls: View {
    let isFirstPage: Bool
    let isLastPage: Bool
    let stacksActions: Bool
    @FocusState.Binding var focusedControl: TVOnboardingControl?
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: stacksActions ? 16 : 24) {
            if stacksActions {
                VStack(alignment: .trailing, spacing: 16) {
                    if !isFirstPage {
                        backButton
                    }
                    primaryButton
                }
            } else {
                HStack(spacing: 24) {
                    if !isFirstPage {
                        backButton
                    }
                    primaryButton
                }
            }
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Label("Back", systemImage: "chevron.left")
                .font(.system(size: 30, weight: .semibold))
                .frame(minWidth: 150)
                .frame(height: 76)
                .padding(.horizontal, 20)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 28))
        .focused($focusedControl, equals: .back)
        .accessibilityIdentifier("tv_onboarding_back")
    }

    private var primaryButton: some View {
        Button(action: onContinue) {
            Label(
                isLastPage ? "Connect My Server" : "Continue",
                systemImage: isLastPage ? "server.rack" : "arrow.right"
            )
            .font(.system(size: 30, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(minWidth: 400)
            .frame(height: 76)
            .padding(.horizontal, 24)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 28))
        .focused($focusedControl, equals: .primary)
        .accessibilityIdentifier("tv_onboarding_primary_cta")
    }
}

#Preview("TV Onboarding") {
    TVOnboardingView { }
}
#endif
