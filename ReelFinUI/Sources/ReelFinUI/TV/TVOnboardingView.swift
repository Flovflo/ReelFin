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
        ZStack {
            TVOnboardingHeroView(item: currentItem)
                .id(currentItem.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)

            VStack(alignment: .leading, spacing: 0) {
                Text("ReelFin")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))

                Spacer(minLength: 40)

                HStack(alignment: .bottom, spacing: 48) {
                    TVOnboardingCopyBlock(
                        item: currentItem,
                        currentIndex: deck.index,
                        count: deck.count
                    )

                    Spacer(minLength: 32)

                    TVOnboardingControls(
                        isFirstPage: deck.isFirstPage,
                        isLastPage: deck.isLastPage,
                        focusedControl: $focusedControl,
                        onBack: retreat,
                        onContinue: advance
                    )
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
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
        .animation(pageAnimation, value: deck.index)
    }

    private var currentItem: TVOnboardingItem {
        TVOnboardingContent.items[deck.index]
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.42, extraBounce: 0.02)
    }

    private func advance() {
        guard !deck.isLastPage else {
            onComplete()
            return
        }

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

private struct TVOnboardingCopyBlock: View {
    let item: TVOnboardingItem
    let currentIndex: Int
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(item.title)
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .accessibilityIdentifier("tv_onboarding_title")

            Text(item.subtitle)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            TVOnboardingIndicator(count: count, currentIndex: currentIndex)
        }
        .frame(maxWidth: 820, alignment: .leading)
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
    @FocusState.Binding var focusedControl: TVOnboardingControl?
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            if !isFirstPage {
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

            Button(action: onContinue) {
                Label(
                    isLastPage ? "Connect My Server" : "Continue",
                    systemImage: isLastPage ? "server.rack" : "arrow.right"
                )
                .font(.system(size: 30, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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
}

#Preview("TV Onboarding") {
    TVOnboardingView { }
}
#endif
