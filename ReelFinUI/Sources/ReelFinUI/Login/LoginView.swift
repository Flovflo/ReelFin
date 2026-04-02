#if os(iOS)
import Shared
import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var viewModel: LoginViewModel
    @FocusState private var focusedField: LoginFocusField?

    private let onLogin: (UserSession) -> Void
    private let imagePipeline: any ImagePipelineProtocol

    @State private var phase: LoginPhase = .onboarding
    @State private var contentVisible = false
    @State private var onboardingPageIndex = 0

    init(dependencies: ReelFinDependencies, onLogin: @escaping (UserSession) -> Void) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(dependencies: dependencies))
        imagePipeline = dependencies.imagePipeline
        self.onLogin = onLogin
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = LoginLayoutMetrics(size: proxy.size, sizeClass: horizontalSizeClass)

            ZStack {
                OnboardingBackgroundView(
                    accent: activeVisualPage.accent,
                    glow: activeVisualPage.glow,
                    compact: metrics.isCompact
                )

                VStack(spacing: 0) {
                    LoginChromeView(
                        canGoBack: canGoBack,
                        onBack: handleBack
                    )
                    .padding(.top, proxy.safeAreaInsets.top + metrics.topPadding)

                    Spacer(minLength: metrics.topSpacer)

                    stageContent(metrics: metrics)
                        .frame(maxWidth: stageWidth(for: metrics))

                    Spacer(minLength: metrics.bottomSpacer)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .preferredColorScheme(.dark)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear {
            applyDebugOverridesIfNeeded()

            guard !contentVisible else { return }
            withAnimation(entranceAnimation) {
                contentVisible = true
            }
        }
        .onChange(of: viewModel.serverURLText) { _, _ in
            viewModel.serverURLDidChange()
        }
    }

    private var activeVisualPage: OnboardingPageContent {
        switch phase {
        case .onboarding:
            OnboardingPageContent.pages[onboardingPageIndex]
        case .serverEntry, .credentials, .submitting, .success:
            OnboardingPageContent.pages[0]
        }
    }

    private var canGoBack: Bool {
        switch phase {
        case .onboarding:
            return false
        case .serverEntry:
            return true
        case .credentials, .submitting:
            return true
        case .success:
            return false
        }
    }

    private var stageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.14) : .smooth(duration: 0.30, extraBounce: 0.01)
    }

    private var entranceAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.28, extraBounce: 0)
    }

    @ViewBuilder
    private func stageContent(metrics: LoginLayoutMetrics) -> some View {
        switch phase {
        case .onboarding:
            PremiumOnboardingStageView(
                compact: metrics.isCompact,
                page: activeVisualPage,
                currentPage: onboardingPageIndex,
                pageCount: OnboardingPageContent.pages.count,
                titleSize: metrics.titleSize,
                bodySize: metrics.bodySize,
                imagePipeline: imagePipeline,
                onSelectPage: selectOnboardingPage,
                onContinue: advanceFromOnboarding
            )
            .transition(stageTransition)
        case .serverEntry:
            ServerEntryStageView(
                serverURLText: $viewModel.serverURLText,
                focusedField: $focusedField,
                hasSavedServer: viewModel.hasSavedServer,
                isTestingConnection: viewModel.isTestingConnection,
                serverMessage: viewModel.serverMessage,
                serverErrorMessage: viewModel.serverErrorMessage,
                canContinue: viewModel.canAdvanceFromServer,
                titleSize: metrics.titleSize,
                bodySize: metrics.bodySize,
                onContinue: continueFromServer
            )
            .transition(stageTransition)
        case .credentials, .submitting:
            CredentialsStageView(
                username: $viewModel.username,
                password: $viewModel.password,
                focusedField: $focusedField,
                serverHost: serverHost,
                isSubmitting: phase == .submitting,
                authErrorMessage: viewModel.authErrorMessage,
                canSubmit: viewModel.canSubmitCredentials && phase != .submitting,
                titleSize: metrics.formTitleSize,
                bodySize: metrics.formBodySize,
                onSubmit: submitCredentials
            )
            .transition(stageTransition)
        case .success:
            SuccessStageView(
                titleSize: metrics.formTitleSize,
                bodySize: metrics.formBodySize
            )
            .transition(stageTransition)
        }
    }

    private func stageWidth(for metrics: LoginLayoutMetrics) -> CGFloat {
        phase == .onboarding ? metrics.onboardingWidth : metrics.contentWidth
    }

    private var stageTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.985))
    }

    private var serverHost: String {
        URL(string: viewModel.serverURLText.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "Jellyfin"
    }

    private func advanceFromOnboarding() {
        if onboardingPageIndex < OnboardingPageContent.pages.count - 1 {
            withAnimation(stageAnimation) {
                onboardingPageIndex += 1
            }
            return
        }

        transition(to: .serverEntry)
        focus(.serverURL)
    }

    private func selectOnboardingPage(_ index: Int) {
        guard OnboardingPageContent.pages.indices.contains(index) else { return }
        withAnimation(stageAnimation) {
            onboardingPageIndex = index
        }
    }

    private func continueFromServer() {
        guard !viewModel.isTestingConnection else { return }
        focusedField = nil

        let currentServer = viewModel.serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validatedServerURL = viewModel.validatedServerURL,
           currentServer == validatedServerURL.absoluteString
        {
            transition(to: .credentials)
            focus(.username)
            return
        }

        Task {
            let isValid = await viewModel.testConnection()
            guard isValid else { return }

            await MainActor.run {
                transition(to: .credentials)
                focus(.username)
            }
        }
    }

    private func submitCredentials() {
        guard phase != .submitting, viewModel.canSubmitCredentials else { return }

        focusedField = nil
        viewModel.clearAuthError()
        transition(to: .submitting)

        Task {
            if let session = await viewModel.login() {
                await presentSuccess(for: session)
            } else {
                await MainActor.run {
                    transition(to: .credentials)
                    focus(.password)
                }
            }
        }
    }

    private func presentSuccess(for session: UserSession) async {
        await MainActor.run {
            transition(to: .success)
        }

        try? await Task.sleep(nanoseconds: reduceMotion ? 180_000_000 : 360_000_000)

        await MainActor.run {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onLogin(session)
        }
    }

    private func handleBack() {
        switch phase {
        case .onboarding:
            break
        case .serverEntry:
            focusedField = nil
            transition(to: .onboarding)
        case .credentials, .submitting:
            viewModel.clearAuthError()
            transition(to: .serverEntry)
            focus(.serverURL)
        case .success:
            break
        }
    }

    private func transition(to newPhase: LoginPhase) {
        withAnimation(stageAnimation) {
            phase = newPhase
        }
    }

    private func focus(_ field: LoginFocusField) {
        guard !reduceMotion else {
            focusedField = field
            return
        }

        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            await MainActor.run {
                focusedField = field
            }
        }
    }

    private func applyDebugOverridesIfNeeded() {
        guard phase == .onboarding else { return }
        guard let overridePage = LoginDebugOptions.onboardingPage else { return }
        guard OnboardingPageContent.pages.indices.contains(overridePage) else { return }
        onboardingPageIndex = overridePage
    }
}

