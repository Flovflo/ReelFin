#if os(tvOS)
import Shared
import SwiftUI

struct TVLandingStageView: View {
    let buttonWidth: CGFloat
    let hasSavedServer: Bool
    let savedServerText: String
    let onQuickConnect: () -> Void
    let onPassword: () -> Void
    let onChooseServer: () -> Void
    let focus: FocusState<TVLoginFocus?>.Binding

    var body: some View {
        HStack(alignment: .center, spacing: 56) {
            VStack(alignment: .leading, spacing: 22) {
                TVLoginStageHeading(
                    title: "Connect your server",
                    subtitle: "Pair ReelFin with Jellyfin for a fast, native Apple TV library.",
                    titleSize: 56
                )

                if hasSavedServer {
                    TVLoginChip(
                        text: savedServerText,
                        icon: "checkmark.seal.fill",
                        tint: Color(red: 0.34, green: 0.86, blue: 0.66)
                    )
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.vertical, 8)

            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    TVLoginActionButton(title: "Quick Connect", icon: "qrcode.viewfinder", action: onQuickConnect)
                        .focused(focus, equals: .landingQuickConnect)
                        .accessibilityLabel("Quick Connect")
                        .accessibilityIdentifier("tv_login_quick_connect")

                    TVLoginActionButton(title: "Use Password", icon: "person.fill", style: .secondary, action: onPassword)
                        .focused(focus, equals: .landingPassword)
                        .accessibilityLabel("Use Password")
                        .accessibilityIdentifier("tv_login_use_password")

                    if hasSavedServer {
                        TVLoginActionButton(title: "Choose Another Server", icon: "server.rack", style: .tertiary, action: onChooseServer)
                            .focused(focus, equals: .landingChooseServer)
                            .accessibilityLabel("Choose Another Server")
                            .accessibilityIdentifier("tv_login_choose_server")
                    }
                }
            }
            .frame(width: buttonWidth)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Connect your server")
        .accessibilityIdentifier("tv_login_stage_landing")
    }
}

struct TVServerStageView: View {
    @Binding var serverURLText: String
    let signInPath: TVLoginSignInPath
    let isTestingConnection: Bool
    let canContinue: Bool
    let serverMessage: String?
    let serverErrorMessage: String?
    let onBack: () -> Void
    let onContinue: () -> Void
    let onTogglePath: () -> Void
    let focus: FocusState<TVLoginFocus?>.Binding

    var body: some View {
        let isServerFieldFocused = focus.wrappedValue == .serverAddress

        VStack(alignment: .leading, spacing: 24) {
            TVLoginStageHeading(
                title: signInPath == .quickConnect ? "Enter your server" : "Server address",
                subtitle: signInPath == .quickConnect
                    ? "Use your Jellyfin address to get a Quick Connect code."
                    : "Enter your Jellyfin address before signing in."
            )

            TextField(
                "",
                text: $serverURLText,
                prompt: Text("https://jellyfin.example.com")
                    .foregroundStyle(isServerFieldFocused ? Color.black.opacity(0.34) : Color.white.opacity(0.34))
            )
                .font(.system(size: 29, weight: .semibold, design: .monospaced))
                .foregroundStyle(isServerFieldFocused ? Color.black.opacity(0.82) : Color.white.opacity(0.96))
                .focused(focus, equals: .serverAddress)
                .tvLoginFieldSurface(focused: isServerFieldFocused)
                .accessibilityLabel("Jellyfin server address")
                .accessibilityIdentifier("tv_login_server_field")

            TVServerStatusView(
                isLoading: isTestingConnection,
                message: serverMessage,
                error: serverErrorMessage
            )

            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    TVLoginActionButton(title: "Back", icon: "chevron.left", style: .tertiary, action: onBack)
                        .focused(focus, equals: .serverBack)
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("tv_login_server_back")

                    TVLoginActionButton(
                        title: signInPath.primaryActionTitle,
                        icon: signInPath.primaryActionSymbol,
                        isLoading: isTestingConnection,
                        isEnabled: canContinue,
                        action: onContinue
                    )
                    .focused(focus, equals: .serverPrimary)
                    .accessibilityLabel(signInPath.primaryActionTitle)
                    .accessibilityIdentifier("tv_login_server_primary")

                    TVLoginActionButton(
                        title: signInPath.alternateActionTitle,
                        icon: signInPath.alternateActionSymbol,
                        style: .secondary,
                        action: onTogglePath
                    )
                    .focused(focus, equals: .serverAlternate)
                    .accessibilityLabel(signInPath.alternateActionTitle)
                    .accessibilityIdentifier("tv_login_server_alternate")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(signInPath == .quickConnect ? "Enter your server" : "Server address")
        .accessibilityIdentifier("tv_login_stage_server")
    }
}

struct TVCredentialsStageView: View {
    @Binding var username: String
    @Binding var password: String
    let serverHost: String
    let authErrorMessage: String?
    let canSubmit: Bool
    let onBack: () -> Void
    let onSubmit: () -> Void
    let onQuickConnect: () -> Void
    let focus: FocusState<TVLoginFocus?>.Binding

