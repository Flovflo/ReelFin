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
    @State private var successVisible = false

    init(dependencies: ReelFinDependencies, onLogin: @escaping (UserSession) -> Void) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(dependencies: dependencies))
        self.onLogin = onLogin
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(for: proxy.size)

            ZStack {
                backgroundView(size: proxy.size)

                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, proxy.safeAreaInsets.top + metrics.topPadding)

                    Spacer(minLength: metrics.topSpacer)

                    ZStack {
                        stageContent(metrics: metrics)
                    }
                    .frame(maxWidth: metrics.contentWidth)

                    Spacer()
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 10)
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
        reduceMotion ? .easeInOut(duration: 0.14) : .smooth(duration: 0.28, extraBounce: 0.01)
    }

    private var entranceAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.26, extraBounce: 0)
    }

    private var stageTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.985))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Jellyfin")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

            Spacer()

            if phase != .landing {
                Button {
                    handleBack()
                } label: {
                    Image(systemName: phase == .serverEntry ? "xmark" : "chevron.backward")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(NativeCircleButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func stageContent(metrics: LoginMetrics) -> some View {
        switch phase {
        case .landing:
            landingCard(metrics: metrics)
                .transition(stageTransition)
        case .serverEntry:
            serverCard(metrics: metrics)
                .transition(stageTransition)
        case .credentials, .submitting:
            credentialsCard(metrics: metrics)
                .transition(stageTransition)
        case .success:
            successCard(metrics: metrics)
                .transition(stageTransition)
        }
    }

    private func landingCard(metrics: LoginMetrics) -> some View {
        stageCard {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect your server")
                        .font(.system(size: metrics.titleSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("login_landing_title")

                    Text("Simple setup, native feel.")
                        .font(.system(size: metrics.subtitleSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                if viewModel.hasSavedServer {
                    Text("Saved server ready")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .capsuleSurface()
                }

                Button {
                    transition(to: .serverEntry)
                    focus(.serverURL)
                } label: {
                    Text(viewModel.hasSavedServer ? "Continue" : "Start setup")
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(NativePrimaryButtonStyle())
                .accessibilityIdentifier("login_primary_cta")
            }
        }
    }

    private func serverCard(metrics: LoginMetrics) -> some View {
        stageCard {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Server URL")
                        .font(.system(size: metrics.titleSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Enter your Jellyfin address.")
                        .font(.system(size: metrics.subtitleSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

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
                    .fieldSurface()

                if viewModel.isTestingConnection {
                    feedbackRow(text: "Checking server", tint: .white.opacity(0.72))
                } else if let serverError = viewModel.serverErrorMessage {
                    feedbackRow(text: serverError, tint: .red.opacity(0.92))
                } else if let serverMessage = viewModel.serverMessage {
                    feedbackRow(text: serverMessage, tint: .white.opacity(0.72))
                }

                Button {
                    continueFromServer()
                } label: {
                    Group {
                        if viewModel.isTestingConnection {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        } else {
                            Text("Continue")
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        }
                    }
                }
                .buttonStyle(NativePrimaryButtonStyle())
                .disabled(!viewModel.canAdvanceFromServer)
                .accessibilityIdentifier("login_server_continue")
            }
        }
    }

    private func credentialsCard(metrics: LoginMetrics) -> some View {
        stageCard {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sign in")
                        .font(.system(size: metrics.titleSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(serverHost)
                        .font(.system(size: metrics.subtitleSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

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

                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            submitCredentials()
                        }
                        .fieldSurface()
                }
                .accessibilityIdentifier("login_credentials_sheet")

                if phase == .submitting {
                    feedbackRow(text: "Signing in", tint: .white.opacity(0.72))
                } else if let authError = viewModel.authErrorMessage {
                    feedbackRow(text: authError, tint: .red.opacity(0.92))
                }

                Button {
                    submitCredentials()
                } label: {
                    Group {
                        if phase == .submitting {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        } else {
                            Text("Sign in")
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        }
                    }
                }
                .buttonStyle(NativePrimaryButtonStyle())
                .disabled(!viewModel.canSubmitCredentials || phase == .submitting)
            }
        }
    }

    private func successCard(metrics: LoginMetrics) -> some View {
        stageCard {
            VStack(alignment: .center, spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.white)
                    .opacity(successVisible ? 1 : 0.65)
                    .scaleEffect(successVisible ? 1 : 0.9)

                Text("Connected")
                    .font(.system(size: metrics.titleSize - 4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("login_success_title")
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            withAnimation(entranceAnimation) {
                successVisible = true
            }
        }
    }

    private func backgroundView(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.02, green: 0.03, blue: 0.05),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(phaseTint.opacity(0.34))
                .frame(width: min(size.width * 0.72, 340), height: min(size.width * 0.72, 340))
                .blur(radius: 60)
                .offset(y: -size.height * 0.2)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.03),
                    Color.clear,
                    Color.black.opacity(0.44)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .animation(stageAnimation, value: phase)
    }

    private var phaseTint: Color {
        switch phase {
        case .landing, .serverEntry:
            return ReelFinTheme.onboardingBlue
        case .credentials, .submitting:
            return ReelFinTheme.onboardingViolet
        case .success:
            return ReelFinTheme.onboardingMint
        }
    }

    private var serverHost: String {
        URL(string: viewModel.serverURLText.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "Jellyfin account"
    }

    private func stageCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nativeStageSurface()
    }

    private func feedbackRow(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .capsuleSurface()
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
                transition(to: .credentials)
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
                    transition(to: .credentials)
                    focus(.password)
                }
            }
        }
    }

    private func presentSuccess(for session: UserSession) async {
        await MainActor.run {
            successVisible = false
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
        case .landing:
            break
        case .serverEntry:
            transition(to: .landing)
        case .credentials, .submitting:
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
            try? await Task.sleep(nanoseconds: 120_000_000)
            await MainActor.run {
                focusedField = field
            }
        }
    }

    private func layoutMetrics(for size: CGSize) -> LoginMetrics {
        let compact = size.width < 760 || horizontalSizeClass != .regular

        if compact {
            return LoginMetrics(
                contentWidth: min(size.width - 32, 420),
                horizontalPadding: 16,
                topPadding: 8,
                topSpacer: max(36, size.height * 0.18),
                titleSize: 34,
                subtitleSize: 18
            )
        }

        return LoginMetrics(
            contentWidth: min(size.width - 96, 500),
            horizontalPadding: 24,
            topPadding: 18,
            topSpacer: max(52, size.height * 0.16),
            titleSize: 42,
            subtitleSize: 20
        )
    }
}

private enum OnboardingPhase {
    case landing
    case serverEntry
    case credentials
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
    let titleSize: CGFloat
    let subtitleSize: CGFloat
}

private extension View {
    @ViewBuilder
    func nativeStageSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

        if #available(iOS 26.0, *) {
            self
                .background {
                    Color.clear
                        .glassEffect(.regular, in: .rect(cornerRadius: 30))
                }
                .overlay {
                    shape.stroke(.white.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
        }
    }

    func fieldSurface() -> some View {
        self
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.08))
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
                    .fill(.white.opacity(0.06))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct NativePrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                configuration.label
                    .foregroundStyle(.white)
                    .glassEffect(.regular.interactive(), in: .capsule)
            } else {
                configuration.label
                    .foregroundStyle(.white)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.14))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }
            }
        }
        .scaleEffect(configuration.isPressed ? 0.985 : 1)
        .opacity(configuration.isPressed ? 0.96 : 1)
        .animation(
            reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.14, extraBounce: 0),
            value: configuration.isPressed
        )
    }
}

private struct NativeCircleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                configuration.label
                    .glassEffect(.regular.interactive(), in: .circle)
            } else {
                configuration.label
                    .background(
                        Circle()
                            .fill(.white.opacity(0.10))
                    )
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }
            }
        }
        .scaleEffect(configuration.isPressed ? 0.96 : 1)
        .animation(
            reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.14, extraBounce: 0),
            value: configuration.isPressed
        )
    }
}