private enum LoginPhase {
    case onboarding
    case serverEntry
    case credentials
    case submitting
    case success
}

private enum LoginDebugOptions {
    static var onboardingPage: Int? {
        let arguments = ProcessInfo.processInfo.arguments

        guard let flagIndex = arguments.firstIndex(of: "-reelfin-onboarding-page") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        return Int(arguments[valueIndex])
    }
}

private struct LoginLayoutMetrics {
    let isCompact: Bool
    let contentWidth: CGFloat
    let onboardingWidth: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let topSpacer: CGFloat
    let bottomSpacer: CGFloat
    let titleSize: CGFloat
    let bodySize: CGFloat
    let formTitleSize: CGFloat
    let formBodySize: CGFloat

    init(size: CGSize, sizeClass: UserInterfaceSizeClass?) {
        let compact = size.width < 720 || sizeClass != .regular
        isCompact = compact
        contentWidth = compact ? min(size.width - 32, 430) : min(size.width - 120, 500)
        onboardingWidth = compact ? min(size.width - 24, 520) : min(size.width - 120, 680)
        horizontalPadding = compact ? 16 : 24
        topPadding = compact ? 10 : 18
        topSpacer = compact ? max(28, size.height * 0.11) : max(40, size.height * 0.12)
        bottomSpacer = compact ? 28 : 44
        titleSize = compact ? 34 : 40
        bodySize = compact ? 17 : 18
        formTitleSize = compact ? 30 : 36
        formBodySize = compact ? 16 : 17
    }
}

private struct LoginChromeView: View {
    let canGoBack: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Text("ReelFin")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(OnboardingPalette.primaryText)

                Text("for Jellyfin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OnboardingPalette.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        if #available(iOS 26.0, *) {
                            Color.clear
                                .glassEffect(.regular, in: .capsule)
                        } else {
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
            }

            Spacer(minLength: 0)

            if canGoBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(ChromeCircleButtonStyle())
            }
        }
    }
}

#Preview("Logged Out") {
    LoginView(dependencies: ReelFinPreviewFactory.dependencies(authenticated: false)) { _ in }
}
#endif
