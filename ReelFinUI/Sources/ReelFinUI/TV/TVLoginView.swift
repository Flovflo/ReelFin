#if os(tvOS)
import Shared
import SwiftUI

/// Apple TV login view — optimized for Siri Remote focus navigation.
/// Large tap targets, focus-first design, no keyboard tricks required.
public struct TVLoginView: View {
    @StateObject private var viewModel: LoginViewModel
    @FocusState private var focusedField: TVFocusField?
    @State private var phase: TVOnboardingPhase = .landing
    @State private var contentVisible = false
    @State private var successVisible = false

    private let onLogin: (UserSession) -> Void

    public init(dependencies: ReelFinDependencies, onLogin: @escaping (UserSession) -> Void) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(dependencies: dependencies))
        self.onLogin = onLogin
    }

    public var body: some View {
        ZStack {
            backgroundView
            contentStack
        }
        .ignoresSafeArea()
        .opacity(contentVisible ? 1 : 0)
        .onAppear {
            withAnimation(.smooth(duration: 0.4)) {
                contentVisible = true
            }
        }
        .onChange(of: viewModel.serverURLText) { _, _ in
            viewModel.serverURLDidChange()
        }
    }

    // MARK: - Background

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.10),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(phaseTint.opacity(0.25))
                .frame(width: 600, height: 600)
                .blur(radius: 120)
                .offset(x: -300, y: -200)
                .animation(.smooth(duration: 0.6), value: phase)
        }
        .ignoresSafeArea()
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

    // MARK: - Content

    private var contentStack: some View {
        HStack(spacing: 0) {
            // Left branding panel
            brandingPanel
                .frame(maxWidth: .infinity)

            // Right stage panel
            stagePanel
                .frame(width: 680)
                .padding(.trailing, 120)
        }
        .padding(.leading, 120)
    }

    private var brandingPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            Text("ReelFin")
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("Your Jellyfin, beautifully on Apple TV.")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stagePanel: some View {
        switch phase {
        case .landing:
            landingStage
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case .serverEntry:
            serverStage
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case .credentials, .submitting:
            credentialsStage
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case .success:
            successStage
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    // MARK: - Landing

    private var landingStage: some View {
        TVStageCard {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect your server")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Simple setup, native feel.")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                if viewModel.hasSavedServer {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ReelFinTheme.onboardingMint)
                        Text("Saved server ready")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.08), in: Capsule())
                }

                TVPrimaryButton(
                    title: viewModel.hasSavedServer ? "Continue" : "Start setup",
                    isLoading: false
                ) {
                    transitionTo(.serverEntry)
                }
                .focused($focusedField, equals: .primary)
            }
        }
        .onAppear {
            focusedField = .primary
        }
    }

    // MARK: - Server Entry

    private var serverStage: some View {
        TVStageCard {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Server URL")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Enter your Jellyfin server address.")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                TextField("https://server.tld", text: $viewModel.serverURLText)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .serverURL)
                    .tvFieldStyle()

                if viewModel.isTestingConnection {
                    tvFeedbackRow(text: "Checking server...", tint: .white.opacity(0.7))
                } else if let serverError = viewModel.serverErrorMessage {
                    tvFeedbackRow(text: serverError, tint: .red.opacity(0.9))
                } else if let serverMessage = viewModel.serverMessage {
                    tvFeedbackRow(text: serverMessage, tint: .white.opacity(0.7))
                }

                HStack(spacing: 16) {
                    TVSecondaryButton(title: "Back") {
                        transitionTo(.landing)
                    }
                    .focused($focusedField, equals: .back)

                    TVPrimaryButton(
                        title: "Continue",
                        isLoading: viewModel.isTestingConnection
                    ) {
                        continueFromServer()
                    }
                    .focused($focusedField, equals: .primary)
                    .disabled(!viewModel.canAdvanceFromServer)
                }
            }
        }
        .onAppear {
            focusedField = .serverURL
        }
    }

    // MARK: - Credentials

    private var credentialsStage: some View {
        TVStageCard {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sign in")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(serverHost)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                VStack(spacing: 14) {
                    TextField("Username", text: $viewModel.username)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .username)
                        .tvFieldStyle()

                    SecureField("Password", text: $viewModel.password)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .password)
                        .tvFieldStyle()
                }

                if phase == .submitting {
                    tvFeedbackRow(text: "Signing in...", tint: .white.opacity(0.7))
                } else if let authError = viewModel.authErrorMessage {
                    tvFeedbackRow(text: authError, tint: .red.opacity(0.9))
                }

                HStack(spacing: 16) {
                    TVSecondaryButton(title: "Back") {
                        viewModel.clearAuthError()
                        transitionTo(.serverEntry)
                    }
                    .focused($focusedField, equals: .back)

                    TVPrimaryButton(
                        title: "Sign in",
                        isLoading: phase == .submitting
                    ) {
                        submitCredentials()
                    }
                    .focused($focusedField, equals: .primary)
                    .disabled(!viewModel.canSubmitCredentials || phase == .submitting)
                }
            }
        }
        .onAppear {
            focusedField = .username
        }
    }

    // MARK: - Success

    private var successStage: some View {
        TVStageCard {
            VStack(alignment: .center, spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80, weight: .medium))
                    .foregroundStyle(ReelFinTheme.onboardingMint)
                    .scaleEffect(successVisible ? 1.0 : 0.7)
                    .opacity(successVisible ? 1 : 0)

                Text("Connected")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(successVisible ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                successVisible = true
            }
        }
    }

    // MARK: - Helpers

    private var serverHost: String {
        URL(string: viewModel.serverURLText.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "Jellyfin account"
    }

    private func tvFeedbackRow(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func transitionTo(_ newPhase: TVOnboardingPhase) {
        withAnimation(.smooth(duration: 0.32)) {
            phase = newPhase
        }
    }

    private func continueFromServer() {
        guard !viewModel.isTestingConnection else { return }
        focusedField = nil
        Task {
            let isValid = await viewModel.testConnection()
            guard isValid else { return }
            await MainActor.run {
                transitionTo(.credentials)
                focusedField = .username
            }
        }
    }

    private func submitCredentials() {
        guard phase != .submitting, viewModel.canSubmitCredentials else { return }
        focusedField = nil
        viewModel.clearAuthError()
        transitionTo(.submitting)
        Task {
            if let session = await viewModel.login() {
                await MainActor.run {
                    successVisible = false
                    transitionTo(.success)
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run {
                    onLogin(session)
                }
            } else {
                await MainActor.run {
                    transitionTo(.credentials)
                    focusedField = .password
                }
            }
        }
    }
}

// MARK: - Supporting Types

private enum TVOnboardingPhase {
    case landing, serverEntry, credentials, submitting, success
}

private enum TVFocusField {
    case primary, serverURL, username, password, back
}

// MARK: - TV Stage Card

private struct TVStageCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    }
            )
    }
}

// MARK: - TV Buttons

private struct TVPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(title)
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .frame(height: 66)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(color: .white.opacity(isFocused ? 0.3 : 0), radius: 20)
            .animation(.smooth(duration: 0.2), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .disabled(isLoading)
    }
}

private struct TVSecondaryButton: View {
    let title: String
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(height: 66)
                .padding(.horizontal, 32)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(isFocused ? 0.18 : 0.10))
                )
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.smooth(duration: 0.2), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}

// MARK: - TV Field Style

private extension View {
    func tvFieldStyle() -> some View {
        self
            .padding(.horizontal, 22)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
            )
    }
}

// MARK: - Previews

#Preview("TV Login - Landing") {
    TVLoginView(dependencies: ReelFinPreviewFactory.dependencies(authenticated: false)) { _ in }
}
#endif
