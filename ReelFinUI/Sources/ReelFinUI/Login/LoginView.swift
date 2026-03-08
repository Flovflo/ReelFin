import Shared
import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: LoginViewModel
    @FocusState private var focusedField: FocusField?

    private let onLogin: (UserSession) -> Void

    @State private var phase: OnboardingPhase = .landing
    @State private var contentVisible = false
    @State private var successBounce = false

    init(dependencies: ReelFinDependencies, onLogin: @escaping (UserSession) -> Void) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(dependencies: dependencies))
        self.onLogin = onLogin
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(for: proxy.size)

            ZStack {
                backdrop(size: proxy.size)

                if phase != .success {
                    VStack(alignment: .leading, spacing: 0) {
                        topChrome
                            .padding(.top, proxy.safeAreaInsets.top + metrics.topPadding)

                        Spacer(minLength: metrics.topSpacer)

                        currentStep(metrics: metrics)
                            .frame(maxWidth: metrics.contentWidth, alignment: .leading)

                        Spacer(minLength: metrics.bottomSpacer)

                        bottomAction(metrics: metrics, safeAreaInsets: proxy.safeAreaInsets)
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 12)
                } else {
                    successState
                        .padding(.bottom, proxy.safeAreaInsets.bottom)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .preferredColorScheme(.dark)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear {
            guard !contentVisible else {
                return
            }

            withAnimation(entranceAnimation) {
                contentVisible = true
            }
        }
        .onChange(of: viewModel.serverURLText) { _, _ in
            viewModel.serverURLDidChange()
        }
    }

    private var stageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.38, extraBounce: 0.02)
    }

    private var entranceAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.34, extraBounce: 0.01)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: reduceMotion ? 0 : 10).combined(with: .opacity),
            removal: .opacity
        )
    }

    private var topChrome: some View {
        HStack {
            Text(chromeTitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))

            Spacer()

            if phase != .landing {
                Button {
                    handleBack()
                } label: {
                    Image(systemName: phase == .serverEntry ? "xmark" : "chevron.backward")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.86))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(OnboardingIconButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func currentStep(metrics: LoginMetrics) -> some View {
        switch phase {
        case .landing:
            landingStep(metrics: metrics)
                .transition(stepTransition)
        case .serverEntry:
            serverStep(metrics: metrics)
                .transition(stepTransition)
        case .credentialsSheet, .submitting:
            credentialsStep(metrics: metrics)
                .transition(stepTransition)
        case .success:
            EmptyView()
        }
    }

    private func landingStep(metrics: LoginMetrics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Setup Jellyfin")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))

            Text("Fast. Native. Clean.")
                .font(.system(size: metrics.titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityIdentifier("login_landing_title")

            Text("Just connect your server and sign in.")
                .font(.system(size: metrics.subtitleSize, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            if viewModel.hasSavedServer {
                Text("Saved server ready")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(ReelFinTheme.onboardingMint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .capsuleSurface()
            }
        }
    }

    private func serverStep(metrics: LoginMetrics) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIcon(systemImage: "network")

            Text("Server URL")
                .font(.system(size: metrics.titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Paste your Jellyfin address.")
                .font(.system(size: metrics.subtitleSize, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.60))

            HStack(spacing: 12) {
                TextField("https://server.tld", text: $viewModel.serverURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .serverURL)
                    .submitLabel(.continue)
                    .onSubmit {
                        continueFromServer()
                    }
                    .accessibilityIdentifier("login_server_field")

                Button {
                    continueFromServer()
                } label: {
                    Group {
                        if viewModel.isTestingConnection {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(ReelFinTheme.onboardingButtonText)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(ReelFinTheme.onboardingButtonText)
                        }
                    }
                    .frame(width: 50, height: 50)
                }
                .buttonStyle(OnboardingProminentIconButtonStyle())
                .disabled(!viewModel.canAdvanceFromServer)
                .accessibilityIdentifier("login_server_continue")
            }
            .fieldSurface()

            if viewModel.isTestingConnection {
                feedbackRow(text: "Checking server", tint: ReelFinTheme.onboardingBlue)
            } else if let serverError = viewModel.serverErrorMessage {
                feedbackRow(text: serverError, tint: .red)
            } else if let serverMessage = viewModel.serverMessage {
                feedbackRow(text: serverMessage, tint: ReelFinTheme.onboardingMint)
            }
        }
    }

    private func credentialsStep(metrics: LoginMetrics) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIcon(systemImage: "person.crop.circle")

            Text("Sign in")
                .font(.system(size: metrics.titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(serverHost)
                .font(.system(size: metrics.subtitleSize, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.60))

            VStack(spacing: 12) {
                TextField("Username", text: $viewModel.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textContentType(.username)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .password
                    }
                    .fieldSurface()

                HStack(spacing: 12) {
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            submitCredentials()
                        }
                }
                .fieldSurface()
            }
            .accessibilityIdentifier("login_credentials_sheet")

            if phase == .submitting {
                feedbackRow(text: "Signing in", tint: ReelFinTheme.onboardingBlue)
            } else if let authError = viewModel.authErrorMessage {
                feedbackRow(text: authError, tint: .red)
            }
        }
    }

    private func bottomAction(metrics: LoginMetrics, safeAreaInsets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            switch phase {
            case .landing:
                Button {
                    transition(to: .serverEntry)
                    focus(.serverURL)
                } label: {
                    Text(viewModel.hasSavedServer ? "Continue" : "Start")
                        .foregroundStyle(ReelFinTheme.onboardingButtonText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .accessibilityIdentifier("login_primary_cta")

            case .serverEntry:
                Color.clear.frame(height: 1)

            case .credentialsSheet, .submitting:
                Button {
                    submitCredentials()
                } label: {
                    Group {
                        if phase == .submitting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(ReelFinTheme.onboardingButtonText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        } else {
                            Text("Sign in")
                                .foregroundStyle(ReelFinTheme.onboardingButtonText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        }
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canSubmitCredentials || phase == .submitting)

            case .success:
                EmptyView()
            }
        }
        .padding(.bottom, safeAreaInsets.bottom + 8)
    }

    private var successState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(ReelFinTheme.onboardingMint)
                .frame(width: 84, height: 84)
                .background(
                    Circle()
                        .fill(.white.opacity(0.06))
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .scaleEffect(successBounce ? 1 : 0.82)

            Text("Done")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityIdentifier("login_success_title")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .smooth(duration: 0.32, extraBounce: 0.08)) {
                successBounce = true
            }
        }
    }

    private func backdrop(size: CGSize) -> some View {
        let state = backdropState
        let orbDiameter = min(size.width * state.diameterScale, state.maximumDiameter)

        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.02, blue: 0.03),
                    Color(red: 0.03, green: 0.04, blue: 0.07),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: paletteColors,
                        center: .center,
                        startRadius: 12,
                        endRadius: orbDiameter * 0.5
                    )
                )
                .frame(width: orbDiameter, height: orbDiameter * state.aspectRatio)
                .blur(radius: state.blurRadius)
                .opacity(state.opacity)
                .scaleEffect(state.scale)
                .offset(
                    x: size.width * state.xOffsetRatio,
                    y: size.height * state.yOffsetRatio
                )
                .drawingGroup()

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.24),
                    Color.black.opacity(0.56),
                    Color.black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var paletteColors: [Color] {
        switch phase {
        case .landing, .serverEntry:
            return [
                ReelFinTheme.onboardingCyan.opacity(0.98),
                ReelFinTheme.onboardingBlue.opacity(1.0)
            ]
        case .credentialsSheet, .submitting:
            return [
                ReelFinTheme.onboardingOrange.opacity(0.96),
                ReelFinTheme.onboardingViolet.opacity(0.90)
            ]
        case .success:
            return [
                ReelFinTheme.onboardingMint.opacity(0.72),
                ReelFinTheme.onboardingBlue.opacity(0.48)
            ]
        }
    }

    private func stepIcon(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 52, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }

    private func feedbackRow(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .capsuleSurface()
    }

    private var serverHost: String {
        URL(string: viewModel.serverURLText.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "Jellyfin account"
    }

    private var chromeTitle: String {
        switch phase {
        case .landing:
            return "Setup"
        case .serverEntry:
            return "Jellyfin server"
        case .credentialsSheet, .submitting:
            return "Jellyfin account"
        case .success:
            return ""
        }
    }

    private func continueFromServer() {
        guard !viewModel.isTestingConnection else {
            return
        }

        focusedField = nil

        Task {
            let isValid = await viewModel.testConnection()
            guard isValid else { return }

            await MainActor.run {
                transition(to: .credentialsSheet)
                focus(.username)
            }
        }
    }

    private func submitCredentials() {
        guard phase != .submitting, viewModel.canSubmitCredentials else {
            return
        }

        focusedField = nil
        viewModel.clearAuthError()
        transition(to: .submitting)

        Task {
            if let session = await viewModel.login() {
                await presentSuccess(for: session)
            } else {
                await MainActor.run {
                    transition(to: .credentialsSheet)
                    focus(.password)
                }
            }
        }
    }

    private func presentSuccess(for session: UserSession) async {
        await MainActor.run {
            successBounce = false
            transition(to: .success)
        }

        try? await Task.sleep(nanoseconds: reduceMotion ? 180_000_000 : 420_000_000)

        await MainActor.run {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onLogin(session)
        }
    }

    private func handleBack() {
        switch phase {
        case .landing:
            break
        case .serverEntry:
            transition(to: .landing)
        case .credentialsSheet, .submitting:
            viewModel.clearAuthError()
            transition(to: .serverEntry)
        case .success:
            break
        }
    }

    private func transition(to newPhase: OnboardingPhase) {
        withAnimation(stageAnimation) {
            phase = newPhase
        }
    }

    private func focus(_ field: FocusField) {
        guard !reduceMotion else {
            focusedField = field
            return
        }

        Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            await MainActor.run {
                focusedField = field
            }
        }
    }

    private var backdropState: BackdropState {
        switch phase {
        case .landing:
            return BackdropState(
                diameterScale: 0.74,
                maximumDiameter: 440,
                aspectRatio: 1.04,
                blurRadius: 54,
                scale: 1,
                opacity: 0.96,
                xOffsetRatio: 0.02,
                yOffsetRatio: -0.12
            )
        case .serverEntry:
            return BackdropState(
                diameterScale: 0.68,
                maximumDiameter: 410,
                aspectRatio: 1.08,
                blurRadius: 52,
                scale: 0.96,
                opacity: 0.9,
                xOffsetRatio: 0.08,
                yOffsetRatio: -0.08
            )
        case .credentialsSheet, .submitting:
            return BackdropState(
                diameterScale: 0.78,
                maximumDiameter: 470,
                aspectRatio: 1.12,
                blurRadius: 58,
                scale: 1.03,
                opacity: 0.92,
                xOffsetRatio: 0.06,
                yOffsetRatio: -0.18
            )
        case .success:
            return BackdropState(
                diameterScale: 0.62,
                maximumDiameter: 360,
                aspectRatio: 1,
                blurRadius: 44,
                scale: 0.88,
                opacity: 0.7,
                xOffsetRatio: 0,
                yOffsetRatio: -0.22
            )
        }
    }

    private func layoutMetrics(for size: CGSize) -> LoginMetrics {
        let compact = size.width < 760 || horizontalSizeClass != .regular

        if compact {
            return LoginMetrics(
                contentWidth: min(size.width - 40, 420),
                horizontalPadding: 20,
                topPadding: 8,
                topSpacer: max(40, size.height * 0.20),
                bottomSpacer: 28,
                titleSize: 36,
                subtitleSize: 18
            )
        }

        return LoginMetrics(
            contentWidth: min(size.width - 120, 520),
            horizontalPadding: 28,
            topPadding: 18,
            topSpacer: max(60, size.height * 0.18),
            bottomSpacer: 36,
            titleSize: 46,
            subtitleSize: 20
        )
    }
}

private struct BackdropState {
    let diameterScale: CGFloat
    let maximumDiameter: CGFloat
    let aspectRatio: CGFloat
    let blurRadius: CGFloat
    let scale: CGFloat
    let opacity: CGFloat
    let xOffsetRatio: CGFloat
    let yOffsetRatio: CGFloat
}

private enum OnboardingPhase {
    case landing
    case serverEntry
    case credentialsSheet
    case submitting
    case success
}

private enum FocusField {
    case serverURL
    case username
    case password
}

private struct LoginMetrics {
    let contentWidth: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let topSpacer: CGFloat
    let bottomSpacer: CGFloat
    let titleSize: CGFloat
    let subtitleSize: CGFloat
}

private extension View {
    func fieldSurface() -> some View {
        self
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.06))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }

    func capsuleSurface() -> some View {
        self
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.05))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule(style: .continuous)
                    .fill(ReelFinTheme.onboardingButtonTint)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.12 : 0.2),
                radius: configuration.isPressed ? 10 : 18,
                x: 0,
                y: configuration.isPressed ? 5 : 10
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(
                reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.16, extraBounce: 0),
                value: configuration.isPressed
            )
    }
}

private struct OnboardingIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(ReelFinTheme.onboardingQuietButtonTint)
            )
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(
                reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.14, extraBounce: 0),
                value: configuration.isPressed
            )
    }
}

private struct OnboardingProminentIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(ReelFinTheme.onboardingButtonTint)
            )
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.08 : 0.16),
                radius: configuration.isPressed ? 8 : 14,
                x: 0,
                y: configuration.isPressed ? 4 : 8
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(
                reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.14, extraBounce: 0),
                value: configuration.isPressed
            )
    }
}
