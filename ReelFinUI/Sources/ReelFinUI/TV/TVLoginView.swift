#if os(tvOS)
import Shared
import SwiftUI

public struct TVLoginView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var loginVM: LoginViewModel
    @StateObject private var quickConnectVM: QuickConnectViewModel
    @FocusState private var focus: TVLoginFocus?
    @State private var phase: TVLoginPhase = .landing
    @State private var signInPath: TVLoginSignInPath = .quickConnect
    @State private var contentVisible = false
    @State private var successVisible = false

    private let imagePipeline: any ImagePipelineProtocol
    private let onLogin: (UserSession) -> Void

    public init(dependencies: ReelFinDependencies, onLogin: @escaping (UserSession) -> Void) {
        _loginVM = StateObject(wrappedValue: LoginViewModel(dependencies: dependencies))
        _quickConnectVM = StateObject(wrappedValue: QuickConnectViewModel(dependencies: dependencies))
        imagePipeline = dependencies.imagePipeline
        self.onLogin = onLogin
    }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = TVLoginLayoutMetrics(size: proxy.size, phase: phase)

            ZStack(alignment: .topLeading) {
                TVLoginBackgroundView(accent: heroAccent, secondaryAccent: heroGlow)

                TVLoginHeroView(
                    imagePipeline: imagePipeline,
                    accent: heroAccent,
                    secondaryAccent: heroGlow,
                    phase: phase
                )
                .frame(width: metrics.heroWidth, height: metrics.heroHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 78)

                VStack(spacing: 0) {
                    TVLoginBrandHeader()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, metrics.topPadding)
                        .padding(.leading, metrics.outerHorizontalPadding)

                    Spacer(minLength: 0)

                    TVLoginStageSurface(metrics: metrics) {
                        stageContent(metrics: metrics)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, metrics.bottomPadding)
                }
            }
            .opacity(contentVisible ? 1 : 0)
            .offset(y: contentVisible ? 0 : 12)
        }
        .preferredColorScheme(.dark)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear(perform: handleAppear)
        .onChange(of: loginVM.serverURLText) { _, _ in
            loginVM.serverURLDidChange()
        }
    }

    private var stageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.36, extraBounce: 0.02)
    }

    private var entranceAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .smooth(duration: 0.28, extraBounce: 0)
    }

    private var stageTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.985))
    }

    @ViewBuilder
    private func stageContent(metrics: TVLoginLayoutMetrics) -> some View {
        switch phase {
        case .landing:
            TVLandingStageView(
                buttonWidth: metrics.landingButtonWidth,
                hasSavedServer: loginVM.hasSavedServer,
                savedServerText: loginVM.serverURLText,
                onQuickConnect: beginQuickConnectFlow,
                onPassword: beginPasswordFlow,
                onChooseServer: {
                    go(.server)
                    focus = .textA
                },
                focus: $focus
            )
            .transition(stageTransition)
        case .server:
            TVServerStageView(
                serverURLText: $loginVM.serverURLText,
                signInPath: signInPath,
                isTestingConnection: loginVM.isTestingConnection,
                canContinue: loginVM.canAdvanceFromServer,
                serverMessage: loginVM.serverMessage,
                serverErrorMessage: loginVM.serverErrorMessage,
                onBack: { go(.landing) },
                onContinue: continueFromServer,
                onTogglePath: toggleSignInPath,
                focus: $focus
            )
            .transition(stageTransition)
        case .credentials:
            TVCredentialsStageView(
                username: $loginVM.username,
                password: $loginVM.password,
                serverHost: serverHost,
                authErrorMessage: loginVM.authErrorMessage,
                canSubmit: loginVM.canSubmitCredentials,
                onBack: {
                    loginVM.clearAuthError()
                    go(.server)
                },
                onSubmit: submitCredentials,
                onQuickConnect: beginQuickConnectFlow,
                focus: $focus
            )
            .transition(stageTransition)
        case .submitting:
            TVSubmittingStageView(serverHost: serverHost)
                .transition(stageTransition)
        case .quickConnect:
            TVQuickConnectStageView(
                state: quickConnectVM.state,
                onUsePassword: {
                    quickConnectVM.cancel()
                    signInPath = .credentials
                    go(.credentials)
                },
                focus: $focus
            )
            .transition(stageTransition)
        case .success:
            TVSuccessStageView(animateIn: $successVisible)
                .onAppear {
                    withAnimation(.spring(duration: 0.55, bounce: 0.28)) {
                        successVisible = true
                    }
                }
                .transition(stageTransition)
        }
    }

    private var heroAccent: Color {
        switch phase {
        case .landing, .server:
            return Color(red: 0.34, green: 0.52, blue: 0.96)
        case .credentials, .submitting:
            return Color(red: 0.48, green: 0.60, blue: 0.94)
        case .quickConnect:
            return Color(red: 0.28, green: 0.74, blue: 0.90)
        case .success:
            return Color(red: 0.28, green: 0.84, blue: 0.66)
        }
    }

    private var heroGlow: Color {
        switch phase {
        case .landing:
            return Color.white.opacity(0.86)
        case .server:
            return signInPath == .quickConnect
                ? Color(red: 0.42, green: 0.86, blue: 0.94)
                : Color(red: 0.62, green: 0.64, blue: 0.98)
        case .credentials, .submitting:
            return Color(red: 0.70, green: 0.72, blue: 0.98)
        case .quickConnect:
            return Color(red: 0.56, green: 0.92, blue: 0.92)
        case .success:
            return Color.white.opacity(0.82)
        }
    }

    private var serverHost: String {
        URL(string: loginVM.serverURLText.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "Jellyfin"
    }

    private func handleAppear() {
        quickConnectVM.onAuthenticated = { session in
            handleSuccess(session)
        }

        applyDebugOverridesIfNeeded()

        guard !contentVisible else { return }

        withAnimation(entranceAnimation) {
            contentVisible = true
        }

        if focus == nil {
            focus = .primary
        }
    }

    private func applyDebugOverridesIfNeeded() {
        guard let overridePhase = TVLoginDebugOptions.phase else { return }

        signInPath = TVLoginDebugOptions.signInPath ?? signInPath
        phase = overridePhase

        switch overridePhase {
        case .landing:
            focus = .primary
        case .server:
            focus = .textA
        case .credentials:
            focus = .textA
        case .quickConnect:
            focus = .tertiary
        case .submitting, .success:
            focus = nil
        }
    }

    private func go(_ newPhase: TVLoginPhase) {
        withAnimation(stageAnimation) {
            phase = newPhase
        }

        if newPhase != .success {
            successVisible = false
        }
    }

    private func beginQuickConnectFlow() {
        signInPath = .quickConnect

        guard loginVM.hasSavedServer else {
            go(.server)
            focus = .textA
            return
        }

        continueToQuickConnect()
    }

    private func beginPasswordFlow() {
        signInPath = .credentials

        if loginVM.hasSavedServer {
            go(.credentials)
        } else {
            go(.server)
        }

        focus = .textA
    }

    private func continueFromServer() {
        switch signInPath {
        case .quickConnect:
            continueToQuickConnect()
        case .credentials:
            continueToCredentials()
        }
    }

    private func toggleSignInPath() {
        signInPath = signInPath.alternate
        focus = .primary
    }

    private func continueToCredentials() {
        guard !loginVM.isTestingConnection else { return }
        focus = nil

        Task {
            let ok = await loginVM.testConnection()
            guard ok else { return }
            await MainActor.run {
                go(.credentials)
                focus = .textA
            }
        }
    }

    private func continueToQuickConnect() {
        guard !loginVM.isTestingConnection else { return }
        focus = nil

        Task {
            let ok = await loginVM.testConnection()
            guard ok else {
                await MainActor.run {
                    if phase != .server {
                        go(.server)
                        focus = .textA
                    }
                }
                return
            }

            await MainActor.run {
                launchQuickConnect(url: loginVM.validatedServerURL)
            }
        }
    }

    private func launchQuickConnect(url: URL?) {
        guard let url else {
            go(.server)
            focus = .textA
            return
        }

        quickConnectVM.cancel()

        Task {
            await quickConnectVM.initiate(serverURL: url)
        }

        go(.quickConnect)
        focus = .tertiary
    }

    private func submitCredentials() {
        guard loginVM.canSubmitCredentials, phase != .submitting else { return }
        focus = nil
        loginVM.clearAuthError()
        go(.submitting)

        Task {
            if let session = await loginVM.login() {
                handleSuccess(session)
            } else {
                await MainActor.run {
                    go(.credentials)
                    focus = .textB
                }
            }
        }
    }

    private func handleSuccess(_ session: UserSession) {
        Task { @MainActor in
            go(.success)
            try? await Task.sleep(nanoseconds: 900_000_000)
            onLogin(session)
        }
    }
}

private enum TVLoginDebugOptions {
    static var phase: TVLoginPhase? {
        let arguments = ProcessInfo.processInfo.arguments

        guard let flagIndex = arguments.firstIndex(of: "-reelfin-tv-login-phase") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        switch arguments[valueIndex] {
        case "landing":
            return .landing
        case "server":
            return .server
        case "credentials":
            return .credentials
        case "submitting":
            return .submitting
        case "quickConnect":
            return .quickConnect
        case "success":
            return .success
        default:
            return nil
        }
    }

    static var signInPath: TVLoginSignInPath? {
        let arguments = ProcessInfo.processInfo.arguments

        guard let flagIndex = arguments.firstIndex(of: "-reelfin-tv-login-path") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        switch arguments[valueIndex] {
        case "quickConnect":
            return .quickConnect
        case "credentials":
            return .credentials
        default:
            return nil
        }
    }
}

#Preview("TV Login") {
    TVLoginView(dependencies: ReelFinPreviewFactory.dependencies(authenticated: false)) { _ in }
}
#endif