    var body: some View {
        let isUsernameFocused = focus.wrappedValue == .credentialsUsername
        let isPasswordFocused = focus.wrappedValue == .credentialsPassword

        VStack(alignment: .leading, spacing: 24) {
            TVLoginStageHeading(
                title: "Sign in",
                subtitle: "Use the account you already use on \(serverHost)."
            )

            VStack(spacing: 16) {
                TextField(
                    "",
                    text: $username,
                    prompt: Text("Username")
                        .foregroundStyle(isUsernameFocused ? Color.black.opacity(0.34) : Color.white.opacity(0.34))
                )
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(isUsernameFocused ? Color.black.opacity(0.82) : Color.white.opacity(0.96))
                    .focused(focus, equals: .credentialsUsername)
                    .tvLoginFieldSurface(focused: isUsernameFocused)
                    .accessibilityLabel("Jellyfin username")
                    .accessibilityIdentifier("tv_login_username_field")

                SecureField(
                    "",
                    text: $password,
                    prompt: Text("Password")
                        .foregroundStyle(isPasswordFocused ? Color.black.opacity(0.34) : Color.white.opacity(0.34))
                )
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(isPasswordFocused ? Color.black.opacity(0.82) : Color.white.opacity(0.96))
                    .focused(focus, equals: .credentialsPassword)
                    .tvLoginFieldSurface(focused: isPasswordFocused)
                    .accessibilityLabel("Jellyfin password")
                    .accessibilityIdentifier("tv_login_password_field")
            }

            TVServerStatusView(isLoading: false, message: nil, error: authErrorMessage)

            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    TVLoginActionButton(title: "Back", icon: "chevron.left", style: .tertiary, action: onBack)
                        .focused(focus, equals: .credentialsBack)
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("tv_login_credentials_back")

                    TVLoginActionButton(title: "Sign In", icon: "arrow.right", isEnabled: canSubmit, action: onSubmit)
                        .focused(focus, equals: .credentialsSubmit)
                        .accessibilityLabel("Sign In")
                        .accessibilityIdentifier("tv_login_credentials_submit")

                    TVLoginActionButton(title: "Quick Connect", icon: "qrcode", style: .secondary, action: onQuickConnect)
                        .focused(focus, equals: .credentialsQuickConnect)
                        .accessibilityLabel("Quick Connect")
                        .accessibilityIdentifier("tv_login_credentials_quick_connect")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sign in")
        .accessibilityIdentifier("tv_login_stage_credentials")
    }
}

struct TVQuickConnectStageView: View {
    let state: QuickConnectViewModel.State
    let onUsePassword: () -> Void
    let focus: FocusState<TVLoginFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            TVLoginStageHeading(
                title: "Approve on another device",
                subtitle: "Open Jellyfin on iPhone or the web, then enter this code."
            )

            TVQuickConnectCodeView(state: state)

            GlassEffectContainer(spacing: 16) {
                TVLoginActionButton(title: "Use Password Instead", icon: "keyboard", style: .tertiary, action: onUsePassword)
                    .focused(focus, equals: .quickConnectUsePassword)
                    .accessibilityLabel("Use Password Instead")
                    .accessibilityIdentifier("tv_login_quick_connect_use_password")
                    .frame(width: 420)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Approve on another device")
        .accessibilityIdentifier("tv_login_stage_quick_connect")
    }
}

struct TVSubmittingStageView: View {
    let serverHost: String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            TVLoginStageHeading(
                title: "Signing in",
                subtitle: "Verifying your account on \(serverHost)."
            )

            HStack(spacing: 14) {
                ProgressView().tint(.white).scaleEffect(1.2)
                Text("One moment…")
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
            }
            .frame(height: 82)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Signing in")
        .accessibilityIdentifier("tv_login_stage_submitting")
    }
}

struct TVSuccessStageView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var animateIn: Bool

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color(red: 0.34, green: 0.86, blue: 0.66))
                .symbolRenderingMode(.hierarchical)
                .scaleEffect(reduceMotion ? 1 : (animateIn ? 1 : 0.70))
                .opacity(animateIn ? 1 : 0)

            VStack(alignment: .leading, spacing: 8) {
                Text("Connected")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.white)
                Text("Your library is ready on Apple TV.")
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Connected")
        .accessibilityIdentifier("tv_login_stage_success")
    }
}

private struct TVServerStatusView: View {
    let isLoading: Bool
    let message: String?
    let error: String?

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 12) {
                    ProgressView().tint(.white.opacity(0.75)).scaleEffect(0.88)
                    Text("Checking server…")
                        .foregroundStyle(.white.opacity(0.72))
                }
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(red: 1.0, green: 0.44, blue: 0.44))
            } else if let message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.34, green: 0.86, blue: 0.66))
            } else {
                Color.clear
            }
        }
        .font(.system(size: 21, weight: .semibold))
        .frame(height: 44, alignment: .leading)
    }
}

private struct TVQuickConnectCodeView: View {
    let state: QuickConnectViewModel.State

    var body: some View {
        switch state {
        case .idle, .loading:
            HStack(spacing: 14) {
                ProgressView().tint(.white).scaleEffect(1.0)
                Text("Requesting code…")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
            }
            .frame(minHeight: 110, alignment: .leading)
        case let .awaitingApproval(code):
            let displayCode = formattedCode(code)
            VStack(alignment: .leading, spacing: 18) {
                Text(displayCode)
                    .font(.system(size: 88, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(10)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 22)
                    .background {
                        Color.clear.reelFinGlassRoundedRect(
                            cornerRadius: 30,
                            tint: Color.white.opacity(0.10),
                            stroke: Color.white.opacity(0.16),
                            shadowOpacity: 0.16,
                            shadowRadius: 18,
                            shadowYOffset: 10
                        )
                    }
                    .accessibilityLabel(displayCode)
                    .accessibilityIdentifier("tv_login_quick_connect_code")

                Label("Waiting for approval in Jellyfin…", systemImage: "iphone.and.arrow.forward")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.64))
            }
        case let .error(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.44, blue: 0.44))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func formattedCode(_ code: String) -> String {
        guard code.count == 4 else { return code }
        let midpoint = code.index(code.startIndex, offsetBy: 2)
        return String(code[..<midpoint]) + "  " + String(code[midpoint...])
    }
}
#endif
