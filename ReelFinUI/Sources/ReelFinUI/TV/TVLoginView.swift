#if os(tvOS)
import Shared
import SwiftUI

public struct TVLoginView: View {
    @StateObject private var loginVM: LoginViewModel
    @StateObject private var quickConnectVM: QuickConnectViewModel
    @FocusState private var focus: TVFocus?
    @State private var phase: TVPhase = .landing
    @State private var signInPath: TVSignInPath = .quickConnect
    @State private var appeared = false
    @State private var successBounce = false

    private let onLogin: (UserSession) -> Void

    public init(dependencies: ReelFinDependencies, onLogin: @escaping (UserSession) -> Void) {
        _loginVM = StateObject(wrappedValue: LoginViewModel(dependencies: dependencies))
        _quickConnectVM = StateObject(wrappedValue: QuickConnectViewModel(dependencies: dependencies))
        self.onLogin = onLogin
    }

    public var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.12).ignoresSafeArea()
            glow.ignoresSafeArea()

            GeometryReader { geo in
                stageView
                    .frame(width: min(geo.size.width * 0.58, 840))
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            quickConnectVM.onAuthenticated = { session in
                handleSuccess(session)
            }
            withAnimation(.easeOut(duration: 0.35)) {
                appeared = true
            }
        }
        .onChange(of: loginVM.serverURLText) { _, _ in
            loginVM.serverURLDidChange()
        }
    }

    private var glow: some View {
        GeometryReader { geo in
            Circle()
                .fill(glowColor.opacity(0.22))
                .frame(width: geo.size.width * 0.7, height: geo.size.width * 0.7)
                .blur(radius: 180)
                .offset(x: geo.size.width * 0.15, y: -geo.size.height * 0.15)
                .animation(.easeInOut(duration: 0.6), value: phase)
        }
    }

    private var glowColor: Color {
        switch phase {
        case .landing, .server:
            return Color(red: 0.2, green: 0.45, blue: 1.0)
        case .credentials, .submitting:
            return Color(red: 0.55, green: 0.3, blue: 1.0)
        case .quickConnect:
            return Color(red: 0.15, green: 0.65, blue: 1.0)
        case .success:
            return Color(red: 0.2, green: 0.85, blue: 0.6)
        }
    }

    @ViewBuilder
    private var stageView: some View {
        switch phase {
        case .landing:
            landingStage
        case .server:
            serverStage
        case .credentials:
            credentialsStage
        case .submitting:
            submittingStage
        case .quickConnect:
            quickConnectStage
        case .success:
            successStage
        }
    }

    private var landingStage: some View {
        TVStageContainer {
            HStack(spacing: 18) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
                Text("ReelFin")
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(-1)
            }

            Spacer().frame(height: 8)

            Text("Set up ReelFin the Apple TV way.")
                .font(.system(size: 28, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))

            if loginVM.hasSavedServer {
                TVChip(
                    text: loginVM.serverURLText,
                    icon: "checkmark.seal.fill",
                    tint: Color(red: 0.2, green: 0.85, blue: 0.6)
                )
            }

            Spacer().frame(height: 12)

            VStack(spacing: 16) {
                TVButton(
                    title: loginVM.hasSavedServer ? "Quick Connect" : "Set Up Quick Connect",
                    icon: "qrcode.viewfinder"
                ) {
                    beginQuickConnectFlow()
                }
                .focused($focus, equals: .primary)

                TVButton(
                    title: loginVM.hasSavedServer ? "Sign In with Password" : "Use Password",
                    icon: "person.fill",
                    style: .secondary
                ) {
                    beginPasswordFlow()
                }
                .focused($focus, equals: .alt)

                if loginVM.hasSavedServer {
                    TVButton(title: "Choose Another Server", icon: "server.rack", style: .ghost) {
                        go(.server)
                        focus = .textA
                    }
                    .focused($focus, equals: .back)
                }
            }
        }
        .onAppear {
            focus = .primary
        }
    }

    private var serverStage: some View {
        TVStageContainer {
            stageHeader(
                title: signInPath == .quickConnect ? "Quick Connect" : "Server",
                subtitle: signInPath == .quickConnect
                    ? "Enter your Jellyfin server address. ReelFin will fetch the pairing code next."
                    : "Enter your Jellyfin server address before signing in."
            )

            TextField("https://jellyfin.example.com", text: $loginVM.serverURLText)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .focused($focus, equals: .textA)
                .tvField()

            feedbackRow(
                loading: loginVM.isTestingConnection,
                loadingText: "Checking…",
                error: loginVM.serverErrorMessage,
                info: loginVM.serverMessage
            )

            HStack(spacing: 16) {
                TVButton(title: "Back", icon: "chevron.left", style: .ghost) {
                    go(.landing)
                }
                .focused($focus, equals: .back)

                TVButton(
                    title: signInPath.primaryActionTitle,
                    icon: signInPath.primaryActionSymbol,
                    isLoading: loginVM.isTestingConnection
                ) {
                    continueFromServer()
                }
                .focused($focus, equals: .primary)
                .disabled(!loginVM.canAdvanceFromServer)

                TVButton(
                    title: signInPath.alternateActionTitle,
                    icon: signInPath.alternateActionSymbol,
                    style: .secondary
                ) {
                    toggleSignInPath()
                }
                .focused($focus, equals: .alt)
            }
        }
        .onAppear {
            focus = .textA
        }
    }

    private var credentialsStage: some View {
        TVStageContainer {
            stageHeader(title: "Sign in", subtitle: serverHost)

            VStack(spacing: 14) {
                TextField("Username", text: $loginVM.username)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .focused($focus, equals: .textA)
                    .tvField()

                SecureField("Password", text: $loginVM.password)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .focused($focus, equals: .textB)
                    .tvField()
            }

            feedbackRow(loading: false, loadingText: "", error: loginVM.authErrorMessage, info: nil)

            HStack(spacing: 16) {
                TVButton(title: "Back", icon: "chevron.left", style: .ghost) {
                    loginVM.clearAuthError()
                    go(.server)
                }
                .focused($focus, equals: .back)

                TVButton(title: "Sign in", icon: "arrow.right") {
                    submitCredentials()
                }
                .focused($focus, equals: .primary)
                .disabled(!loginVM.canSubmitCredentials)

                TVButton(title: "Use Quick Connect", icon: "qrcode", style: .secondary) {
                    beginQuickConnectFlow()
                }
                .focused($focus, equals: .alt)
            }
        }
        .onAppear {
            focus = .textA
        }
    }

    private var submittingStage: some View {
        TVStageContainer {
            stageHeader(title: "Signing in…", subtitle: serverHost)
            ProgressView()
                .tint(.white)
                .scaleEffect(1.4)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        }
    }

    private var quickConnectStage: some View {
        TVStageContainer {
            stageHeader(
                title: "Quick Connect",
                subtitle: "Open Jellyfin on your phone or tablet, go to Dashboard → Quick Connect, and enter this code."
            )

            quickConnectCodeArea

            TVButton(title: "Use password instead", icon: "keyboard", style: .ghost) {
                quickConnectVM.cancel()
                signInPath = .credentials
                go(.credentials)
            }
            .focused($focus, equals: .back)
        }
        .onAppear {
            focus = .back
        }
    }

    @ViewBuilder
    private var quickConnectCodeArea: some View {
        switch quickConnectVM.state {
        case .idle, .loading:
            HStack(spacing: 14) {
                ProgressView().tint(.white)
                Text("Requesting code…")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(minHeight: 90)

        case let .awaitingApproval(code):
            VStack(alignment: .leading, spacing: 20) {
                Text(spacedCode(code))
                    .font(.system(size: 80, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(8)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 20)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.22), lineWidth: 2)
                    }

                HStack(spacing: 10) {
                    ProgressView().tint(.white.opacity(0.55)).scaleEffect(0.8)
                    Text("Waiting for approval on Jellyfin…")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

        case let .error(message):
            Text(message)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color(red: 1.0, green: 0.38, blue: 0.38))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var successStage: some View {
        TVStageContainer {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.6))
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(successBounce ? 1.0 : 0.5)
                    .opacity(successBounce ? 1 : 0)

                Text("Connected!")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(successBounce ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.35)) {
                successBounce = true
            }
        }
    }

    private func stageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 24, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 680, alignment: .leading)
        }
    }

    @ViewBuilder
    private func feedbackRow(loading: Bool, loadingText: String, error: String?, info: String?) -> some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView().tint(.white.opacity(0.75)).scaleEffect(0.8)
                Text(loadingText)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(height: 44)
        } else if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.38, blue: 0.38))
                .frame(height: 44)
        } else if let info {
            Label(info, systemImage: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.6))
                .frame(height: 44)
        } else {
            Color.clear.frame(height: 44)
        }
    }

    private func go(_ newPhase: TVPhase) {
        withAnimation(.smooth(duration: 0.28)) {
            phase = newPhase
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
            focus = .textA
        } else {
            go(.server)
            focus = .textA
        }
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
            try? await Task.sleep(nanoseconds: 800_000_000)
            onLogin(session)
        }
    }

    private var serverHost: String {
        URL(string: loginVM.serverURLText.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "Jellyfin"
    }

    private func spacedCode(_ code: String) -> String {
        guard code.count == 4 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 2)
        return String(code[..<mid]) + "  " + String(code[mid...])
    }
}

