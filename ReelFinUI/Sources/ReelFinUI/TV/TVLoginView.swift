#if os(tvOS)
import Shared
import SwiftUI

public struct TVLoginView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var loginVM: LoginViewModel
    @StateObject private var quickConnectVM: QuickConnectViewModel
    @FocusState private var focus: TVLoginFocus?
    @Namespace private var loginFocusScope
    @State private var phase: TVLoginPhase
    @State private var signInPath: TVLoginSignInPath
    @State private var quickConnectOrigin: TVLoginPhase
    @State private var navigationGeneration = 0
    @State private var navigationTask: Task<Void, Never>?
    @State private var contentVisible = false
    @State private var successVisible = false

    private let imagePipeline: any ImagePipelineProtocol
    private let onLogin: (UserSession) -> Void

    public init(dependencies: ReelFinDependencies, onLogin: @escaping (UserSession) -> Void) {
        let initialPhase = TVLoginDebugOptions.phase ?? .landing
        let initialPath = TVLoginDebugOptions.signInPath ?? .quickConnect
        let loginViewModel = LoginViewModel(dependencies: dependencies)

        if let username = TVLoginDebugOptions.username {
            loginViewModel.username = username
        }
        if let password = TVLoginDebugOptions.password {
            loginViewModel.password = password
        }

        _loginVM = StateObject(wrappedValue: loginViewModel)
        _quickConnectVM = StateObject(wrappedValue: QuickConnectViewModel(dependencies: dependencies))
        _phase = State(initialValue: initialPhase)
        _signInPath = State(initialValue: initialPath)
        _quickConnectOrigin = State(initialValue: TVLoginDebugOptions.quickConnectOrigin ?? .landing)
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
                    .id(phase)
                    .focusScope(loginFocusScope)
                    .tvLoginDefaultFocus($focus, phase: phase)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, metrics.bottomPadding)
                }
            }
            .opacity(contentVisible ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (contentVisible ? 0 : 12))
        }
        .preferredColorScheme(.dark)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear(perform: handleAppear)
        .onChange(of: loginVM.serverURLText) { _, _ in
            loginVM.serverURLDidChange()
        }
        .onExitCommand(perform: navigateBack)
        .onDisappear(perform: cancelAsyncNavigation)
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
                onChooseServer: { go(.server) },
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
                onBack: navigateBack,
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
                onBack: navigateBack,
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
                    cancelAsyncNavigation()
                    signInPath = .credentials
                    go(.credentials)
                },
                focus: $focus
            )
            .transition(stageTransition)
        case .success:
            TVSuccessStageView(animateIn: $successVisible)
                .onAppear {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: 0.55, bounce: 0.28)) {
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
            guard phase == .quickConnect else { return }
            handleSuccess(session)
        }

        guard !contentVisible else { return }

        withAnimation(entranceAnimation) {
            contentVisible = true
        }

        focus = TVLoginNavigationPolicy.preferredFocus(for: phase)
    }

    private func go(_ newPhase: TVLoginPhase) {
        focus = nil

        if newPhase != .success {
            successVisible = false
        }

        withAnimation(stageAnimation) {
            phase = newPhase
        }

        focus = TVLoginNavigationPolicy.preferredFocus(for: newPhase)
    }

    private func beginQuickConnectFlow() {
        let origin = phase
        signInPath = .quickConnect

        guard loginVM.hasSavedServer else {
            go(.server)
            return
        }

        continueToQuickConnect(origin: origin)
    }

    private func beginPasswordFlow() {
        cancelAsyncNavigation()
        signInPath = .credentials

        if loginVM.hasSavedServer {
            go(.credentials)
        } else {
            go(.server)
        }
    }

    private func continueFromServer() {
        switch signInPath {
        case .quickConnect:
            continueToQuickConnect(origin: phase)
        case .credentials:
            continueToCredentials()
        }
    }

    private func toggleSignInPath() {
        guard !loginVM.isTestingConnection else { return }
        signInPath = signInPath.alternate
        focus = .serverPrimary
    }

    private func continueToCredentials() {
        guard !loginVM.isTestingConnection else { return }
        focus = nil
        let generation = beginAsyncNavigation()

        navigationTask = Task { @MainActor in
            let ok = await loginVM.testConnection()
            guard navigationGeneration == generation, !Task.isCancelled else { return }

            finishAsyncNavigation(generation: generation)
            if ok {
                go(.credentials)
            } else {
                go(.server)
            }
        }
    }

    private func continueToQuickConnect(origin: TVLoginPhase) {
        guard !loginVM.isTestingConnection else { return }
        quickConnectOrigin = origin
        focus = nil
        let generation = beginAsyncNavigation()

        navigationTask = Task { @MainActor in
            let ok = await loginVM.testConnection()
            guard navigationGeneration == generation, !Task.isCancelled else { return }

            guard ok, let url = loginVM.validatedServerURL else {
                finishAsyncNavigation(generation: generation)
                go(.server)
                return
            }

            go(.quickConnect)
            await quickConnectVM.initiate(serverURL: url)

            guard navigationGeneration == generation,
                  !Task.isCancelled,
                  phase == .quickConnect else {
                return
            }

            finishAsyncNavigation(generation: generation)
        }
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
                    focus = .credentialsPassword
                }
            }
        }
    }

    private func navigateBack() {
        let source = phase
        let destination = TVLoginNavigationPolicy.backDestination(
            from: source,
            quickConnectOrigin: quickConnectOrigin
        )

        if navigationTask != nil || source == .quickConnect {
            cancelAsyncNavigation()
        }

        guard let destination else {
            focus = TVLoginNavigationPolicy.preferredFocus(for: source)
            return
        }

        if source == .credentials {
            loginVM.clearAuthError()
        }

        if source == .quickConnect, destination == .credentials {
            signInPath = .credentials
        }

        go(destination)
    }

    private func beginAsyncNavigation() -> Int {
        navigationTask?.cancel()
        navigationTask = nil
        loginVM.cancelConnectionTest()
        quickConnectVM.cancel()
        navigationGeneration &+= 1
        return navigationGeneration
    }

    private func cancelAsyncNavigation() {
        navigationGeneration &+= 1
        navigationTask?.cancel()
        navigationTask = nil
        loginVM.cancelConnectionTest()
        quickConnectVM.cancel()
    }

    private func finishAsyncNavigation(generation: Int) {
        guard navigationGeneration == generation else { return }
        navigationTask = nil
    }

    private func handleSuccess(_ session: UserSession) {
        cancelAsyncNavigation()
        Task { @MainActor in
            go(.success)
            try? await Task.sleep(nanoseconds: 900_000_000)
            onLogin(session)
        }
    }
}

private enum TVLoginDebugOptions {
    static var username: String? {
        argumentValue(after: "-reelfin-tv-login-username")
    }

    static var password: String? {
        argumentValue(after: "-reelfin-tv-login-password")
    }

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

    static var quickConnectOrigin: TVLoginPhase? {
        let arguments = ProcessInfo.processInfo.arguments

        guard let flagIndex = arguments.firstIndex(of: "-reelfin-tv-login-quick-connect-origin") else {
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
        default:
            return nil
        }
    }

    private static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: flag) else { return nil }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return arguments[valueIndex]
    }
}

private extension View {
    @ViewBuilder
    func tvLoginDefaultFocus(
        _ focus: FocusState<TVLoginFocus?>.Binding,
        phase: TVLoginPhase
    ) -> some View {
        if let preferredFocus = TVLoginNavigationPolicy.preferredFocus(for: phase) {
            defaultFocus(focus, preferredFocus, priority: .userInitiated)
        } else {
            self
        }
    }
}

#Preview("TV Login") {
    TVLoginView(dependencies: ReelFinPreviewFactory.dependencies(authenticated: false)) { _ in }
}
#endif
