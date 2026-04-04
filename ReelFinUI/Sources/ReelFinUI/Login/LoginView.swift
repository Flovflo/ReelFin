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
    private let settingsStore: SettingsStoreProtocol
    private let imagePipeline: any ImagePipelineProtocol

    @State private var phase: LoginPhase
    @State private var contentVisible = false
    @State private var onboardingPageIndex: Int

    init(dependencies: ReelFinDependencies, onLogin: @escaping (UserSession) -> Void) {
        let initialPhase = Self.initialPhase(settingsStore: dependencies.settingsStore)
        _viewModel = StateObject(wrappedValue: LoginViewModel(dependencies: dependencies))
        _phase = State(initialValue: initialPhase)
        _onboardingPageIndex = State(initialValue: Self.initialOnboardingPageIndex)
        settingsStore = dependencies.settingsStore
        imagePipeline = dependencies.imagePipeline
        self.onLogin = onLogin
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = LoginLayoutMetrics(size: proxy.size, sizeClass: horizontalSizeClass)

            ZStack {
                backgroundView(compact: metrics.isCompact)

                Group {
                    if phase == .onboarding || phase == .serverEntry {
                        stageContent(metrics: metrics)
                            .frame(maxWidth: stageWidth(for: metrics))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 0) {
                            LoginChromeView(
                                compact: metrics.isCompact,
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
                    }
                }
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .preferredColorScheme(.dark)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear {
            guard !contentVisible else { return }
            withAnimation(entranceAnimation) {
                contentVisible = true
            }
        }
        .onChange(of: viewModel.serverURLText) { _, _ in
            viewModel.serverURLDidChange()
        }
    }

    @ViewBuilder
    private func backgroundView(compact: Bool) -> some View {
        if phase == .onboarding || phase == .serverEntry {
            TemplateOnboardingBackgroundView(compact: compact)
        } else {
            OnboardingBackgroundView(
                accent: OnboardingPalette.blue,
                glow: OnboardingPalette.violet,
                compact: compact
            )
        }
    }

    private var canGoBack: Bool {
        switch phase {
        case .onboarding:
            return false
        case .serverEntry:
            return false
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
                currentPage: onboardingPageIndex,
                onPageChange: { onboardingPageIndex = $0 },
                onComplete: completeOnboardingAndEnterServer
            )
            .transition(stageTransition)
        case .serverEntry:
            ConnectionLandingShowcaseView(
                compact: metrics.isCompact,
                imagePipeline: imagePipeline,
                serverURLText: $viewModel.serverURLText,
                focusedField: $focusedField,
                hasSavedServer: viewModel.hasSavedServer,
                isTestingConnection: viewModel.isTestingConnection,
                serverMessage: viewModel.serverMessage,
                serverErrorMessage: viewModel.serverErrorMessage,
                canContinue: viewModel.canAdvanceFromServer,
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
        switch phase {
        case .onboarding, .serverEntry:
            return metrics.onboardingWidth
        case .credentials, .submitting, .success:
            return metrics.contentWidth
        }
    }

    private var stageTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.985))
    }

    private var serverHost: String {
        URL(string: viewModel.serverURLText.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "Jellyfin"
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
            break
        case .credentials, .submitting:
            viewModel.clearAuthError()
            transition(to: .serverEntry)
            focus(.serverURL)
        case .success:
            break
        }
    }

    private func completeOnboardingAndEnterServer() {
        settingsStore.hasCompletedOnboarding = true
        settingsStore.completedOnboardingVersion = ReelFinOnboardingContent.version
        transition(to: .serverEntry)
        focus(.serverURL)
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

    private static func initialPhase(settingsStore: SettingsStoreProtocol) -> LoginPhase {
        if LoginDebugOptions.forceOnboarding {
            return .onboarding
        }

        if settingsStore.completedOnboardingVersion >= ReelFinOnboardingContent.version {
            return .serverEntry
        }

        return .onboarding
    }

    private static var initialOnboardingPageIndex: Int {
        guard let overridePage = LoginDebugOptions.onboardingPage else { return 0 }
        let lastIndex = max(ReelFinOnboardingContent.items.count - 1, 0)
        return min(max(overridePage, 0), lastIndex)
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
    static let forceOnboarding = ProcessInfo.processInfo.arguments.contains("-reelfin-force-onboarding")

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
        topPadding = compact ? 14 : 18
        topSpacer = compact ? max(28, size.height * 0.11) : max(40, size.height * 0.12)
        bottomSpacer = compact ? 28 : 44
        titleSize = compact ? 32 : 40
        bodySize = compact ? 17 : 18
        formTitleSize = compact ? 30 : 36
        formBodySize = compact ? 16 : 17
    }
}

private struct LoginChromeView: View {
    let compact: Bool
    let canGoBack: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Text("ReelFin")
                    .font(.system(size: compact ? 18 : 20, weight: .bold))
                    .foregroundStyle(OnboardingPalette.primaryText)

                if !compact {
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