private enum TVPhase {
    case landing
    case server
    case credentials
    case submitting
    case quickConnect
    case success
}

private enum TVFocus {
    case primary
    case alt
    case back
    case textA
    case textB
}

private enum TVSignInPath {
    case quickConnect
    case credentials

    var alternate: Self {
        switch self {
        case .quickConnect:
            return .credentials
        case .credentials:
            return .quickConnect
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .quickConnect:
            return "Get Code"
        case .credentials:
            return "Continue"
        }
    }

    var primaryActionSymbol: String {
        switch self {
        case .quickConnect:
            return "qrcode"
        case .credentials:
            return "person.fill"
        }
    }

    var alternateActionTitle: String {
        switch self {
        case .quickConnect:
            return "Use Password"
        case .credentials:
            return "Use Quick Connect"
        }
    }

    var alternateActionSymbol: String {
        switch self {
        case .quickConnect:
            return "keyboard"
        case .credentials:
            return "qrcode"
        }
    }
}

private struct TVStageContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            content
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 38)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 38, x: 0, y: 18)
    }
}

private struct TVButton: View {
    enum Style {
        case primary
        case secondary
        case ghost
    }

    let title: String
    let icon: String
    var style: Style = .primary
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        switch style {
        case .primary:
            baseButton
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color.black)
        case .secondary:
            baseButton
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.18))
                .foregroundStyle(Color.white)
        case .ghost:
            baseButton
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.08))
                .foregroundStyle(Color.white.opacity(0.92))
        }
    }

    private var baseButton: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonBorderShape(.roundedRectangle(radius: 24))
        .controlSize(.large)
        .disabled(isLoading)
    }
}

private struct TVChip: View {
    let text: String
    let icon: String
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 18, weight: .semibold))
            Text(text)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }
}

private extension View {
    func tvField() -> some View {
        self
            .padding(.horizontal, 24)
            .frame(height: 76)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1.5)
            }
    }
}

#Preview("TV Login") {
    TVLoginView(dependencies: ReelFinPreviewFactory.dependencies(authenticated: false)) { _ in }
}
#endif
